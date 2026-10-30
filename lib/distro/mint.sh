#!/usr/bin/env bash
# =============================================================================
# lib/distro/mint.sh - Linux Mint (Ubuntu/Debian family, apt, Cinnamon desktop)
# =============================================================================
# Loaded automatically by load_distro (see lib/common.sh). Do not run directly.
# =============================================================================

DISTRO_LABEL="Linux Mint"
SSH_PKG="openssh-server"
SSH_SERVICE="ssh"

# Needed to add Docker's apt repository.
DISTRO_CORE_PACKAGES=(
    ca-certificates
    gnupg
    lsb-release
)

# -----------------------------------------------------------------------------
# Packages
# -----------------------------------------------------------------------------
pkg_update() {
    apt-get update -y
    apt-get upgrade -y
}

# Skips already-installed packages to keep runs idempotent.
# Usage: pkg_install curl git htop
pkg_install() {
    local to_install=() pkg
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
# Docker
# We use Docker's official repo, NOT the older version from Ubuntu's repos.
# The Ubuntu/Mint version is often out of date and missing Compose v2.
# -----------------------------------------------------------------------------
install_docker() {
    info "Adding Docker's official GPG key and repository..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Linux Mint is Ubuntu-based. We pull the Ubuntu codename for the repo.
    # e.g. Mint 21.x → Ubuntu "jammy"; Mint 22.x → Ubuntu "noble"
    local ubuntu_codename
    ubuntu_codename=$(. /etc/upstream-release/lsb_release 2>/dev/null \
        && echo "$DISTRIB_CODENAME" \
        || grep -oP '(?<=UBUNTU_CODENAME=).+' /etc/os-release)

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# -----------------------------------------------------------------------------
# Firewall: UFW is the standard firewall on Ubuntu/Mint, nothing to prepare.
# -----------------------------------------------------------------------------
prepare_firewall() {
    :
}

# -----------------------------------------------------------------------------
# Desktop: screensaver and display sleep
# These settings target Cinnamon DE (Linux Mint's default).
# If you're on MATE or XFCE, the setting keys will be slightly different.
# -----------------------------------------------------------------------------
disable_screensaver() {
    # Disable the screensaver entirely
    user_session_run gsettings set org.cinnamon.desktop.screensaver lock-enabled false 2>/dev/null \
        && success "Screensaver lock disabled" \
        || warn "Could not set screensaver — user session may not be active. Run manually after login."

    # Disable display power management (prevents monitor from sleeping)
    user_session_run gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 0 2>/dev/null \
        && success "Display sleep disabled" \
        || warn "Could not disable display sleep — apply manually in System Settings → Power Management."

    # ── XFCE alternative (use instead if on Mint XFCE edition) ───────────────
    # user_session_run xfconf-query -c xfce4-screensaver -p /saver/enabled -s false
    # user_session_run xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false
}

# -----------------------------------------------------------------------------
# Automatic security updates (unattended-upgrades)
# Applies security patches without requiring manual updates.
# Non-security updates are left for you to apply manually.
# -----------------------------------------------------------------------------
enable_auto_updates() {
    pkg_install unattended-upgrades
    dpkg-reconfigure -f noninteractive unattended-upgrades
    success "Unattended security upgrades enabled"
}

# -----------------------------------------------------------------------------
# Desktop auto-login (LightDM, Mint's display manager) - opt-in, see 01-os-tweaks.sh
# -----------------------------------------------------------------------------
enable_autologin() {
    local lightdm_conf="/etc/lightdm/lightdm.conf"
    if [[ -f "$lightdm_conf" ]]; then
        sed -i "s/^#autologin-user=.*/autologin-user=$HOMELAB_USER/" "$lightdm_conf"
        sed -i "s/^#autologin-user-timeout=.*/autologin-user-timeout=0/" "$lightdm_conf"
        success "Auto-login enabled for $HOMELAB_USER"
    else
        warn "LightDM config not found at $lightdm_conf — check your display manager."
        return 1
    fi
}
