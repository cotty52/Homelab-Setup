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
# All stacks live under ~/homelab/<app-name>/
# Each app gets its own subdirectory to keep compose files and data separate.
# =============================================================================
section "Creating homelab directory structure"

# Core directories
mkdir -p "$HOMELAB_DIR"/{portainer,jellyfin,nginx-proxy-manager,homarr}

# Each app dir gets a data/ subfolder for persistent container data.
# Docker Compose volumes will map into these paths.
for app_dir in "$HOMELAB_DIR"/*/; do
    mkdir -p "${app_dir}data"
done

# Set ownership back to the regular user (since we're running as root/sudo)
chown -R "$HOMELAB_USER":"$HOMELAB_USER" "$HOMELAB_DIR"

success "Homelab directory created at $HOMELAB_DIR"
mark_done "Directory structure created"

# =============================================================================
# STEP 8 — Write starter Docker Compose files
# These are minimal working configs to get the core stack running.
# Edit the .env file in each folder to customize ports, paths, and credentials.
# =============================================================================
section "Writing starter Docker Compose files"

# ── Portainer ─────────────────────────────────────────────────────────────
# Portainer gives you a web GUI to manage all your Docker containers.
# Access at: http://<server-ip>:9000
cat > "$HOMELAB_DIR/portainer/docker-compose.yml" << 'EOF'
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
      - "9443:9443"   # HTTPS — optional but recommended
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock   # allows Portainer to manage Docker
      - ./data:/data
EOF

# ── Jellyfin ──────────────────────────────────────────────────────────────
# Media server. Access at: http://<server-ip>:8096
# Replace /path/to/media with the actual path to your media files.
# Intel iGPU transcoding is commented out — see notes below to enable it.
cat > "$HOMELAB_DIR/jellyfin/docker-compose.yml" << 'EOF'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    network_mode: host   # host networking gives best performance for local streaming
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York   # change to your timezone
    volumes:
      - ./data/config:/config
      - ./data/cache:/cache
      - /path/to/media:/media   # ← CHANGE THIS to your media folder path
    # ── Intel iGPU hardware transcoding ───────────────────────────────────
    # Uncomment the block below to enable hardware-accelerated transcoding.
    # This makes a huge difference for 4K or multiple simultaneous streams.
    # After enabling, go to Jellyfin Dashboard → Playback → Transcoding
    # and select "Intel QSV" or "VA-API" as the hardware acceleration option.
    #
    # devices:
    #   - /dev/dri:/dev/dri
    # group_add:
    #   - "render"   # may be needed depending on your kernel version
EOF

# ── Nginx Proxy Manager ───────────────────────────────────────────────────
# Reverse proxy with a GUI. Lets you use friendly URLs like jellyfin.local
# instead of IP:port. Access the admin UI at: http://<server-ip>:81
# Default login: admin@example.com / changeme (you'll be prompted to change it)
cat > "$HOMELAB_DIR/nginx-proxy-manager/docker-compose.yml" << 'EOF'
services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"     # HTTP traffic
      - "443:443"   # HTTPS traffic
      - "81:81"     # Admin web UI
    volumes:
      - ./data:/data
      - ./data/letsencrypt:/etc/letsencrypt
EOF

# ── Homarr (dashboard) ────────────────────────────────────────────────────
# A clean homepage/dashboard that links to all your services.
# Access at: http://<server-ip>:7575
cat > "$HOMELAB_DIR/homarr/docker-compose.yml" << 'EOF'
services:
  homarr:
    image: ghcr.io/ajnart/homarr:latest
    container_name: homarr
    restart: unless-stopped
    ports:
      - "7575:7575"
    volumes:
      - ./data/configs:/app/data/configs
      - ./data/icons:/app/public/icons
      - /var/run/docker.sock:/var/run/docker.sock   # lets Homarr auto-detect running containers
EOF

# Fix ownership after writing files as root
chown -R "$HOMELAB_USER":"$HOMELAB_USER" "$HOMELAB_DIR"

success "Compose files written to $HOMELAB_DIR"
mark_done "Docker Compose starter files created"

# =============================================================================
# Done
# =============================================================================
print_summary

echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo -e "  1. ${YELLOW}Log out and back in${RESET} so Docker group membership takes effect."
echo -e "  2. Edit the Jellyfin compose file and set your media path:"
echo -e "     ${CYAN}nano $HOMELAB_DIR/jellyfin/docker-compose.yml${RESET}"
echo -e "  3. Start a stack:"
echo -e "     ${CYAN}cd $HOMELAB_DIR/portainer && docker compose up -d${RESET}"
echo -e "  4. Run ${CYAN}01-os-tweaks.sh${RESET} to configure Mint-specific settings."
echo -e "  5. Run ${CYAN}02-hardening.sh${RESET} to secure the server."
echo ""
