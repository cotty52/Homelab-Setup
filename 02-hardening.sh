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
load_distro

HOMELAB_USER="${SUDO_USER:-$USER}"

# =============================================================================
# STEP 1 — UFW Firewall
# UFW (Uncomplicated Firewall) is the standard firewall tool on Ubuntu/Mint
# and ships with CachyOS (switched off by default).
# We start with a "deny all inbound, allow all outbound" policy and then
# punch holes only for the services we actually run.
# =============================================================================
section "Configuring UFW firewall"

pkg_install ufw

# Make sure no rival firewall manager (e.g. firewalld) is running
prepare_firewall

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
# Make sure the rules are loaded again after a reboot (not automatic on every distro)
systemctl enable ufw || warn "Could not enable the ufw service, so the firewall may not start on boot."
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

# Read logins from the systemd journal (works on Mint and CachyOS alike,
# so no log file path is needed)
backend = systemd

[sshd]
enabled = true
port    = ssh
EOF

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2ban installed and running"
mark_done "Fail2ban configured"

# =============================================================================
# STEP 3 — Harden SSH configuration
# Disabling root login and password auth (if you use keys) are the two
# most important SSH hardening steps.
# The change is checked with `sshd -t` before SSH is restarted, and rolled
# back if the config is invalid, so a typo cannot lock you out.
# =============================================================================
section "Hardening SSH configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"

if [[ ! -f "$SSHD_CONFIG" ]]; then
    warn "No $SSHD_CONFIG found, so the SSH server is not installed."
    warn "Run 01-os-tweaks.sh first (it installs and enables SSH), then re-run this script."
else
    # Back up original config before modifying (keeps the first backup of the day)
    SSHD_BACKUP="${SSHD_CONFIG}.bak.$(date +%Y%m%d)"
    [[ -e "$SSHD_BACKUP" ]] || cp "$SSHD_CONFIG" "$SSHD_BACKUP"
    info "Backed up sshd_config to $SSHD_BACKUP"
    # Copy used for rolling back if the new config turns out to be invalid
    SSHD_ROLLBACK=$(mktemp)
    cp "$SSHD_CONFIG" "$SSHD_ROLLBACK"

    # Disable root login over SSH
    set_sshd_option PermitRootLogin no

    # ── Disable password authentication (KEY-BASED LOGIN ONLY) ───────────────
    # WARNING: Only enable this AFTER you have set up SSH key-based login.
    # If you lock yourself out, you'll need physical access to fix it.
    #
    # To set up key-based login from your client machine:
    #   ssh-keygen -t ed25519           # generate a key pair (once)
    #   ssh-copy-id user@server-ip      # copy your public key to the server
    # Then uncomment:
    #
    # set_sshd_option PasswordAuthentication no

    # ── Change SSH port (security through obscurity) ─────────────────────────
    # Changing from port 22 dramatically reduces automated scan noise in logs.
    # Make sure to update UFW rules to allow the new port before restarting SSH,
    # or you will lose remote access. Also change "port = ssh" in the [sshd]
    # section of /etc/fail2ban/jail.local above to the new port number.
    #
    # NEW_SSH_PORT=2222
    # set_sshd_option Port "$NEW_SSH_PORT"
    # ufw delete allow ssh
    # ufw allow "$NEW_SSH_PORT"/tcp comment "SSH on custom port"
    # success "SSH port changed to $NEW_SSH_PORT"
    # warn "Update your SSH client config to use port $NEW_SSH_PORT!"
    # mark_done "SSH port changed to $NEW_SSH_PORT"

    # Validate, then apply SSH config changes
    install -d -m 0755 /run/sshd   # sshd -t needs this directory to exist
    if sshd -t; then
        systemctl restart "$SSH_SERVICE"
        success "SSH hardening applied"
        if sshd -T 2>/dev/null | grep -qi '^permitrootlogin no'; then
            success "Confirmed: root login over SSH is disabled"
        else
            warn "sshd still reports root login as allowed. Check /etc/ssh/sshd_config.d/ for an override."
        fi
        mark_done "SSH configuration hardened"
    else
        error "The edited sshd_config is invalid. Restoring the previous version."
        cp "$SSHD_ROLLBACK" "$SSHD_CONFIG"
        warn "SSH was left unchanged. Original backup: $SSHD_BACKUP"
    fi
    rm -f "$SSHD_ROLLBACK"
fi

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
