#!/usr/bin/env bash
# ramdisk.sh - Advanced RAM disk (tmpfs) creator for Linux

# --- Configuration & Defaults ---
VERSION="1.0.0"
STATE_DIR="/var/lib/ramdisk-creator"
STATE_FILE="$STATE_DIR/state.tsv"
LOG_FILE="/var/log/ramdisk-creator.log"
CONFIG_FILE_SYSTEM="/etc/ramdisk-creator.conf"

DEFAULT_SIZE="512M"
DEFAULT_MOUNT_PREFIX="/mnt/ramdisk"
SAFETY_CAP_PERCENT=50
WARN_CAP_PERCENT=30
DEFAULT_PERMS="1777"
DEFAULT_PERSIST="none"

# --- Globals for State ---
ACTION=""
ARG_SIZE=""
ARG_MOUNT=""
ARG_LABEL=""
ARG_PERMS=""
ARG_USER=""
ARG_PERSIST=""
ARG_FORCE=0
ARG_DRY_RUN=0
ARG_JSON=0
ARG_YES=0

# --- Colors & Logging ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    YELLOW="\033[0;33m"
    BLUE="\033[0;34m"
    BOLD="\033[1m"
    NC="\033[0m"
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    NC=""
fi

log_msg() {
    local level="$1"
    local msg="$2"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$level] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; log_msg "INFO" "$1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; log_msg "SUCCESS" "$1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; log_msg "WARN" "$1"; }
echo_err() { echo -e "${RED}[ERROR]${NC} $1" >&2; log_msg "ERROR" "$1"; }
die() { echo_err "$1"; return 1; }

# --- Load Config ---
load_config() {
    if [[ -f "$CONFIG_FILE_SYSTEM" ]]; then
        source "$CONFIG_FILE_SYSTEM"
    fi
}

# --- Helper Functions ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo_err "This script must be run as root."
        if [[ -t 1 ]]; then
            echo_info "Try running with sudo."
        fi
        return 1
    fi
}

init_state_dir() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR" || die "Failed to create state directory $STATE_DIR" || return 1
        chmod 755 "$STATE_DIR"
    fi
    if [[ ! -f "$STATE_FILE" ]]; then
        touch "$STATE_FILE" || die "Failed to create state file $STATE_FILE" || return 1
        chmod 644 "$STATE_FILE"
    fi
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" || die "Failed to create log file $LOG_FILE" || return 1
        chmod 644 "$LOG_FILE"
    fi
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
            *) echo "$size_val" ;; # assume bytes
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

get_mem_available() {
    local mem_kb
    mem_kb=$(grep MemAvailable /proc/meminfo | awk "{print \$2}")
    if [[ -z "$mem_kb" ]]; then
        # Fallback to MemFree + Cached
        local mem_free
        local mem_cached
        mem_free=$(grep MemFree /proc/meminfo | awk "{print \$2}")
        mem_cached=$(grep "^Cached" /proc/meminfo | awk "{print \$2}")
        mem_kb=$((mem_free + mem_cached))
    fi
    echo $((mem_kb * 1024))
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

# --- State Management ---
save_state() {
    local mount="$1"
    local size="$2"
    local label="$3"
    local user="$4"
    local persist="$5"
    local ts
    ts=$(date "+%s")

    # Remove old entry if exists
    remove_state "$mount"

    echo -e "$mount\t$size\t$label\t$ts\t$user\t$persist" >> "$STATE_FILE"
}

remove_state() {
    local mount="$1"
    if [[ -f "$STATE_FILE" ]]; then
        # Create a temporary file and replace safely
        local tmp_state
        tmp_state=$(mktemp)
        awk -F"\t" -v m="$mount" '$1 != m' "$STATE_FILE" > "$tmp_state"
        mv "$tmp_state" "$STATE_FILE"
        chmod 644 "$STATE_FILE"
    fi
}

# --- Persistence ---
add_fstab() {
    local mount="$1"
    local size="$2"
    local perms="$3"
    local uid="$4"
    local gid="$5"

    local opts="size=${size},mode=${perms},uid=${uid},gid=${gid},noexec,nosuid,nodev"
    local fstab_mount="${mount// /\\040}"
    local entry="tmpfs $fstab_mount tmpfs $opts 0 0"

    if grep -q "[[:space:]]${mount}[[:space:]]" /etc/fstab; then
        echo_warn "An entry for $mount already exists in /etc/fstab. Updating it."
        local tmp_fstab=$(mktemp); awk -v m="$mount" '$1 == "tmpfs" && $2 == m {next} {print}' /etc/fstab > "$tmp_fstab" && cat "$tmp_fstab" > /etc/fstab && rm -f "$tmp_fstab"
    fi

    echo "$entry" >> /etc/fstab
    echo_info "Added fstab entry for $mount"
}

remove_fstab() {
    local mount="$1"
    if grep -q "[[:space:]]${mount}[[:space:]]" /etc/fstab; then
        local tmp_fstab=$(mktemp); awk -v m="$mount" '$1 == "tmpfs" && $2 == m {next} {print}' /etc/fstab > "$tmp_fstab" && cat "$tmp_fstab" > /etc/fstab && rm -f "$tmp_fstab"
        echo_info "Removed fstab entry for $mount"
    fi
}

add_systemd() {
    local mount="$1"
    local size="$2"
    local perms="$3"
    local uid="$4"
    local gid="$5"

    local unit_name
    # systemd mount unit names are based on path, e.g., /mnt/ramdisk -> mnt-ramdisk.mount
    unit_name=$(systemd-escape -p --suffix=mount "$mount")
    local unit_file="/etc/systemd/system/$unit_name"

    cat << EOF > "$unit_file"
[Unit]
Description=RAM Disk (tmpfs) for $mount
DefaultDependencies=no
Conflicts=umount.target
Before=local-fs.target umount.target
After=swap.target

[Mount]
What=tmpfs
Where=$mount
Type=tmpfs
Options=size=$size,mode=$perms,uid=$uid,gid=$gid,noexec,nosuid,nodev

[Install]
WantedBy=local-fs.target
EOF

    systemctl daemon-reload
    systemctl enable "$unit_name"
    echo_info "Created and enabled systemd unit $unit_name"
}

remove_systemd() {
    local mount="$1"
    local unit_name
    unit_name=$(systemd-escape -p --suffix=mount "$mount")
    local unit_file="/etc/systemd/system/$unit_name"

    if [[ -f "$unit_file" ]]; then
        systemctl disable "$unit_name" 2>/dev/null
        rm -f "$unit_file"
        systemctl daemon-reload
        echo_info "Removed systemd unit $unit_name"
    fi
}

# --- Core Operations ---
do_create() {
    echo_info "Starting RAM disk creation process..."

    local size_str="${ARG_SIZE:-$DEFAULT_SIZE}"
    local size_bytes
    size_bytes=$(parse_size "$size_str")

    if [[ $size_bytes -le 0 ]]; then
        die "Invalid size specified: $size_str" || return 1
    fi

    if [[ $size_bytes -lt 4194304 ]]; then # 4M
        echo_warn "Requested size ($size_str) is very small. Minimum recommended is 4M."
    fi

    local mem_avail
    mem_avail=$(get_mem_available)
    local max_safe_bytes=$((mem_avail * SAFETY_CAP_PERCENT / 100))
    local warn_bytes=$((mem_avail * WARN_CAP_PERCENT / 100))

    if [[ $size_bytes -gt $max_safe_bytes ]]; then
        if [[ $ARG_FORCE -eq 1 ]]; then
            echo_warn "Requested size ($size_str) exceeds safety cap ($SAFETY_CAP_PERCENT% of available RAM). Forcing due to --force flag."
        else
            die "Requested size ($size_str) exceeds safety cap ($SAFETY_CAP_PERCENT% of available RAM: $(format_bytes $max_safe_bytes)). Use --force to override." || return 1
        fi
    elif [[ $size_bytes -gt $warn_bytes ]]; then
        echo_warn "Requested size ($size_str) is quite large (> $WARN_CAP_PERCENT% of available RAM)."
    fi

    # Check swap
    local swap_total
    swap_total=$(grep SwapTotal /proc/meminfo | awk "{print \$2}")
    if [[ "$swap_total" == "0" ]]; then
        echo_warn "Swap is disabled. Large tmpfs allocations may cause OOM killer to trigger."
    fi

    local mount_point="${ARG_MOUNT:-${DEFAULT_MOUNT_PREFIX}}"
    local label="${ARG_LABEL:-ramdisk}"
    local perms="${ARG_PERMS:-$DEFAULT_PERMS}"
    local owner="${ARG_USER:-${SUDO_USER:-root}}"
    local persist="${ARG_PERSIST:-$DEFAULT_PERSIST}"

    # Validate mount point
    if grep -q "[[:space:]]${mount_point}[[:space:]]" /proc/mounts; then
        die "Mount point $mount_point is already mounted." || return 1
    fi

    if [[ -d "$mount_point" ]] && [[ "$(ls -A -- "$mount_point")" ]]; then
        echo_warn "Directory $mount_point exists and is not empty."
        prompt_confirm "Are you sure you want to mount over it?" || { echo "Aborted."; return 1; }
    fi

    # Resolve owner to UID/GID
    local uid
    local gid
    uid=$(id -u "$owner" 2>/dev/null) || { die "User $owner does not exist." ; return 1; }
    gid=$(id -g "$owner" 2>/dev/null)

    local opts="size=${size_bytes},mode=${perms},uid=${uid},gid=${gid},noexec,nosuid,nodev"
    local mount_cmd="mount -t tmpfs -o \"$opts\" tmpfs \"$mount_point\""

    if [[ $ARG_DRY_RUN -eq 1 ]]; then
        echo_info "[DRY-RUN] Would create directory: mkdir -p \"$mount_point\""
        echo_info "[DRY-RUN] Would run: $mount_cmd"
        if [[ "$persist" == "fstab" ]]; then
            echo_info "[DRY-RUN] Would add to /etc/fstab"
        elif [[ "$persist" == "systemd" ]]; then
            echo_info "[DRY-RUN] Would create systemd mount unit"
        fi
        echo_info "[DRY-RUN] Would save state."
        return 0
    fi

    # Actually do it
    mkdir -p "$mount_point" || { die "Failed to create directory $mount_point" ; return 1; }

    mount -t tmpfs -o "$opts" tmpfs "$mount_point" || { die "Failed to mount tmpfs at $mount_point" ; return 1; }

    if [[ "$persist" == "fstab" ]]; then
        add_fstab "$mount_point" "$size_bytes" "$perms" "$uid" "$gid"
    elif [[ "$persist" == "systemd" ]]; then
        add_systemd "$mount_point" "$size_bytes" "$perms" "$uid" "$gid"
    fi

    save_state "$mount_point" "$size_str" "$label" "$owner" "$persist"

    echo_success "RAM disk mounted successfully at $mount_point"
    echo_info "Size: $(format_bytes $size_bytes), Owner: $owner, Persistence: $persist"
}

do_remove() {
    local target="$1"

    if [[ -z "$target" ]]; then
        target="$ARG_MOUNT"
    fi

    if [[ -z "$target" ]]; then
        die "No mount point specified for removal." || return 1
    fi

    echo_info "Starting removal for $target..."

    if ! grep -q "[[:space:]]${target}[[:space:]]" /proc/mounts; then
        echo_warn "Not currently mounted: $target"
    else
        # Check if files inside
        local used_bytes
        used_bytes=$(df -P "$target" | awk "NR==2 {print \$3}")
        if [[ "$used_bytes" -gt 0 ]]; then
            echo_warn "There are files on $target. They will be LOST."
            prompt_confirm "Are you sure you want to unmount and DESTROY data?" || { echo "Aborted."; return 1; }
        fi

        if [[ $ARG_DRY_RUN -eq 1 ]]; then
            echo_info "[DRY-RUN] Would unmount: umount \"$target\""
            echo_info "[DRY-RUN] Would remove directory if empty: rmdir \"$target\""
        else
            umount "$target" || { die "Failed to unmount $target"; return 1; }
            echo_success "Unmounted $target"
            rmdir "$target" 2>/dev/null && echo_info "Removed empty mount point directory $target" || echo_warn "Mount point directory $target not empty or couldn\"t be removed."
        fi
    fi

    # Cleanup persistence and state
    if [[ -f "$STATE_FILE" ]]; then
        local persist
        persist=$(awk -F"\t" -v m="$target" "\$1 == m {print \$6}" "$STATE_FILE")

        if [[ $ARG_DRY_RUN -eq 1 ]]; then
            if [[ "$persist" == "fstab" ]]; then echo_info "[DRY-RUN] Would remove fstab entry."; fi
            if [[ "$persist" == "systemd" ]]; then echo_info "[DRY-RUN] Would remove systemd unit."; fi
            echo_info "[DRY-RUN] Would remove state entry."
            return 0
        fi

        if [[ "$persist" == "fstab" ]]; then
            remove_fstab "$target"
        elif [[ "$persist" == "systemd" ]]; then
            remove_systemd "$target"
        fi

        remove_state "$target"
        echo_success "Cleaned up configuration for $target"
    fi
}

do_list() {
    if [[ $ARG_JSON -eq 1 ]]; then
        echo "["
        local first=1
    else
        printf "%-25s %-10s %-15s %-15s %-10s %-10s\n" "MOUNT POINT" "SIZE" "LABEL" "OWNER" "PERSIST" "USED"
        echo "------------------------------------------------------------------------------------------"
    fi

    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ $ARG_JSON -eq 1 ]]; then echo "]"; fi
        return 0
    fi

    while IFS=$'\t' read -r mount size label ts user persist; do
        if [[ -z "$mount" ]]; then continue; fi

        local used="-"
        if grep -q "[[:space:]]${mount}[[:space:]]" /proc/mounts; then
            used=$(df -hP "$mount" | awk "NR==2 {print \$5}")
        else
            used="(unmounted)"
        fi

        if [[ $ARG_JSON -eq 1 ]]; then
            if [[ $first -eq 0 ]]; then echo ","; fi
            cat <<EOF
  {
    "mount": "$mount",
    "size": "$size",
    "label": "$label",
    "user": "$user",
    "persist": "$persist",
    "used": "$used"
  }
EOF
            first=0
        else
            printf "%-25s %-10s %-15s %-15s %-10s %-10s\n" "$mount" "$size" "$label" "$user" "$persist" "$used"
        fi
    done < "$STATE_FILE"

    if [[ $ARG_JSON -eq 1 ]]; then
        echo "]"
    fi
}

do_info() {
    do_list
}

# --- Interactive Menu ---
show_menu() {
    echo -e "${BOLD}Advanced RAM Disk (tmpfs) Creator${NC} - v$VERSION"
    echo "================================================="
    echo "1) Create a new RAM disk"
    echo "2) List active RAM disks"
    echo "3) Remove a RAM disk"
    echo "4) System Memory Info"
    echo "5) Exit"
    echo ""
    read -r -p "Select an option [1-5]: " menu_choice || return 0

    case "$menu_choice" in
        1)
            echo -e "\n${BOLD}--- Create RAM Disk ---${NC}"
            read -r -p "Size (e.g., 512M, 2G) [$DEFAULT_SIZE]: " ARG_SIZE || return 0
            ARG_SIZE=${ARG_SIZE:-$DEFAULT_SIZE}

            read -r -p "Mount Point [$DEFAULT_MOUNT_PREFIX]: " ARG_MOUNT || return 0
            ARG_MOUNT=${ARG_MOUNT:-$DEFAULT_MOUNT_PREFIX}

            read -r -p "Label [ramdisk]: " ARG_LABEL || return 0
            ARG_LABEL=${ARG_LABEL:-ramdisk}

            read -r -p "Persistence (none, fstab, systemd) [none]: " ARG_PERSIST || return 0
            ARG_PERSIST=${ARG_PERSIST:-none}

            echo ""
            prompt_confirm "Create $ARG_SIZE RAM disk at $ARG_MOUNT?" || { echo "Aborted."; return 0; }
            do_create
            ;;
        2)
            echo -e "\n${BOLD}--- Active RAM Disks ---${NC}"
            do_list
            ;;
        3)
            echo -e "\n${BOLD}--- Remove RAM Disk ---${NC}"
            if [[ ! -f "$STATE_FILE" ]] || [[ ! -s "$STATE_FILE" ]]; then
                echo "No managed RAM disks found."
                return
            fi

            local i=1
            local mounts=()
            while IFS=$'\t' read -r mount size label ts user persist; do
                if [[ -z "$mount" ]]; then continue; fi
                mounts[$i]="$mount"
                echo "$i) $mount ($size, $label)"
                i=$((i+1))
            done < "$STATE_FILE"

            echo "0) Cancel"
            read -r -p "Select disk to remove [0-$((i-1))]: " rm_choice || return 0

            if [[ "$rm_choice" =~ ^[0-9]+$ ]] && [[ "$rm_choice" -gt 0 ]] && [[ "$rm_choice" -lt "$i" ]]; then
                ARG_MOUNT="${mounts[$rm_choice]}"
                do_remove
            else
                echo "Cancelled."
            fi
            ;;
        4)
            echo -e "\n${BOLD}--- System Memory Info ---${NC}"
            free -h
            ;;
        5)
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

# --- Main & Arg Parsing ---
print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Advanced RAM disk (tmpfs) creator for Linux.
If run with no arguments, drops into an interactive menu.

Actions:
  --create                  Create a new RAM disk
  --remove                  Remove an existing RAM disk
  --list                    List managed RAM disks
  --info                    Same as --list
  -h, --help                Show this help message
  --version                 Show version

Create Options:
  --size SIZE               Size of RAM disk (e.g., 512M, 2G). Default: $DEFAULT_SIZE
  --mount PATH              Mount point. Default: $DEFAULT_MOUNT_PREFIX
  --label LABEL             Custom label
  --perms PERMS             Permissions (e.g., 1777). Default: $DEFAULT_PERMS
  --user USER               Owner of the mounted directory
  --persist MODE            Persistence mode: none, fstab, systemd. Default: $DEFAULT_PERSIST
  --force                   Bypass safety caps (use with caution)

Global Options:
  --dry-run                 Show what would be done without doing it
  -y, --yes                 Skip confirmation prompts
  --json                    Output list in JSON format

Examples:
  $0 --create --size 1G --mount /mnt/fastcache --persist systemd
  $0 --remove --mount /mnt/fastcache
  $0 --list
EOF
}

main() {
    load_config

    # Check for help/version first
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
            print_help
            return 0
        elif [[ "$arg" == "--version" ]]; then
            echo "ramdisk.sh version $VERSION"
            return 0
        fi
    done

    if [[ $# -eq 0 ]]; then
        check_root || return 1
        init_state_dir || return 1
        show_menu
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --create) ACTION="create"; shift ;;
            --remove) ACTION="remove"; shift ;;
            --list|--info) ACTION="list"; shift ;;

            --size) ARG_SIZE="$2"; shift 2 || shift ;;
            --mount) ARG_MOUNT="$2"; shift 2 || shift ;;
            --label) ARG_LABEL="$2"; shift 2 || shift ;;
            --perms) ARG_PERMS="$2"; shift 2 || shift ;;
            --user) ARG_USER="$2"; shift 2 || shift ;;
            --persist) ARG_PERSIST="$2"; shift 2 || shift ;;
            --force) ARG_FORCE=1; shift ;;

            --dry-run) ARG_DRY_RUN=1; shift ;;
            -y|--yes) ARG_YES=1; shift ;;
            --json) ARG_JSON=1; shift ;;

            *) echo_err "Unknown option: $1"; print_help; return 1 ;;
        esac
    done

    if [[ "$ACTION" != "list" ]]; then
        check_root || return 1
    fi

    # Do not fail hard on list if not root and state file does not exist
    if [[ "$ACTION" == "list" ]] && [[ $EUID -ne 0 ]] && [[ ! -d "$STATE_DIR" ]]; then
        # Just show empty list
        do_list
        return 0
    fi

    init_state_dir || return 1

    case "$ACTION" in
        create)
            do_create
            ;;
        remove)
            do_remove ""
            ;;
        list)
            do_list
            ;;
        *)
            echo_err "No action specified. Use --create, --remove, or --list."
            print_help
            return 1
            ;;
    esac
}

main "$@"
