#!/usr/bin/env bash
# memman.sh - Unified Memory Management Tool (RAM disk, Swap, ZRAM)

VERSION="1.0.0"

# Colors
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

echo_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
echo_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_err() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

print_help() {
    cat <<HELP_EOF
Usage: $0 COMMAND [OPTIONS]

Unified Memory Management Tool.
If run with no arguments, drops into an interactive menu.

Commands:
  ramdisk    Manage tmpfs RAM disks
  swap       Manage Swapfiles, Swap Partitions, and ZRAM
  help       Show this help message
  version    Show version

To see options for a specific command, run:
  $0 ramdisk --help
  $0 swap --help

Examples:
  $0 ramdisk --create --size 1G --mount /mnt/ramdisk
  $0 swap --create --backend zram --size 1G
HELP_EOF
}

show_main_menu() {
    echo -e "${BOLD}Unified Memory Manager (memman)${NC} - v$VERSION"
    echo "======================================"
    echo "1) Manage RAM Disks (tmpfs)"
    echo "2) Manage Swap & ZRAM"
    echo "3) System Memory Info"
    echo "4) Exit"
    echo ""
    read -r -p "Select a subsystem [1-4]: " menu_choice || return 0

    case "$menu_choice" in
        1)
            bash "$(dirname "$0")/ramdisk.sh"
            ;;
        2)
            bash "$(dirname "$0")/swapman.sh"
            ;;
        3)
            echo -e "\n${BOLD}--- System Memory Info ---${NC}"
            free -h
            echo ""
            read -r -p "Press Enter to continue..." || return 0
            show_main_menu
            ;;
        4)
            return 0
            ;;
        *)
            echo_err "Invalid choice."
            show_main_menu
            ;;
    esac
}

main() {
    if [[ $# -eq 0 ]]; then
        show_main_menu
        return 0
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        ramdisk)
            bash "$(dirname "$0")/ramdisk.sh" "$@"
            ;;
        swap)
            bash "$(dirname "$0")/swapman.sh" "$@"
            ;;
        help|-h|--help)
            print_help
            ;;
        version|--version)
            echo "memman.sh version $VERSION"
            ;;
        *)
            echo_err "Unknown command: $cmd"
            print_help
            return 1
            ;;
    esac
}

main "$@"
