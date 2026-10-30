# homelab-setup

Beginner-friendly homelab setup scripts for Docker Compose on **Linux Mint** or **CachyOS**.

The scripts detect your distro automatically and use the matching setup.

| Distro | Package manager | Docker comes from | SSH service |
|---|---|---|---|
| Linux Mint | apt | Docker's official apt repo | `ssh` |
| CachyOS | pacman | Arch repos (`docker`, `docker-compose`, `docker-buildx`) | `sshd` |

## Structure

```
homelab-setup/
├── 00-core.sh          # Required: Docker, directory structure, compose starters
├── 01-os-tweaks.sh     # Quality-of-life (screensaver, SSH, timezone)
├── 02-hardening.sh     # Security hardening (UFW, Fail2ban, SSH lockdown)
├── docker-compose.yml  # Starter stack, same on every distro
├── .env                # Starter config, same on every distro
└── lib/
    ├── common.sh       # Shared logging, checks, and utilities + distro detection
    └── distro/
        ├── mint.sh     # Everything specific to Linux Mint
        └── cachyos.sh  # Everything specific to CachyOS
```

The three numbered scripts are the same on every distro. Anything that differs
(installing packages, installing Docker, service names, desktop settings) lives in
one file per distro under `lib/distro/`.

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

`00-core.sh` copies the starter `docker-compose.yml` and `.env` into `~/homelab/`
(it never overwrites files that are already there).

On an unsupported distro the scripts stop and list what is supported. To force a
setup anyway (untested), name it yourself:

```bash
sudo HOMELAB_DISTRO=cachyos bash 00-core.sh
```

## CachyOS notes

- **Updates are manual.** CachyOS is a rolling release, so unattended upgrades are
  deliberately not set up. Run `sudo pacman -Syu` every week or two.
- **Reboot after kernel updates.** If `00-core.sh` updates the kernel, it stops and asks
  you to reboot, then run it again. Finished steps are skipped on the second run.
  After any later kernel update, reboot before restarting containers.
- **Firewall.** CachyOS ships UFW switched off. `02-hardening.sh` configures and enables
  it. If `firewalld` is running, the script asks before disabling it, since the two
  conflict.
- **Desktop settings** (screensaver, display sleep) target KDE Plasma, CachyOS's default.
  GNOME and XFCE are handled on a best-effort basis. Check
  System Settings → Energy Saving afterwards, because KDE's power settings vary between
  Plasma versions.
- **Auto-login** (optional, commented out in `01-os-tweaks.sh`) is written for SDDM.

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

## Adding another distro

Copy `lib/distro/cachyos.sh` to `lib/distro/<name>.sh`, change it for your distro, and
add one line to the `case` in `load_distro` (`lib/common.sh`). The list of variables and
functions a driver must provide is documented above `load_distro`, and a driver that is
missing one fails with a clear error message.
