#!/usr/bin/env bash
# =============================================================================
# 00-core.sh — Core homelab setup
# =============================================================================
# This is the only script you MUST run. It sets up Docker and the basic
# directory structure needed to run any homelab Docker Compose stack.
#
# Supported: Linux Mint, CachyOS (see lib/distro/ for the per-distro details)
#
# Run with: sudo bash 00-core.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_sudo
load_distro

# -----------------------------------------------------------------------------
# Configuration — edit these before running if needed
# -----------------------------------------------------------------------------

# The non-root user that will own the homelab files and run Docker.
# Defaults to the user who invoked sudo (i.e. your normal login user).
HOMELAB_USER="${SUDO_USER:-$USER}"
HOMELAB_USER_HOME=$(eval echo "~$HOMELAB_USER")

# Root directory for all Docker Compose stacks and config.
HOMELAB_DIR="$HOMELAB_USER_HOME/homelab"

# Hostname to assign this machine on the local network.
# Keep it short and lowercase — it shows up in your router and SSH prompts.
DESIRED_HOSTNAME="homelab"

# Essential CLI tools to install alongside Docker.
# (Each distro driver adds a few of its own on top, see DISTRO_CORE_PACKAGES.)
CORE_PACKAGES=(
    curl
    git
    htop
    nano
    wget
    net-tools     # provides ifconfig, netstat
    unzip
    "${DISTRO_CORE_PACKAGES[@]}"
)

# =============================================================================
# STEP 1 — System update
# =============================================================================
section "Updating system packages"

pkg_update
mark_done "System updated"

# Some distros need a reboot after a kernel update before Docker works reliably.
if [[ "${REBOOT_REQUIRED:-0}" == "1" ]]; then
    print_summary
    warn "The kernel was updated, so the running kernel no longer matches what is installed."
    warn "Reboot now, then run this script again: sudo bash $0"
    warn "Steps that are already done are skipped on the second run."
    exit 0
fi

# =============================================================================
# STEP 2 — Install essential CLI tools
# =============================================================================
section "Installing core packages"

pkg_install "${CORE_PACKAGES[@]}"
mark_done "Core packages installed"

# =============================================================================
# STEP 3 — Install Docker Engine
# How Docker is installed depends on the distro (official Docker apt repo on
# Mint, the regular package repos on CachyOS), see install_docker in
# lib/distro/<your-distro>.sh
# =============================================================================
section "Installing Docker Engine"

if command -v docker &>/dev/null; then
    info "Docker is already installed: $(docker --version)"
else
    install_docker
fi

mark_done "Docker Engine installed"

# =============================================================================
# STEP 4 — Enable and start Docker service
# =============================================================================
section "Enabling Docker service"

systemctl enable docker
systemctl start docker
success "Docker service is running"
mark_done "Docker service enabled"

# =============================================================================
# STEP 5 — Add user to the docker group
# This lets your user run docker commands without sudo.
# NOTE: Takes effect on next login — remind the user to log out/in after setup.
# =============================================================================
section "Adding $HOMELAB_USER to the docker group"

if id -nG "$HOMELAB_USER" | grep -qw "docker"; then
    info "$HOMELAB_USER is already in the docker group"
else
    usermod -aG docker "$HOMELAB_USER"
    success "$HOMELAB_USER added to docker group"
fi

mark_done "User added to docker group"

# =============================================================================
# STEP 6 — Set hostname
# =============================================================================
section "Setting hostname to '$DESIRED_HOSTNAME'"

CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == "$DESIRED_HOSTNAME" ]]; then
    info "Hostname already set to '$DESIRED_HOSTNAME'"
else
    hostnamectl set-hostname "$DESIRED_HOSTNAME"
    # Update /etc/hosts so the new hostname resolves locally.
    # Mint has a 127.0.1.1 line to edit; some distros (Arch-based) don't, so add one.
    if grep -q '^127\.0\.1\.1' /etc/hosts; then
        sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$DESIRED_HOSTNAME/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$DESIRED_HOSTNAME" >> /etc/hosts
    fi
    success "Hostname changed from '$CURRENT_HOSTNAME' to '$DESIRED_HOSTNAME'"
fi

mark_done "Hostname configured"

# =============================================================================
# STEP 7 — Create homelab directory structure
# Everything lives under ~/homelab/ — one compose file, one data/ folder.
# Persistent data for each app gets its own subfolder under data/ so files
# stay organised without needing separate directories per app.
# The starter docker-compose.yml and .env next to this script are copied in
# (an existing copy is never overwritten).
# =============================================================================
section "Creating homelab directory structure"

mkdir -p "$HOMELAB_DIR"/data/{portainer,jellyfin,nginx-proxy-manager,homarr}

for starter in docker-compose.yml .env; do
    if [[ -f "$HOMELAB_DIR/$starter" ]]; then
        info "$starter already exists in $HOMELAB_DIR, leaving it alone"
    elif [[ -f "$SCRIPT_DIR/$starter" ]]; then
        cp "$SCRIPT_DIR/$starter" "$HOMELAB_DIR/$starter"
        success "Copied starter $starter to $HOMELAB_DIR"
    else
        warn "No $starter found next to this script, so none was copied."
    fi
done

chown -R "$HOMELAB_USER":"$HOMELAB_USER" "$HOMELAB_DIR"

success "Homelab directory created at $HOMELAB_DIR"
mark_done "Directory structure created"

# =============================================================================
# Done
# =============================================================================
print_summary

echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. ${YELLOW}Log out and back in${RESET} so Docker group membership takes effect."
echo -e "  2. Set your media path in the .env file:"
echo -e "     ${CYAN}nano $HOMELAB_DIR/.env${RESET}"
echo -e "  3. Start the full stack:"
echo -e "     ${CYAN}cd $HOMELAB_DIR && docker compose up -d${RESET}"
echo -e "  4. Enable Intel iGPU transcoding in Jellyfin (optional but recommended):"
echo -e "     Uncomment the 'devices' block in docker-compose.yml, then"
echo -e "     go to Jellyfin → Dashboard → Playback → Transcoding → Intel QSV"
echo -e "  5. Run ${CYAN}01-os-tweaks.sh${RESET} to configure OS-specific settings."
echo -e "  6. Run ${CYAN}02-hardening.sh${RESET} to secure the server."
echo ""
