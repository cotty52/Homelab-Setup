#!/usr/bin/env bash
# =============================================================================
# 01-os-tweaks.sh — Linux Mint / desktop OS quality-of-life tweaks
# =============================================================================
# Configures the OS to behave like a server appliance rather than a workstation.
# All sections are documented — comment/uncomment what you need.
#
# Run with: sudo bash 01-os-tweaks.sh
# =============================================================================

source "$(dirname "$0")/lib/common.sh"

require_sudo
check_os "linuxmint"

HOMELAB_USER="${SUDO_USER:-$USER}"
HOMELAB_USER_HOME=$(eval echo "~$HOMELAB_USER")

# =============================================================================
# STEP 1 — Disable screensaver and display sleep
# Without this, the screen will blank and the desktop will lock itself,
# which is annoying on a server you occasionally glance at or use via HDMI.
# =============================================================================
section "Disabling screensaver and display sleep"

# These settings target Cinnamon DE (Linux Mint's default).
# If you're on MATE or XFCE, the setting keys will be slightly different.

# Disable the screensaver entirely
sudo -u "$HOMELAB_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$HOMELAB_USER")/bus" \
    gsettings set org.cinnamon.desktop.screensaver lock-enabled false 2>/dev/null \
    && success "Screensaver lock disabled" \
    || warn "Could not set screensaver — user session may not be active. Run manually after login."

# Disable display power management (prevents monitor from sleeping)
sudo -u "$HOMELAB_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$HOMELAB_USER")/bus" \
    gsettings set org.cinnamon.settings-daemon.plugins.power sleep-display-ac 0 2>/dev/null \
    && success "Display sleep disabled" \
    || warn "Could not disable display sleep — apply manually in System Settings → Power Management."

# ── XFCE alternative (uncomment if using Mint XFCE edition) ──────────────
# xfconf-query -c xfce4-screensaver -p /saver/enabled -s false
# xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false

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
# =============================================================================
section "Setting up SSH server"

pkg_install openssh-server

systemctl enable ssh
systemctl start ssh
success "SSH server installed and running"

# Display the IP address so you know where to connect
LOCAL_IP=$(hostname -I | awk '{print $1}')
info "Connect to this machine with: ssh $HOMELAB_USER@$LOCAL_IP"
mark_done "SSH server configured"

# =============================================================================
# STEP 4 — Install Tailscale (commented out by default)
# Tailscale creates a private encrypted network between your devices,
# letting you access your homelab remotely without opening firewall ports.
# Sign up free at https://tailscale.com, then uncomment and run this section.
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
# =============================================================================
section "Auto-login"

# ── Uncomment to enable auto-login for the Cinnamon display manager (MDM/LightDM)
#
# LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
# if [[ -f "$LIGHTDM_CONF" ]]; then
#     sed -i "s/^#autologin-user=.*/autologin-user=$HOMELAB_USER/" "$LIGHTDM_CONF"
#     sed -i "s/^#autologin-user-timeout=.*/autologin-user-timeout=0/" "$LIGHTDM_CONF"
#     success "Auto-login enabled for $HOMELAB_USER"
#     mark_done "Auto-login configured"
# else
#     warn "LightDM config not found at $LIGHTDM_CONF — check your display manager."
# fi

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
# STEP 7 — Configure unattended security upgrades
# Automatically applies security patches without requiring manual updates.
# Non-security updates are left for you to apply manually.
# =============================================================================
section "Configuring automatic security updates"

pkg_install unattended-upgrades

# Enable unattended upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

success "Unattended security upgrades enabled"
mark_done "Automatic security updates configured"

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
