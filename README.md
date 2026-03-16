## Debian Bookworm installer (Fieldsets)

This installer hardens a fresh **Debian 12 (Bookworm)** server and prepares it to run the Fieldsets framework. It configures SSH, automatic updates, a Docker-compatible firewall, fail2ban, and installs Docker Engine + PowerShell.

### What it does

- **OS validation**: exits unless running on **Debian 12**.
- **Base packages**: installs common tools plus `chrony`, `apparmor`, `fail2ban`, and friends.
- **SSH hardening**:
  - Installs and configures `openssh-server`
  - Uses the repo `config/sshd_config` (default port **2022**)
  - Adds a **PowerShell subsystem** (`Subsystem powershell /usr/bin/pwsh -sshs ...`)
  - Validates config with `sshd -t` and restarts `ssh`
- **Automatic security updates**:
  - Configures unattended upgrades using `config/unattended_upgrades`
  - Enables periodic APT upgrades using `config/auto-upgrades.conf`
- **Firewall (iptables, Docker-compatible)**:
  - Installs `iptables` + `nftables` and selects the nft backend (`iptables-nft`)
  - Applies a baseline ruleset equivalent to:
    - default deny incoming
    - default allow outgoing
    - default deny forwarded/routed
    - allow TCP `${SSH_PORT}`, `80`, `443`
  - Persists rules via `netfilter-persistent`
- **Fail2ban**:
  - Installs `fail2ban`
  - Copies `config/jail.local` and rewrites the ssh jail port to `${SSH_PORT}`
  - Restarts fail2ban
- **Kernel/sysctl hardening**:
  - Applies `config/kernel_hardening.conf`
  - Ensures Docker networking sysctls are applied from `config/docker-networking.conf` into `/etc/sysctl.d/99-zdocker-networking.conf` (so Docker works)
- **Docker Engine**:
  - Runs `src/install-docker.sh` to install **docker-ce** from Docker’s official repo
  - Enables/restarts `docker`
  - Adds `${DEFAULT_ADMIN_USER}` to the `docker` group (if the user exists)
- **PowerShell**:
  - Runs `src/install-powershell.sh` to install **PowerShell (`pwsh`)** from Microsoft’s repo

### Files

- **Main installer**: `install.sh`
- **Config**: `config/`
  - `sshd_config`
  - `jail.local`
  - `kernel_hardening.conf`
  - `unattended_upgrades`
  - `auto-upgrades.conf`
  - `docker-networking.conf`
- **Sub-installers**: `src/`
  - `install-docker.sh`
  - `install-powershell.sh`

### Configuration knobs

You can edit these at the top of `install.sh`:

- **`DEFAULT_ADMIN_USER`**: default `ops` (created if missing, added to `sudo`)
- **`SSH_PORT`**: default `2022`

### How to run

Run as root from this directory (paths are relative to the installer directory):

```bash
sudo bash install.sh
```

### Important notes / safety

- **SSH access**: the installer sets SSH to port **`${SSH_PORT}`** only. Ensure your cloud firewall/security group allows that port before you apply firewall rules.
- **Firewall + Docker**: the firewall uses `iptables` (nft backend) and is intended to coexist with Docker’s rules. If you later harden `DOCKER-USER`, do it carefully to avoid breaking container networking.
- **Reboots**: unattended upgrades are configured to allow automatic reboots (see `config/unattended_upgrades`).