# Homelab Setup

Beginner-friendly homelab setup scripts for Ubuntu + Docker Compose.

## Structure

```
homelab-setup/
├── 00-core.sh          # Required — Docker, directory structure, compose starters
├── 01-os-tweaks.sh     # LinuxMint-specific quality-of-life (screensaver, SSH, timezone)
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

## What gets installed

| App | Port | Purpose |
|---|---|---|
| Portainer | 9000 | Docker container management GUI |
| Jellyfin | 8096 | Media server |
| Nginx Proxy Manager | 81 (admin) / 80 / 443 | Reverse proxy with GUI |
| Homarr | 7575 | Homepage dashboard |

## Starting your stack

After running `00-core.sh`, log out and back in (for Docker group), then:

```bash
cd ~/homelab/portainer && docker compose up -d
cd ~/homelab/jellyfin  && docker compose up -d
# etc.
```

## Notable commented-out options

- **Intel iGPU transcoding** in Jellyfin compose file
- **Tailscale** remote access VPN in `01-os-tweaks.sh`
- **Auto-login** in `01-os-tweaks.sh`
- **Laptop lid-close behavior** in `01-os-tweaks.sh`
- **SSH key-only login** in `02-hardening.sh`
- **Custom SSH port** in `02-hardening.sh`
- **Kernel sysctl hardening** in `02-hardening.sh`
- **Additional arr-stack ports** (Sonarr, Radarr, etc.) in UFW rules

## Adding more apps

Create a new folder under `~/homelab/` with a `docker-compose.yml` and a `data/` subfolder:

```bash
mkdir -p ~/homelab/myapp/data
nano ~/homelab/myapp/docker-compose.yml
cd ~/homelab/myapp && docker compose up -d
```
