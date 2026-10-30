#!/usr/bin/env bash
# =============================================================================
# 01-os-tweaks.sh — OS quality-of-life tweaks (Linux Mint, CachyOS)
# =============================================================================
# Configures the OS to behave like a server appliance rather than a workstation.
# All sections are documented — comment/uncomment what you need.
# Distro-specific parts (desktop settings, SSH package, updates) live in
# lib/distro/<your-distro>.sh
#
# Run with: sudo bash 01-os-tweaks.sh
# =============================================================================

source "$(dirname "$0")/lib/common.sh"

require_sudo
load_distro

HOMELAB_USER="${SUDO_USER:-$USER}"
HOMELAB_USER_HOME=$(eval echo "~$HOMELAB_USER")

# =============================================================================
# STEP 1 — Disable screensaver and display sleep
# Without this, the screen will blank and the desktop will lock itself,
# which is annoying on a server you occasionally glance at or use via HDMI.
# The settings keys depend on the desktop environment, so this is handled by
# the distro driver (Cinnamon on Mint; KDE/GNOME/XFCE on CachyOS).
# =============================================================================
section "Disabling screensaver and display sleep"

disable_screensaver

mark_done "Screensaver and display sleep disabled"

# =============================================================================
# STEP 2 — Disable system suspend and hibernation
# A server should never go to sleep on its own. These commands disable all
# suspend/hibernate targets at the systemd level, which is distro-agnostic.
# =============================================================================
section "Disabling system suspend and hibernation"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
success "Suspend and hibernation disabled"
mark_done "System suspend disabled"

# =============================================================================
# STEP 3 — Install and enable SSH server
# Essential for remote management — lets you admin the server from another
# machine without needing a keyboard/monitor plugged in.
# (Package and service names differ per distro: openssh-server/ssh on Mint,
# openssh/sshd on CachyOS.)
# =============================================================================
section "Setting up SSH server"

pkg_install "$SSH_PKG"

systemctl enable "$SSH_SERVICE"
systemctl start "$SSH_SERVICE"
success "SSH server installed and running"

# Display the IP address so you know where to connect
LOCAL_IP=$(get_local_ip)
info "Connect to this machine with: ssh $HOMELAB_USER@$LOCAL_IP"
mark_done "SSH server configured"

# =============================================================================
# STEP 4 — Install Tailscale (commented out by default)
# Tailscale creates a private encrypted network between your devices,
# letting you access your homelab remotely without opening firewall ports.
# Sign up free at https://tailscale.com, then uncomment and run this section.
# (Tailscale's installer script supports both Mint and CachyOS.)
# =============================================================================
section "Tailscale (remote access VPN)"

# ── Uncomment the block below to install Tailscale ───────────────────────
#
# info "Installing Tailscale..."
# curl -fsSL https://tailscale.com/install.sh | sh
# systemctl enable tailscaled
# systemctl start tailscaled
# success "Tailscale installed. Run 'sudo tailscale up' to authenticate."
# info "After running 'tailscale up', visit the URL shown to log in."
# mark_done "Tailscale installed"

info "Tailscale install is commented out. Uncomment in this script to enable."

# =============================================================================
# STEP 5 — Set auto-login for the desktop (commented out by default)
# Useful if the server reboots and you want the desktop ready without a
# password prompt. Only enable this if physical access is restricted.
# The display manager differs per distro (LightDM on Mint, SDDM on CachyOS),
# so the work is done by enable_autologin in the distro driver.
# =============================================================================
section "Auto-login"

# ── Uncomment the line below to enable auto-login ────────────────────────
#
# enable_autologin && mark_done "Auto-login configured"

info "Auto-login is commented out. Uncomment in this script to enable."

# =============================================================================
# STEP 6 — Set timezone
# Comment this out or change the timezone string if needed.
# Find your timezone string with: timedatectl list-timezones
# =============================================================================
section "Setting timezone"

# Change "America/New_York" to match your location
TIMEZONE="America/New_York"

timedatectl set-timezone "$TIMEZONE"
success "Timezone set to $TIMEZONE"
mark_done "Timezone configured"

# =============================================================================
# STEP 7 — Automatic updates
# Mint: unattended security upgrades (security patches only; the rest is left
# for you to apply manually).
# CachyOS: skipped on purpose. It is a rolling release, so you update
# manually with `sudo pacman -Syu` (the driver explains why).
# =============================================================================
section "Configuring automatic updates"

enable_auto_updates && mark_done "Automatic security updates configured"

# =============================================================================
# STEP 8 — Disable laptop lid-close suspend (commented out by default)
# Only relevant if the server is a laptop. Without this, closing the lid
# will suspend the machine and kill all your containers.
# =============================================================================
section "Lid close behavior"

# ── Uncomment to prevent suspend on lid close ─────────────────────────────
#
# LOGIND_CONF="/etc/systemd/logind.conf"
# sed -i 's/^#HandleLidSwitch=.*/HandleLidSwitch=ignore/' "$LOGIND_CONF"
# sed -i 's/^#HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' "$LOGIND_CONF"
# systemctl restart systemd-logind
# success "Lid close will no longer suspend the system"
# mark_done "Lid close behavior configured"

info "Lid close tweak is commented out (only needed for laptops)."

# =============================================================================
# Done
# =============================================================================
print_summary

echo ""
echo -e "${BOLD}Notes:${RESET}"
echo -e "  • Screensaver/display settings may need to be applied manually"
echo -e "    if the user session wasn't active during this run."
echo -e "  • SSH is now active. Connect with: ${CYAN}ssh $HOMELAB_USER@$LOCAL_IP${RESET}"
echo -e "  • Run ${CYAN}02-hardening.sh${RESET} next to secure your server."
echo ""
