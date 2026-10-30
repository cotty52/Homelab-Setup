#!/usr/bin/env bash
# =============================================================================
# lib/distro/cachyos.sh - CachyOS (Arch-based, pacman, rolling release)
# =============================================================================
# Loaded automatically by load_distro (see lib/common.sh). Do not run directly.
#
# Differences from Linux Mint worth knowing:
#   • Docker comes from the official Arch repos (no third-party apt repo).
#   • The SSH service is "sshd", not "ssh".
#   • It is a rolling release: updates are done manually with `pacman -Syu`.
#     Unattended upgrades are deliberately NOT set up.
#   • CachyOS defaults to KDE Plasma, so desktop tweaks target KDE
#     (GNOME and XFCE are handled on a best-effort basis).
# =============================================================================

DISTRO_LABEL="CachyOS"
SSH_PKG="openssh"
SSH_SERVICE="sshd"

# Everything 00-core.sh needs is already in the shared list.
DISTRO_CORE_PACKAGES=()

# -----------------------------------------------------------------------------
# Packages
# -----------------------------------------------------------------------------
pkg_update() {
    pacman -Syu --noconfirm

    # Arch removes the modules of the *running* kernel when the kernel package
    # is upgraded. Until you reboot, Docker can fail to load the networking
    # modules it needs, so 00-core.sh stops here and asks for a reboot.
    if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
        REBOOT_REQUIRED=1
    fi
}

# Skips already-installed packages to keep runs idempotent.
# Usage: pkg_install curl git htop
# Note: this never runs `pacman -Sy` on its own - refreshing the package
# database without upgrading is unsupported on Arch (partial upgrades).
# If an install fails with "target not found" or a 404, run: sudo pacman -Syu
pkg_install() {
    local to_install=() pkg
    for pkg in "$@"; do
        if pacman -Qq "$pkg" &>/dev/null; then
            info "Already installed: $pkg"
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -gt 0 ]]; then
        info "Installing: ${to_install[*]}"
        pacman -S --needed --noconfirm "${to_install[@]}"
    fi
}

# -----------------------------------------------------------------------------
# Docker - straight from the Arch repos. `docker-compose` and `docker-buildx`
# install the `docker compose` and `docker buildx` CLI plugins.
# -----------------------------------------------------------------------------
install_docker() {
    pkg_install docker docker-compose docker-buildx
}

# -----------------------------------------------------------------------------
# Firewall - CachyOS ships UFW (inactive by default). firewalld would fight
# with it over the same rules, so make sure only one of them is running.
# -----------------------------------------------------------------------------
prepare_firewall() {
    if systemctl is-active --quiet firewalld; then
        warn "firewalld is running. It conflicts with UFW, which this script uses."
        if confirm "Disable firewalld and use UFW instead?"; then
            systemctl disable --now firewalld
            success "firewalld disabled"
        else
            error "Not continuing while two firewall managers are active."
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Desktop: screensaver and display sleep
# Best effort, picks whichever desktop's tools are installed. Changes apply
# after the user logs out and back in. System-level suspend is handled
# separately (and reliably) by systemd in 01-os-tweaks.sh.
# -----------------------------------------------------------------------------
disable_screensaver() {
    if command -v kwriteconfig6 &>/dev/null; then
        # KDE Plasma (CachyOS default)
        user_session_run kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false \
            && user_session_run kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false \
            && success "KDE screen locking disabled" \
            || warn "Could not disable KDE screen locking - apply manually in System Settings → Screen Locking."

        user_session_run kwriteconfig6 --file powerdevilrc --group AC --group Display --key DimDisplayWhenIdle false \
            && user_session_run kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayWhenIdle false \
            && user_session_run kwriteconfig6 --file powerdevilrc --group AC --group SuspendAndShutdown --key AutoSuspendAction 0 \
            && success "KDE display sleep settings written (log out and back in to apply)" \
            || warn "Could not set KDE power settings - apply manually in System Settings → Energy Saving."
        info "Double-check System Settings → Energy Saving: KDE's power keys vary between Plasma versions."

    elif command -v gsettings &>/dev/null; then
        # GNOME
        user_session_run gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null \
            && user_session_run gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null \
            && user_session_run gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null \
            && success "GNOME screen lock and sleep disabled" \
            || warn "Could not apply GNOME settings - user session may not be active. Set them in Settings → Power / Privacy."

    elif command -v xfconf-query &>/dev/null; then
        # XFCE
        user_session_run xfconf-query -c xfce4-screensaver -p /saver/enabled -s false 2>/dev/null \
            && user_session_run xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false 2>/dev/null \
            && success "XFCE screensaver and display power management disabled" \
            || warn "Could not apply XFCE settings - user session may not be active."

    else
        warn "No supported desktop found (KDE, GNOME, XFCE). Skipping screensaver settings."
    fi
}

# -----------------------------------------------------------------------------
# Automatic updates - intentionally not enabled.
# On a rolling release, unattended upgrades can break the system, and kernel
# updates need a reboot before Docker is reliable again.
# -----------------------------------------------------------------------------
enable_auto_updates() {
    info "Automatic updates are intentionally not set up on CachyOS (rolling release)."
    info "Update manually every week or two with: sudo pacman -Syu"
    info "Reboot after kernel updates, then check: docker compose ps"
    return 1
}

# -----------------------------------------------------------------------------
# Desktop auto-login (SDDM, CachyOS's KDE display manager) - opt-in, see 01-os-tweaks.sh
# "plasma" is the Wayland session; use "plasmax11" if you run the X11 session.
# -----------------------------------------------------------------------------
enable_autologin() {
    if systemctl is-enabled --quiet sddm 2>/dev/null; then
        install -d /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=$HOMELAB_USER
Session=plasma
EOF
        success "Auto-login enabled for $HOMELAB_USER (SDDM)"
    else
        warn "SDDM isn't the enabled display manager - set auto-login in your display manager's settings."
        return 1
    fi
}
