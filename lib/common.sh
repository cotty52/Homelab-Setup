#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared utilities for homelab setup scripts
# =============================================================================
# Source this file at the top of each script:
#   source "$(dirname "$0")/lib/common.sh"
# =============================================================================

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
# Call check_os "linuxmint" to warn if running on an unexpected distro.
# -----------------------------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_PRETTY="${PRETTY_NAME:-unknown}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_PRETTY="unknown"
    fi
}

check_os() {
    local expected="$1"
    detect_os
    if [[ "$OS_ID" != "$expected" ]]; then
        warn "This script was written for '$expected' but detected '$OS_ID'."
        warn "Some steps may not work correctly. Proceed with caution."
        echo ""
        read -rp "Continue anyway? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
}

# -----------------------------------------------------------------------------
# Package install helper
# Skips already-installed packages to keep runs idempotent.
# Usage: pkg_install curl git htop
# -----------------------------------------------------------------------------
pkg_install() {
    local to_install=()
    for pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            info "Already installed: $pkg"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        info "Installing: ${to_install[*]}"
        apt-get install -y "${to_install[@]}"
    fi
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
