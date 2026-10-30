#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared utilities for homelab setup scripts
# =============================================================================
# Source this file at the top of each script:
#   source "$(dirname "$0")/lib/common.sh"
#
# Anything that differs between Linux distros (package manager, how Docker is
# installed, service names, desktop settings) lives in lib/distro/<name>.sh.
# Call load_distro once near the top of a script and the matching "driver" is
# loaded for you. See "Distro drivers" below for what a driver must provide.
# =============================================================================

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Color codes
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------

info() {
    echo -e "${BLUE}[INFO]${RESET}  $*"
}

success() {
    echo -e "${GREEN}[OK]${RESET}    $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${RESET}  $*"
}

error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}==> $*${RESET}"
    echo ""
}

# -----------------------------------------------------------------------------
# Root / sudo check
# Run this at the top of any script that needs elevated privileges.
# -----------------------------------------------------------------------------
require_sudo() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run with sudo or as root."
        error "Try: sudo bash $0"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# OS detection
# Sets: $OS_ID, $OS_VERSION, $OS_PRETTY
# -----------------------------------------------------------------------------
detect_os() {
    local release_file="${OS_RELEASE_FILE:-/etc/os-release}"
    if [[ -f "$release_file" ]]; then
        # shellcheck source=/dev/null
        source "$release_file"
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-unknown}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_PRETTY="unknown"
    fi
}

# -----------------------------------------------------------------------------
# Distro drivers
# -----------------------------------------------------------------------------
# load_distro picks lib/distro/<name>.sh based on /etc/os-release and sources it.
# To force a driver (e.g. on an untested distro), set HOMELAB_DISTRO:
#     sudo HOMELAB_DISTRO=cachyos bash 00-core.sh
#
# Every driver must define these variables:
#   DISTRO_LABEL           Human-readable name, e.g. "Linux Mint"
#   SSH_PKG                Package that provides the SSH server
#   SSH_SERVICE            systemd unit name of the SSH server (ssh / sshd)
#   DISTRO_CORE_PACKAGES   Extra packages for 00-core.sh (array, may be empty)
#
# ...and these functions:
#   pkg_update             Refresh package lists and upgrade the system
#   pkg_install <pkgs...>  Install packages, skipping ones already installed
#   install_docker         Install Docker Engine + Compose v2 + Buildx
#   prepare_firewall       Get the distro ready for UFW (e.g. stop a rival firewall)
#   disable_screensaver    Turn off screen lock / display sleep for $HOMELAB_USER
#   enable_auto_updates    Set up automatic updates (return non-zero if skipped)
#   enable_autologin       Desktop auto-login for $HOMELAB_USER (opt-in only)
#
# Driver functions may use $HOMELAB_USER, which the calling script sets.
# A driver may set REBOOT_REQUIRED=1 (e.g. after a kernel update).
# -----------------------------------------------------------------------------
DISTRO_REQUIRED_VARS=(DISTRO_LABEL SSH_PKG SSH_SERVICE DISTRO_CORE_PACKAGES)
DISTRO_REQUIRED_FUNCS=(pkg_update pkg_install install_docker prepare_firewall
                       disable_screensaver enable_auto_updates enable_autologin)

list_distro_drivers() {
    local f names=()
    for f in "$SCRIPT_LIB_DIR"/distro/*.sh; do
        [[ -e "$f" ]] && names+=("$(basename "$f" .sh)")
    done
    echo "${names[*]}"
}

load_distro() {
    detect_os

    local driver="${HOMELAB_DISTRO:-}"
    if [[ -z "$driver" ]]; then
        case "$OS_ID" in
            linuxmint) driver="mint" ;;
            cachyos)   driver="cachyos" ;;
        esac
    fi

    if [[ -z "$driver" ]]; then
        error "Unsupported distro: $OS_PRETTY (ID=$OS_ID)."
        error "Supported setups: $(list_distro_drivers)"
        error "To force one anyway: sudo HOMELAB_DISTRO=<name> bash $0"
        exit 1
    fi

    local driver_file="$SCRIPT_LIB_DIR/distro/${driver}.sh"
    if [[ ! "$driver" =~ ^[a-z0-9_-]+$ || ! -f "$driver_file" ]]; then
        error "No distro driver named '$driver'. Available: $(list_distro_drivers)"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$driver_file"

    local name
    for name in "${DISTRO_REQUIRED_VARS[@]}"; do
        if ! declare -p "$name" &> /dev/null; then
            error "Distro driver '$driver' is missing required variable: $name"
            exit 1
        fi
    done
    for name in "${DISTRO_REQUIRED_FUNCS[@]}"; do
        if ! declare -F "$name" > /dev/null; then
            error "Distro driver '$driver' is missing required function: $name"
            exit 1
        fi
    done

    info "Detected $OS_PRETTY, using the '$driver' setup ($DISTRO_LABEL)"
}

# -----------------------------------------------------------------------------
# Confirm prompt
# Usage: confirm "Do the thing?" && do_the_thing
# -----------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Are you sure?}"
    read -rp "$(echo -e "${YELLOW}${prompt}${RESET} [y/N] ")" answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# -----------------------------------------------------------------------------
# Local IP address
# Prints the IPv4 address this machine uses to reach the network.
# (Replaces `hostname -I`, which is not available on every distro.)
# -----------------------------------------------------------------------------
get_local_ip() {
    local addr
    addr=$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')
    echo "${addr:-<server-ip>}"
}

# -----------------------------------------------------------------------------
# Run a command as $HOMELAB_USER inside their desktop session
# Needed for per-user desktop settings (gsettings, kwriteconfig6, ...) because
# scripts run as root and would otherwise change root's settings instead.
# Usage: user_session_run gsettings set org.example.key value
# -----------------------------------------------------------------------------
user_session_run() {
    local uid user_home
    uid=$(id -u "$HOMELAB_USER")
    user_home=$(getent passwd "$HOMELAB_USER" | cut -d: -f6)
    sudo -u "$HOMELAB_USER" env \
        HOME="$user_home" \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        "$@"
}

# -----------------------------------------------------------------------------
# Set an option in sshd_config
# Replaces an existing "Key value" line, or un-comments the stock "#Key value"
# line, or adds the option (before any Match block so it applies globally).
# Usage: set_sshd_option PermitRootLogin no
# -----------------------------------------------------------------------------
set_sshd_option() {
    local key="$1" value="$2" file="${SSHD_CONFIG:-/etc/ssh/sshd_config}"

    if grep -qE "^[[:space:]]*${key}[[:space:]]" "$file"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
    elif grep -qE "^#${key}[[:space:]]" "$file"; then
        sed -i -E "s|^#${key}[[:space:]].*|${key} ${value}|" "$file"
    elif grep -qE '^[[:space:]]*Match[[:space:]]' "$file"; then
        sed -i -E "0,/^[[:space:]]*Match[[:space:]]/s//${key} ${value}\n&/" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

# -----------------------------------------------------------------------------
# Step tracking — prints a summary of completed steps at the end
# Usage: mark_done "Installed Docker"
# Call print_summary at the end of your script.
# -----------------------------------------------------------------------------
COMPLETED_STEPS=()

mark_done() {
    COMPLETED_STEPS+=("$*")
}

print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}========================================${RESET}"
    echo -e "${BOLD}${GREEN}  Summary of completed steps${RESET}"
    echo -e "${BOLD}${GREEN}========================================${RESET}"
    for step in "${COMPLETED_STEPS[@]}"; do
        echo -e "  ${GREEN}✔${RESET}  $step"
    done
    echo ""
}
