#!/usr/bin/env bash

#===
# install.sh: Debian shell script to install fieldsets data pipeline framework.
#
#
#===

set -eEa -o pipefail

#===
# Variables
#===
export DEBIAN_VERSION=12
export DEBIAN_CODENAME='bookworm'
export DEBIAN_FRONTEND='noninteractive'
export DEFAULT_ADMIN_USER='ops'
export SSH_PORT=2022
export LOGFILE='/var/tmp/install.log'

#===
# Functions
#===

log() {
    # Log to console and logfile (best effort)
    local msg="$*"
    echo "[$(date -Is)] $msg" | tee -a "$LOGFILE" >/dev/null || true
}

run_script() {
    local script_path="$1"
    if [ ! -f "$script_path" ]; then
        log "Missing script: $script_path"
        exit 1
    fi
    log "Running $script_path"
    chmod +x "$script_path" || true
    (DEFAULT_ADMIN_USER="$DEFAULT_ADMIN_USER" DEBIAN_CODENAME="$DEBIAN_CODENAME" bash "$script_path") | tee -a "$LOGFILE"
}

install_dependencies() {
    apt-get update
    apt-get upgrade -y
    apt-get --purge remove xinetd nis yp-tools tftpd atftpd tftpd-hpa telnetd rsh-server rsh-redone-server
    apt-get install -y --no-install-recommends \
        openssh-server openssh-client \
        rsync git curl wget gnupg2 lsb-release apt-transport-https ca-certificates software-properties-common \
        sudo unattended-upgrades apt-listchanges bsd-mailx net-tools apt-config-auto-update \
        autossh \
        chrony \
        apparmor apparmor-utils \
        fail2ban
}

install_iptables_for_docker() {
    # Docker expects to be able to program iptables rules. On Debian 12, the
    # recommended backend is the nftables-based iptables implementation.
    apt-get install -y --no-install-recommends iptables iptables-persistent nftables

    if command -v update-alternatives >/dev/null 2>&1; then
        if [ -x /usr/sbin/iptables-nft ]; then
            update-alternatives --set iptables /usr/sbin/iptables-nft || true
        fi
        if [ -x /usr/sbin/ip6tables-nft ]; then
            update-alternatives --set ip6tables /usr/sbin/ip6tables-nft || true
        fi
        if [ -x /usr/sbin/arptables-nft ]; then
            update-alternatives --set arptables /usr/sbin/arptables-nft || true
        fi
        if [ -x /usr/sbin/ebtables-nft ]; then
            update-alternatives --set ebtables /usr/sbin/ebtables-nft || true
        fi
    fi

    # Required for container/bridge networking
    modprobe br_netfilter || true
    modprobe overlay || true

    # Ensure these win over the general hardening sysctls.
    cat ./config/docker-networking.conf > /etc/sysctl.d/99-zdocker-networking.conf
    sysctl --system >/dev/null || true
}

configure_iptables_firewall() {
    # Replace UFW policy with an iptables ruleset:
    # - default deny incoming
    # - default allow outgoing
    # - default deny routed/forwarded
    #
    # Docker will still manage its own NAT/FORWARD rules; we ensure the base
    # policy is sane and persist it via iptables-persistent.

    local ssh_port="${SSH_PORT:-2022}"

    # IPv4
    iptables -F
    iptables -X || true

    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # Common basics
    iptables -A INPUT -p icmp -j ACCEPT || true

    # Allow SSH + web
    iptables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT

    # DOCKER-USER is evaluated before Docker's own rules; keep it permissive
    # unless the operator explicitly hardens it later.
    iptables -N DOCKER-USER 2>/dev/null || true
    iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -C DOCKER-USER -j RETURN 2>/dev/null || iptables -A DOCKER-USER -j RETURN

    # IPv6 (best-effort; don't fail installer on hosts without IPv6)
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -F || true
        ip6tables -X || true

        ip6tables -P INPUT DROP || true
        ip6tables -P FORWARD DROP || true
        ip6tables -P OUTPUT ACCEPT || true

        ip6tables -A INPUT -i lo -j ACCEPT || true
        ip6tables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true

        ip6tables -A INPUT -p ipv6-icmp -j ACCEPT || true

        ip6tables -A INPUT -p tcp --dport "$ssh_port" -j ACCEPT || true
        ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT || true
        ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT || true

        ip6tables -N DOCKER-USER 2>/dev/null || true
        ip6tables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || ip6tables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
        ip6tables -C DOCKER-USER -j RETURN 2>/dev/null || ip6tables -A DOCKER-USER -j RETURN || true
    fi

    # Persist rules
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    if command -v ip6tables-save >/dev/null 2>&1; then
        ip6tables-save > /etc/iptables/rules.v6 || true
    fi

    systemctl enable netfilter-persistent >/dev/null 2>&1 || true
    systemctl restart netfilter-persistent >/dev/null 2>&1 || true
}

ensure_admin_user() {
    if ! id -u "$DEFAULT_ADMIN_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$DEFAULT_ADMIN_USER"
    fi
    usermod -aG sudo "$DEFAULT_ADMIN_USER"
}

configure_apt_auto_updates() {
    cat ./config/auto-upgrades.conf > /etc/apt/apt.conf.d/20auto-upgrades
}

configure_sshd() {
    cp ./config/sshd_config /etc/ssh/sshd_config
    chown root:root /etc/ssh/sshd_config
    chmod 600 /etc/ssh/sshd_config
    sshd -t
    systemctl enable ssh || true
    systemctl restart ssh || true
}

setup_environment() {
    ensure_admin_user
    # configure sshd
    configure_sshd
    # configure unattended upgrades
    cp ./config/unattended_upgrades /etc/apt/apt.conf.d/50unattended-upgrades
    configure_apt_auto_updates
    systemctl enable unattended-upgrades || true
    systemctl start unattended-upgrades || true

    # Respect systems where apt-daily-upgrade is explicitly masked.
    if ! systemctl is-enabled apt-daily-upgrade.service 2>/dev/null | grep -qi masked; then
        systemctl enable apt-daily-upgrade.timer || true
        systemctl start apt-daily-upgrade.timer || true
    fi
    # configure sudoers
    echo '%'"${DEFAULT_ADMIN_USER}"' ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/10-admin-user
    chmod 0440 /etc/sudoers.d/10-admin-user
    # configure firewall rules (iptables; compatible with Docker)
    configure_iptables_firewall
    # block brute force attacks with fail2ban
    cp ./config/jail.local /etc/fail2ban/jail.local
    # Ensure fail2ban matches our configured SSH port
    sed -i "s/^port[[:space:]]*=[[:space:]]*2022[[:space:]]*$/port    = ${SSH_PORT:-2022}/" /etc/fail2ban/jail.local || true
    systemctl enable fail2ban || true
    systemctl restart fail2ban || true

    # kernel hardening
    cp ./config/kernel_hardening.conf /etc/sysctl.d/99-kernel-hardening.conf
    sysctl --system >/dev/null || true
}

#===
# Main
#===
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Use sudo."
        exit 1
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        CODENAME=$VERSION_CODENAME
        log "Setting up Fieldsets Operating System for: $OS $VERSION"
        if [[ "$OS" == "debian" && "$VERSION" == "$DEBIAN_VERSION" ]]; then
            log "Debian Bookworm detected. Proceeding with installation."
        else
            log "Unsupported Debian version. This installer is designed for Debian 12 (Bookworm). Exiting."
            exit 1
        fi
    else
        log "Unsupported Distribution. Exiting."
        exit 1
    fi

    echo "Starting FieldSets Installation..." | tee -a "$LOGFILE"
    install_dependencies
    install_iptables_for_docker
    run_script ./src/install-docker.sh
    run_script ./src/install-powershell.sh
    setup_environment
    echo "Installation completed successfully." | tee -a "$LOGFILE"
}

main "$@"