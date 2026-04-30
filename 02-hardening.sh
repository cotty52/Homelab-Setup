#!/usr/bin/env bash
# =============================================================================
# 02-hardening.sh — Server security hardening
# =============================================================================
# Applies security best practices for a homelab server exposed to a local
# network (or the internet via Tailscale/port forwarding).
#
# This script is conservative by default — the most impactful options that
# could lock you out (like changing the SSH port) are commented out.
#
# Run with: sudo bash 02-hardening.sh
# =============================================================================

source "$(dirname "$0")/lib/common.sh"

require_sudo
check_os "linuxmint"

HOMELAB_USER="${SUDO_USER:-$USER}"

# =============================================================================
# STEP 1 — UFW Firewall
# UFW (Uncomplicated Firewall) is the standard firewall tool on Ubuntu/Mint.
# We start with a "deny all inbound, allow all outbound" policy and then
# punch holes only for the services we actually run.
# =============================================================================
section "Configuring UFW firewall"

pkg_install ufw

# Reset to a clean state before applying rules (safe to re-run)
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# ── Always-allowed services ───────────────────────────────────────────────
ufw allow ssh                comment "SSH remote management"
ufw allow 80/tcp             comment "HTTP (Nginx Proxy Manager)"
ufw allow 443/tcp            comment "HTTPS (Nginx Proxy Manager)"
ufw allow 81/tcp             comment "Nginx Proxy Manager admin UI"
ufw allow 9000/tcp           comment "Portainer"
ufw allow 8096/tcp           comment "Jellyfin"
ufw allow 7575/tcp           comment "Homarr dashboard"

# ── Additional services — uncomment as you add them ───────────────────────
# ufw allow 8920/tcp         # Jellyfin HTTPS
# ufw allow 8989/tcp         # Sonarr
# ufw allow 7878/tcp         # Radarr
# ufw allow 9696/tcp         # Prowlarr
# ufw allow 8080/tcp         # qBittorrent web UI

# Enable the firewall (non-interactive)
ufw --force enable
success "UFW firewall enabled"
ufw status verbose

mark_done "UFW firewall configured"

# =============================================================================
# STEP 2 — Fail2ban
# Monitors log files and temporarily bans IPs that show signs of brute-force
# attacks (repeated failed SSH logins, etc.).
# =============================================================================
section "Installing and configuring Fail2ban"

pkg_install fail2ban

# Create a local config file (overrides the default on updates)
# /etc/fail2ban/jail.local takes precedence over /etc/fail2ban/jail.conf
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban an IP for 1 hour after 5 failed attempts within 10 minutes
bantime  = 3600
findtime = 600
maxretry = 5

# Use systemd backend for log parsing (works well on modern Ubuntu/Mint)
backend = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
EOF

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2ban installed and running"
mark_done "Fail2ban configured"

# =============================================================================
# STEP 3 — Harden SSH configuration
# Disabling root login and password auth (if you use keys) are the two
# most important SSH hardening steps.
# =============================================================================
section "Hardening SSH configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Back up original config before modifying
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d)"
info "Backed up sshd_config to ${SSHD_CONFIG}.bak.$(date +%Y%m%d)"

# Disable root login over SSH
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
success "Root SSH login disabled"

# ── Disable password authentication (KEY-BASED LOGIN ONLY) ───────────────
# WARNING: Only enable this AFTER you have set up SSH key-based login.
# If you lock yourself out, you'll need physical access to fix it.
#
# To set up key-based login from your client machine:
#   ssh-keygen -t ed25519           # generate a key pair (once)
#   ssh-copy-id user@server-ip      # copy your public key to the server
# Then uncomment:
#
# sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
# sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
# success "SSH password authentication disabled (key-only login active)"
# mark_done "SSH key-only login enforced"

# ── Change SSH port (security through obscurity) ─────────────────────────
# Changing from port 22 dramatically reduces automated scan noise in logs.
# Make sure to update UFW rules to allow the new port before restarting SSH,
# or you will lose remote access.
#
# NEW_SSH_PORT=2222
# sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" "$SSHD_CONFIG"
# sed -i "s/^Port 22/Port $NEW_SSH_PORT/" "$SSHD_CONFIG"
# ufw delete allow ssh
# ufw allow "$NEW_SSH_PORT"/tcp comment "SSH on custom port"
# success "SSH port changed to $NEW_SSH_PORT"
# warn "Update your SSH client config to use port $NEW_SSH_PORT!"
# mark_done "SSH port changed to $NEW_SSH_PORT"

# Apply SSH config changes
systemctl restart ssh
success "SSH hardening applied"
mark_done "SSH configuration hardened"

# =============================================================================
# STEP 4 — Disable unused network services
# Avahi (mDNS/Bonjour) and cups (printing) are often running by default but
# not needed on a headless homelab server.
# =============================================================================
section "Disabling unnecessary network services"

for service in avahi-daemon cups bluetooth; do
    if systemctl is-active --quiet "$service"; then
        systemctl stop "$service"
        systemctl disable "$service"
        success "Disabled: $service"
    else
        info "Already inactive: $service"
    fi
done

mark_done "Unnecessary services disabled"

# =============================================================================
# STEP 5 — Kernel hardening via sysctl (commented out by default)
# These settings harden the network stack against common attacks.
# They are safe to enable but are left optional since they're advanced.
# =============================================================================
section "Kernel network hardening (optional)"

# ── Uncomment to apply sysctl hardening ──────────────────────────────────
#
# SYSCTL_CONF="/etc/sysctl.d/99-homelab-hardening.conf"
# cat > "$SYSCTL_CONF" << 'EOF'
# # Ignore ICMP broadcast requests (Smurf attack mitigation)
# net.ipv4.icmp_echo_ignore_broadcasts = 1
#
# # Ignore bogus ICMP error responses
# net.ipv4.icmp_ignore_bogus_error_responses = 1
#
# # Enable SYN flood protection
# net.ipv4.tcp_syncookies = 1
#
# # Do not accept ICMP redirects (prevents MITM attacks)
# net.ipv4.conf.all.accept_redirects = 0
# net.ipv6.conf.all.accept_redirects = 0
#
# # Do not send ICMP redirects
# net.ipv4.conf.all.send_redirects = 0
#
# # Disable IP source routing
# net.ipv4.conf.all.accept_source_route = 0
# EOF
#
# sysctl -p "$SYSCTL_CONF"
# success "Kernel hardening parameters applied"
# mark_done "Kernel network hardening applied"

info "Kernel hardening is commented out. Uncomment in this script to enable."

# =============================================================================
# STEP 6 — Docker socket permissions warning
# The Docker socket (/var/run/docker.sock) mounted into containers (like
# Portainer and Homarr) grants those containers root-equivalent access to
# the host. This is a known and accepted tradeoff for homelab convenience,
# but worth knowing about.
# =============================================================================
section "Docker security note"

echo ""
warn "Docker socket notice:"
echo -e "  Portainer and Homarr are configured to mount ${CYAN}/var/run/docker.sock${RESET}."
echo -e "  This gives those containers full control over your Docker host."
echo -e "  This is standard homelab practice, but avoid exposing these"
echo -e "  container UIs directly to the internet without authentication."
echo ""

# =============================================================================
# Done
# =============================================================================
print_summary

echo ""
echo -e "${BOLD}Reminders:${RESET}"
echo -e "  • UFW is active — add new ports with: ${CYAN}sudo ufw allow <port>/tcp${RESET}"
echo -e "  • Check Fail2ban status with: ${CYAN}sudo fail2ban-client status sshd${RESET}"
echo -e "  • SSH root login is now disabled."
echo -e "  • Consider setting up key-based SSH login and disabling passwords."
echo ""
