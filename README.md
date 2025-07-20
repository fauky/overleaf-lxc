# Selfhost Overleaf Community Edition in LXC Container

## About
This repository contains a single script for selfhosting Overleaf Community Edition in an all-in-one LXC container. It has been tested in an Ubuntu 24.04 LXC on Proxmox.

## Installation
Though this script has only been tested in an Ubuntu 24.04 LXC on Proxmox 8.4.1, it should technically install on a bare metal  Ubuntu 24.04 Desktop/Server too.

To selfhost Overleaf Community Edition, simply download this script and execute with root or sudo.

```
sudo ./overleaf-lxc.sh
```

Or simply run the following commands inside the LXC container to download and run the script in one go.

```
# install curl
apt update && apt install -y curl

# install Overleaf
bash -c "$(curl -fsSL https://raw.githubusercontent.com/fauky/overleaf-lxc/main/overleaf-lxc.sh)"
```

## Account Setup
There is no default overleaf account created during installation. Create your first account at http://192.168.x.x/launchpad

## Customization

Take a look at all the environmental variables at overleaf docs at: https://docs.overleaf.com/on-premises/configuration/overleaf-toolkit/environment-variables

Add/modify environmental variables in `/etc/overleaf/env.sh` to customize your installation to suit your needs.

Restart systemd services after modifying environmental variables.

```
systemctl restart overleaf-*
```

Check status of systemd services
```
systemctl status overleaf-*
```

## Reverse Proxy Setup
Simply point your reverse proxy to this endpoint: http://192.168.x.x:80

Replace **192.168.x.x** with the actual IP address of your LXC container.

To make Overleaf aware of reverse proxy, add the following variables to `/etc/overleaf/env.sh`

```
OVERLEAF_SITE_URL=https://leaf.your-domain.com/
OVERLEAF_BEHIND_PROXY=true
OVERLEAF_SECURE_COOKIE=true
```

Then restart overleaf web service

```
systemctl restart overleaf-web
```

## Troubleshooting
Log files for all Overleaf systemd services are located at `/var/log/overleaf/`

Review the log files in case you are experiencing problems.
