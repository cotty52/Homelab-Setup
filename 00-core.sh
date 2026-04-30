#!/usr/bin/env bash
# =============================================================================
# 00-core.sh — Core homelab setup
# =============================================================================
# This is the only script you MUST run. It sets up Docker and the basic
# directory structure needed to run any homelab Docker Compose stack.
#
# Run with: sudo bash 00-core.sh
# =============================================================================

source "$(dirname "$0")/lib/common.sh"

require_sudo
check_os "linuxmint"

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
CORE_PACKAGES=(
    curl
    git
    htop
    nano
    wget
    ca-certificates
    gnupg
    lsb-release
    net-tools     # provides ifconfig, netstat
    unzip
)

# =============================================================================
# STEP 1 — System update
# =============================================================================
section "Updating system packages"

apt-get update -y
apt-get upgrade -y
mark_done "System updated"

# =============================================================================
# STEP 2 — Install essential CLI tools
# =============================================================================
section "Installing core packages"

pkg_install "${CORE_PACKAGES[@]}"
mark_done "Core packages installed"

# =============================================================================
# STEP 3 — Install Docker Engine
# We use Docker's official repo, NOT the older version from Ubuntu's repos.
# The Ubuntu/Mint version is often out of date and missing Compose v2.
# =============================================================================
section "Installing Docker Engine"

if command -v docker &>/dev/null; then
    info "Docker is already installed: $(docker --version)"
else
    info "Adding Docker's official GPG key and repository..."

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Linux Mint is Ubuntu-based. We pull the Ubuntu codename for the repo.
    # e.g. Mint 21.x → Ubuntu "jammy"; Mint 22.x → Ubuntu "noble"
    UBUNTU_CODENAME=$(. /etc/upstream-release/lsb_release 2>/dev/null \
        && echo "$DISTRIB_CODENAME" \
        || grep -oP '(?<=UBUNTU_CODENAME=).+' /etc/os-release)

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
    # Update /etc/hosts so the new hostname resolves locally
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$DESIRED_HOSTNAME/" /etc/hosts
    success "Hostname changed from '$CURRENT_HOSTNAME' to '$DESIRED_HOSTNAME'"
fi

mark_done "Hostname configured"

# =============================================================================
# STEP 7 — Create homelab directory structure
# Everything lives under ~/homelab/ — one compose file, one data/ folder.
# Persistent data for each app gets its own subfolder under data/ so files
# stay organised without needing separate directories per app.
# =============================================================================
section "Creating homelab directory structure"

mkdir -p "$HOMELAB_DIR"/data/{portainer,jellyfin,nginx-proxy-manager,homarr}

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
echo -e "  5. Run ${CYAN}01-os-tweaks.sh${RESET} to configure Mint-specific settings."
echo -e "  6. Run ${CYAN}02-hardening.sh${RESET} to secure the server."
echo ""
