#!/usr/bin/env bash
# swapman.sh - Advanced Swap and ZRAM Manager for Linux

VERSION="1.0.0"
STATE_DIR="/var/lib/swapman"
STATE_FILE="$STATE_DIR/swaps.tsv"
LOG_FILE="/var/log/swapman.log"
CONFIG_FILE="/etc/swapman.conf"

# Defaults
DEFAULT_SIZE="" # Will be calculated
DEFAULT_PRIO_ZRAM=100
DEFAULT_PRIO_DISK=0
DEFAULT_ZRAM_COMP_ALG="lz4"
DEFAULT_TUNE_PROFILE="server"

ACTION=""
ARG_BACKEND=""
ARG_SIZE=""
ARG_PATH=""
ARG_DEVICE=""
ARG_PRIO=""
ARG_FORCE=0
ARG_YES=0
ARG_TUNE=""
ARG_INTERVAL=5

# Colors
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

log_msg() {
    local level="$1"
    local msg="$2"
    local ts=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; log_msg "INFO" "$1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; log_msg "SUCCESS" "$1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; log_msg "WARN" "$1"; }
echo_err() { echo -e "${RED}[ERROR]${NC} $1" >&2; log_msg "ERROR" "$1"; }
die() { echo_err "$1"; return 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_err "This script must be run as root."
        return 1
    fi
}

init_state() {
    mkdir -p "$STATE_DIR" || die "Failed to create state directory" || return 1
    chmod 755 "$STATE_DIR"
    touch "$STATE_FILE" || die "Failed to create state file" || return 1
    chmod 644 "$STATE_FILE"
    touch "$LOG_FILE" || die "Failed to create log file" || return 1
}

prompt_confirm() {
    local prompt="$1"
    if [[ $ARG_YES -eq 1 ]]; then return 0; fi
    while true; do
        read -r -p "$(echo -e "${BOLD}${prompt} [y/N]:${NC} ")" choice || return 1
        case "$choice" in
            [Yy]* ) return 0 ;;
            [Nn]* | "" ) return 1 ;;
            * ) echo "Please answer yes or no." ;;
        esac
    done
}

parse_size() {
    local size_str="${1^^}"
    local size_val
    local size_unit

    if [[ "$size_str" =~ ^([0-9]+)([KMGT]?)$ ]]; then
        size_val="${BASH_REMATCH[1]}"
        size_unit="${BASH_REMATCH[2]}"
        case "$size_unit" in
            K) echo $((size_val * 1024)) ;;
            M) echo $((size_val * 1024 * 1024)) ;;
            G) echo $((size_val * 1024 * 1024 * 1024)) ;;
            T) echo $((size_val * 1024 * 1024 * 1024 * 1024)) ;;
            *) echo "$size_val" ;;
        esac
    else
        echo "-1"
    fi
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$((bytes / 1024))K"
    elif [[ $bytes -lt 1073741824 ]]; then
        echo "$((bytes / 1048576))M"
    else
        echo "$((bytes / 1073741824))G"
    fi
}

get_mem_total() {
    local mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((mem_kb * 1024))
}

calc_recommended_swap() {
    local mem_total=$(get_mem_total)
    local mem_mb=$((mem_total / 1024 / 1024))

    if [[ $mem_mb -lt 2048 ]]; then
        echo $((mem_mb * 2))"M"
    elif [[ $mem_mb -le 8192 ]]; then
        echo ${mem_mb}"M"
    else
        echo $((mem_mb / 2))"M"
    fi
}

detect_fs() {
    local target_dir="$1"
    if [[ -d "$target_dir" ]]; then
        stat -f --format=%T "$target_dir" 2>/dev/null
    else
        stat -f --format=%T "$(dirname "$target_dir")" 2>/dev/null
    fi
}

save_state() {
    local type="$1"
    local path="$2"
    local size="$3"
    local prio="$4"
    local persist="$5"
    local ts=$(date '+%s')

    remove_state "$path"
    echo -e "$type\t$path\t$size\t$prio\t$persist\t$ts" >> "$STATE_FILE"
}

remove_state() {
    local path="$1"
    if [[ -f "$STATE_FILE" ]]; then
        local tmp_state=$(mktemp)
        awk -F$'\t' -v p="$path" '$2 != p' "$STATE_FILE" > "$tmp_state"
        mv "$tmp_state" "$STATE_FILE"
        chmod 644 "$STATE_FILE"
    fi
}

add_fstab() {
    local path="$1"
    local prio="$2"
    local fstab_path="${path// /\\040}"
    local entry="$fstab_path none swap sw,pri=$prio 0 0"

    if grep -q "[[:space:]]${path}[[:space:]]" /etc/fstab; then
        local tmp_fstab=$(mktemp)
        awk -v p="$path" '$1 == p && $3 == "swap" {next} {print}' /etc/fstab > "$tmp_fstab"
        cat "$tmp_fstab" > /etc/fstab
        rm -f "$tmp_fstab"
    fi
    echo "$entry" >> /etc/fstab
}

remove_fstab() {
    local path="$1"
    if grep -q "[[:space:]]${path}[[:space:]]" /etc/fstab; then
        local tmp_fstab=$(mktemp)
        awk -v p="$path" '$1 == p && $3 == "swap" {next} {print}' /etc/fstab > "$tmp_fstab"
        cat "$tmp_fstab" > /etc/fstab
        rm -f "$tmp_fstab"
        echo_info "Removed fstab entry for $path"
    fi
}

do_create_swapfile() {
    local path="${ARG_PATH:-/swapfile}"
    local size_str="${ARG_SIZE:-$(calc_recommended_swap)}"
    local prio="${ARG_PRIO:-$DEFAULT_PRIO_DISK}"

    local size_bytes=$(parse_size "$size_str")
    if [[ $size_bytes -le 0 ]]; then die "Invalid size: $size_str" || return 1; fi

    if [[ -e "$path" ]]; then die "File $path already exists." || return 1; fi

    local fs_type=$(detect_fs "$path")
    echo_info "Target filesystem: $fs_type"

    # Check free space
    local dir=$(dirname "$path")
    local free_kb=$(df -Pk "$dir" | awk 'NR==2 {print $4}')
    local free_bytes=$((free_kb * 1024))

    if [[ $size_bytes -ge $((free_bytes * 9 / 10)) ]]; then
        echo_warn "Creating this swapfile leaves less than 10% free space on $dir"
        prompt_confirm "Continue anyway?" || { echo "Aborted."; return 1; }
    fi

    echo_info "Allocating swapfile at $path (${size_str})..."

    if [[ "$fs_type" == "btrfs" ]]; then
        echo_warn "Btrfs detected. Creating file with NOCOW attributes..."
        touch "$path" || { die "Failed to create $path"; return 1; }
        chattr +C "$path" 2>/dev/null || echo_warn "Failed to set NOCOW flag, swapfile creation might fail."
        dd if=/dev/zero of="$path" bs=1M count=$((size_bytes / 1024 / 1024)) status=progress || { die "Failed to allocate space using dd"; return 1; }
    else
        fallocate -l "$size_bytes" "$path" || {
            echo_warn "fallocate failed, falling back to dd..."
            dd if=/dev/zero of="$path" bs=1M count=$((size_bytes / 1024 / 1024)) status=progress || { die "Failed to allocate space"; return 1; }
        }
    fi

    chmod 600 "$path" || { die "Failed to secure $path"; return 1; }
    mkswap "$path" || { die "mkswap failed on $path"; return 1; }
    swapon -p "$prio" "$path" || { die "swapon failed on $path"; return 1; }

    add_fstab "$path" "$prio"
    save_state "file" "$path" "$size_str" "$prio" "fstab"

    echo_success "Swapfile created and activated at $path"
}

do_create_zram() {
    local size_str="${ARG_SIZE:-$(calc_recommended_swap)}"
    local prio="${ARG_PRIO:-$DEFAULT_PRIO_ZRAM}"
    local size_bytes=$(parse_size "$size_str")

    if [[ $size_bytes -le 0 ]]; then die "Invalid size: $size_str" || return 1; fi

    modprobe zram || { die "Failed to load zram module."; return 1; }

    # Find free zram device
    local zram_dev=""
    for i in {0..9}; do
        if ! grep -q "/dev/zram$i" /proc/swaps; then
            zram_dev="/dev/zram$i"
            break
        fi
    done

    if [[ -z "$zram_dev" ]]; then die "No free zram devices found." || return 1; fi

    echo_info "Configuring $zram_dev (${size_str})..."

    # Check algorithms
    local algs=""
    local zram_name="${zram_dev##*/}"
    if [[ -f "/sys/block/${zram_name}/comp_algorithm" ]]; then
        algs=$(cat "/sys/block/${zram_name}/comp_algorithm")
        local chosen_alg="$DEFAULT_ZRAM_COMP_ALG"
        if echo "$algs" | grep -q "\[$chosen_alg\]" || echo "$algs" | grep -q "\b$chosen_alg\b"; then
            echo "$chosen_alg" > "/sys/block/${zram_name}/comp_algorithm" 2>/dev/null
        fi
    fi

    echo "$size_bytes" > "/sys/block/${zram_name}/disksize" || { die "Failed to set zram disksize"; return 1; }
    mkswap "$zram_dev" >/dev/null || { die "mkswap failed on $zram_dev"; return 1; }
    swapon -p "$prio" "$zram_dev" || { die "swapon failed on $zram_dev"; return 1; }

    # Persistence via systemd
    local unit_name="zram-swap-${zram_name}.service"
    local unit_file="/etc/systemd/system/$unit_name"

    cat << SYSTEMD_EOF > "$unit_file"
[Unit]
Description=ZRAM Swap on $zram_dev
After=multi-user.target

[Service]
Type=oneshot
ExecStartPre=/sbin/modprobe zram
ExecStartPre=-/bin/sh -c 'echo $DEFAULT_ZRAM_COMP_ALG > /sys/block/${zram_name}/comp_algorithm'
ExecStartPre=/bin/sh -c 'echo $size_bytes > /sys/block/${zram_name}/disksize'
ExecStartPre=/sbin/mkswap $zram_dev
ExecStart=/sbin/swapon -p $prio $zram_dev
ExecStop=/sbin/swapoff $zram_dev
ExecStopPost=/bin/sh -c 'echo 1 > /sys/block/${zram_name}/reset'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

    systemctl daemon-reload
    systemctl enable "$unit_name" >/dev/null 2>&1

    save_state "zram" "$zram_dev" "$size_str" "$prio" "systemd"
    echo_success "ZRAM swap activated on $zram_dev"
}

do_create_partition() {
    local dev="${ARG_DEVICE}"
    if [[ -z "$dev" ]]; then die "Device must be specified for partition swap (e.g. --device /dev/sdb1)" || return 1; fi

    if [[ ! -b "$dev" ]]; then die "$dev is not a block device." || return 1; fi

    local prio="${ARG_PRIO:-$DEFAULT_PRIO_DISK}"

    echo_warn "WARNING: This will format $dev as swap, DESTROYING all data on it."
    prompt_confirm "Are you absolutely sure?" || { echo "Aborted."; return 1; }

    mkswap "$dev" || { die "mkswap failed on $dev"; return 1; }
    swapon -p "$prio" "$dev" || { die "swapon failed on $dev"; return 1; }

    local size_kb=$(lsblk -b -n -o SIZE "$dev" | head -n1)
    local size_str=$(format_bytes "$size_kb")

    add_fstab "$dev" "$prio"
    save_state "partition" "$dev" "$size_str" "$prio" "fstab"

    echo_success "Partition swap activated on $dev"
}

do_create() {
    if [[ -z "$ARG_BACKEND" ]]; then
        echo_err "Backend must be specified: file, zram, or partition"
        return 1
    fi
    case "$ARG_BACKEND" in
        file) do_create_swapfile ;;
        zram) do_create_zram ;;
        partition) do_create_partition ;;
        *) die "Unknown backend: $ARG_BACKEND" || return 1 ;;
    esac
}

do_remove() {
    local path="$ARG_PATH"
    if [[ -z "$path" ]]; then die "Path must be specified to remove swap." || return 1; fi

    if ! grep -q "[[:space:]]${path}[[:space:]]" /proc/swaps; then
        echo_warn "Swap $path is not currently active."
    else
        local used_kb=$(grep "[[:space:]]${path}[[:space:]]" /proc/swaps | awk '{print $4}')
        if [[ -n "$used_kb" ]] && [[ "$used_kb" -gt 0 ]]; then
            local mem_free_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            if [[ "$used_kb" -gt "$mem_free_kb" ]]; then
                echo_warn "Swap $path is using $(format_bytes $((used_kb*1024))). There is only $(format_bytes $((mem_free_kb*1024))) available RAM."
                echo_warn "Disabling swap might trigger OOM killer."
                if [[ $ARG_FORCE -eq 0 ]]; then
                    die "Aborting for safety. Use --force to proceed anyway." || return 1
                fi
            else
                echo_warn "Swap $path is actively storing $(format_bytes $((used_kb*1024))). Disabling it will move data to RAM."
            fi
        fi

        echo_info "Disabling swap on $path... This may take time if data is being moved."
        swapoff "$path" || { die "Failed to swapoff $path"; return 1; }
        echo_success "Disabled swap on $path"
    fi

    local type=$(awk -F$'\t' -v p="$path" '$2 == p {print $1}' "$STATE_FILE" 2>/dev/null)

    if [[ "$type" == "zram" ]] || [[ "$path" == /dev/zram* ]]; then
        echo 1 > "/sys/block/${path##*/}/reset" 2>/dev/null
        local unit_name="zram-swap-${path##*/}.service"
        if systemctl is-enabled "$unit_name" >/dev/null 2>&1; then
            systemctl disable "$unit_name" >/dev/null 2>&1
            rm -f "/etc/systemd/system/$unit_name"
            systemctl daemon-reload
        fi
    elif [[ "$type" == "file" ]]; then
        remove_fstab "$path"
        prompt_confirm "Delete swapfile $path from disk?" && rm -f "$path" && echo_info "Deleted $path"
    elif [[ "$type" == "partition" ]]; then
        remove_fstab "$path"
    else
        remove_fstab "$path"
    fi

    remove_state "$path"
    echo_success "Swap $path fully removed."
}

do_list() {
    printf "%-10s %-20s %-10s %-10s %-10s %-10s\n" "TYPE" "PATH" "SIZE" "USED" "PRIO" "PERSIST"
    echo "-------------------------------------------------------------------------------"

    if [[ ! -f "$STATE_FILE" ]]; then return 0; fi

    while IFS=$'\t' read -r type path size prio persist ts; do
        if [[ -z "$type" ]]; then continue; fi
        local used="-"
        local actual_prio="$prio"

        if grep -q "[[:space:]]${path}[[:space:]]" /proc/swaps; then
            local sw_info=$(grep "[[:space:]]${path}[[:space:]]" /proc/swaps)
            local used_kb=$(echo "$sw_info" | awk '{print $4}')
            used=$(format_bytes $((used_kb * 1024)))
            actual_prio=$(echo "$sw_info" | awk '{print $5}')
        else
            used="(off)"
        fi

        printf "%-10s %-20s %-10s %-10s %-10s %-10s\n" "$type" "$path" "$size" "$used" "$actual_prio" "$persist"
    done < "$STATE_FILE"
}

do_tune() {
    local profile="${ARG_TUNE:-$DEFAULT_TUNE_PROFILE}"

    local swappiness
    local vfs_cache_pressure
    local dirty_ratio
    local dirty_background_ratio
    local min_free_kbytes=65536

    case "$profile" in
        server)
            swappiness=10
            vfs_cache_pressure=50
            dirty_ratio=10
            dirty_background_ratio=5
            ;;
        desktop)
            swappiness=60
            vfs_cache_pressure=100
            dirty_ratio=20
            dirty_background_ratio=10
            ;;
        aggressive)
            swappiness=100
            vfs_cache_pressure=100
            dirty_ratio=10
            dirty_background_ratio=5
            ;;
        *)
            die "Unknown tune profile: $profile. Use: server, desktop, aggressive." || return 1
            ;;
    esac

    echo_info "Applying '$profile' profile kernel parameters..."

    sysctl -w vm.swappiness=$swappiness
    sysctl -w vm.vfs_cache_pressure=$vfs_cache_pressure
    sysctl -w vm.dirty_ratio=$dirty_ratio
    sysctl -w vm.dirty_background_ratio=$dirty_background_ratio
    sysctl -w vm.min_free_kbytes=$min_free_kbytes

    # Persist
    local sysctl_file="/etc/sysctl.d/99-swapman.conf"
    cat << EOF > "$sysctl_file"
# Swapman tune profile: $profile
vm.swappiness=$swappiness
vm.vfs_cache_pressure=$vfs_cache_pressure
vm.dirty_ratio=$dirty_ratio
vm.dirty_background_ratio=$dirty_background_ratio
vm.min_free_kbytes=$min_free_kbytes
EOF

    echo_success "Kernel tuning applied and persisted to $sysctl_file"
}

do_watch() {
    echo "Starting swap monitoring (interval: ${ARG_INTERVAL}s). Press Ctrl+C to stop."
    while true; do
        clear
        echo "=== Swapman Monitor ==="
        local ts=$(date "+%Y-%m-%d %H:%M:%S")
        echo "Time: $ts"
        echo ""

        local mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        local mem_avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
        local mem_used=$((mem_total - mem_avail))
        local mem_pct=$(( mem_used * 100 / mem_total ))

        echo "RAM:  $(format_bytes $((mem_used*1024))) / $(format_bytes $((mem_total*1024))) ($mem_pct%)"

        local swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
        local swap_free=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
        local swap_used=$((swap_total - swap_free))
        local swap_pct=0
        if [[ $swap_total -gt 0 ]]; then
            swap_pct=$(( swap_used * 100 / swap_total ))
        fi

        echo "Swap: $(format_bytes $((swap_used*1024))) / $(format_bytes $((swap_total*1024))) ($swap_pct%)"

        echo ""
        echo "Active Swap Devices:"
        printf "%-20s %-15s %-15s %-10s\n" "PATH" "SIZE" "USED" "PRIO"
        tail -n +2 /proc/swaps | while read -r path type size used prio; do
            printf "%-20s %-15s %-15s %-10s\n" "$path" "$(format_bytes $((size*1024)))" "$(format_bytes $((used*1024)))" "$prio"
        done

        sleep "$ARG_INTERVAL"
    done
}

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Advanced Swap and ZRAM Manager for Linux.

Actions:
  --create                  Create a new swap
  --remove                  Remove an existing swap
  --list                    List managed swaps
  --tune PROFILE            Tune kernel parameters (server, desktop, aggressive)
  --watch                   Monitor swap usage
  -h, --help                Show this help message
  --version                 Show version

Create Options:
  --backend TYPE            Backend type: file, zram, partition
  --size SIZE               Size of swap (e.g., 2G). Defaults to recommended size based on RAM.
  --path PATH               Path for swapfile (default: /swapfile)
  --device DEV              Block device for partition swap (e.g., /dev/sdb1)
  --prio PRIO               Swap priority. (ZRAM default: 100, Disk default: 0)

Global Options:
  -y, --yes                 Skip confirmation prompts
  --force                   Force actions (e.g., unsafe swapoff)
  --interval SECONDS        Interval for --watch mode (default: 5)

Examples:
  $0 --create --backend zram --size 1G
  $0 --create --backend file --path /swapfile --size 2G
  $0 --remove --path /swapfile
  $0 --tune server
EOF
}

show_menu() {
    echo -e "${BOLD}Advanced Swap Manager${NC} - v$VERSION"
    echo "======================================"
    echo "1) Create ZRAM Swap"
    echo "2) Create Swapfile"
    echo "3) Create Swap Partition"
    echo "4) List Managed Swaps"
    echo "5) Remove Swap"
    echo "6) Tune Kernel Parameters"
    echo "7) Watch Swap Usage"
    echo "8) Exit"
    echo ""
    read -r -p "Select an option [1-8]: " menu_choice || return 0

    case "$menu_choice" in
        1)
            ARG_BACKEND="zram"
            read -r -p "Size (e.g., 1G) [$(calc_recommended_swap)]: " ARG_SIZE || return 0
            do_create_zram
            ;;
        2)
            ARG_BACKEND="file"
            read -r -p "Path [/swapfile]: " ARG_PATH || return 0
            read -r -p "Size (e.g., 2G) [$(calc_recommended_swap)]: " ARG_SIZE || return 0
            do_create_swapfile
            ;;
        3)
            ARG_BACKEND="partition"
            lsblk
            read -r -p "Device path (e.g., /dev/sdb1): " ARG_DEVICE || return 0
            do_create_partition
            ;;
        4)
            echo -e "\n${BOLD}--- Managed Swaps ---${NC}"
            do_list
            ;;
        5)
            echo -e "\n${BOLD}--- Remove Swap ---${NC}"
            if [[ ! -f "$STATE_FILE" ]] || [[ ! -s "$STATE_FILE" ]]; then
                echo "No managed swaps found."
                return 0
            fi
            local i=1
            local paths=()
            while IFS=$'\t' read -r type path size prio persist ts; do
                if [[ -n "$path" ]]; then
                    paths[$i]="$path"
                    echo "$i) $type: $path ($size)"
                    i=$((i+1))
                fi
            done < "$STATE_FILE"
            echo "0) Cancel"
            read -r -p "Select swap to remove [0-$((i-1))]: " rm_choice || return 0
            if [[ "$rm_choice" =~ ^[0-9]+$ ]] && [[ "$rm_choice" -gt 0 ]] && [[ "$rm_choice" -lt "$i" ]]; then
                ARG_PATH="${paths[$rm_choice]}"
                do_remove
            fi
            ;;
        6)
            echo -e "\n${BOLD}--- Tune Kernel ---${NC}"
            echo "Profiles: server (conservative), desktop (responsive), aggressive"
            read -r -p "Profile [server]: " ARG_TUNE || return 0
            do_tune
            ;;
        7)
            do_watch
            ;;
        8)
            return 0
            ;;
        *)
            echo_err "Invalid choice."
            ;;
    esac

    echo ""
    read -r -p "Press Enter to continue..." || return 0
    show_menu
}

main() {
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
            print_help
            return 0
        elif [[ "$arg" == "--version" ]]; then
            echo "swapman.sh version $VERSION"
            return 0
        fi
    done

    if [[ $# -eq 0 ]]; then
        check_root || return 1
        init_state || return 1
        show_menu
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --create) ACTION="create"; shift ;;
            --remove) ACTION="remove"; shift ;;
            --list) ACTION="list"; shift ;;
            --tune) ACTION="tune"; shift ;;
            --watch) ACTION="watch"; shift ;;

            --backend) ARG_BACKEND="$2"; shift 2 || shift ;;
            --size) ARG_SIZE="$2"; shift 2 || shift ;;
            --path) ARG_PATH="$2"; shift 2 || shift ;;
            --device) ARG_DEVICE="$2"; shift 2 || shift ;;
            --prio) ARG_PRIO="$2"; shift 2 || shift ;;
            --interval) ARG_INTERVAL="$2"; shift 2 || shift ;;

            -y|--yes) ARG_YES=1; shift ;;
            --force) ARG_FORCE=1; shift ;;

            *)
                if [[ "$ACTION" == "tune" && -z "$ARG_TUNE" && ! "$1" =~ ^-- ]]; then
                    ARG_TUNE="$1"; shift
                else
                    echo_err "Unknown option: $1"; print_help; return 1
                fi
                ;;
        esac
    done

    if [[ "$ACTION" != "list" ]] && [[ "$ACTION" != "watch" ]]; then
        check_root || return 1
    fi

    if [[ "$ACTION" == "list" ]] && [[ $EUID -ne 0 ]] && [[ ! -d "$STATE_DIR" ]]; then
        do_list
        return 0
    fi

    init_state || return 1

    case "$ACTION" in
        create) do_create ;;
        remove) do_remove ;;
        list) do_list ;;
        tune) do_tune ;;
        watch) do_watch ;;
        *) echo_err "No action specified."; print_help; return 1 ;;
    esac
}

main "$@"
