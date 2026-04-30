# homelab-setup

Beginner-friendly homelab setup scripts for Linux Mint + Docker Compose.

## Structure

```
homelab-setup/
├── 00-core.sh          # Required — Docker, directory structure, compose starters
├── 01-os-tweaks.sh     # Mint-specific quality-of-life (screensaver, SSH, timezone)
├── 02-hardening.sh     # Security hardening (UFW, Fail2ban, SSH lockdown)
└── lib/
    └── common.sh       # Shared logging, checks, and utilities
```

## Quick Start

```bash
# 1. Clone or copy this folder to the server
# 2. Make scripts executable
chmod +x *.sh

# 3. Run in order
sudo bash 00-core.sh       # always run this first
sudo bash 01-os-tweaks.sh  # recommended
sudo bash 02-hardening.sh  # recommended
```

## Directory layout after setup

```
~/homelab/
├── docker-compose.yml   # single file running the entire stack
├── .env                 # your personal config (media path, etc.) — edit this first
└── data/
    ├── portainer/
    ├── jellyfin/
    ├── nginx-proxy-manager/
    └── homarr/
```

## Starting your stack

After running `00-core.sh`, log out and back in (for Docker group membership), then:

```bash
# Set your media path
nano ~/homelab/.env

# Start everything
cd ~/homelab && docker compose up -d

# Useful commands
docker compose logs -f              # tail all logs
docker compose logs -f jellyfin     # tail one service
docker compose pull                 # pull latest images
docker compose up -d                # restart with updated images after pull
docker compose down                 # stop everything
```

## Service URLs

| App | Port | Purpose |
|---|---|---|
| Portainer | 9000 | Docker container management GUI |
| Jellyfin | 8096 | Media server |
| Nginx Proxy Manager | 81 (admin) / 80 / 443 | Reverse proxy with GUI |
| Homarr | 7575 | Homepage dashboard |

## Notable commented-out options

**In `docker-compose.yml`:**
- Intel iGPU hardware transcoding for Jellyfin
- Jellyseerr (media requests)
- Full arr stack: Sonarr, Radarr, Prowlarr, qBittorrent

**In `01-os-tweaks.sh`:**
- Tailscale remote access VPN
- Auto-login on boot
- Laptop lid-close behavior

**In `02-hardening.sh`:**
- SSH key-only login (disable password auth)
- Custom SSH port
- Kernel sysctl network hardening

## Adding more apps

Add a new service block to `~/homelab/docker-compose.yml`, create its data dir, and restart:

```bash
mkdir -p ~/homelab/data/myapp
nano ~/homelab/docker-compose.yml   # add service block
cd ~/homelab && docker compose up -d
```
