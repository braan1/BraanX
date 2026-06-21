#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - Package Management
# Version: 1.0.0
# ============================================================

[[ -n "$_BNX_PKG_LOADED" ]] && return 0
_BNX_PKG_LOADED=1

# ============================================================
# Core Package Operations
# ============================================================

# Update package lists
pkg_update() {
    bnx_info "Updating package lists..."
    eval "$BNX_PKG_UPDATE" >/dev/null 2>&1
    bnx_success "Package lists updated"
}

# Install one or more packages
pkg_install() {
    local packages=("$@")
    local to_install=()

    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null && ! dpkg -l "$pkg" &>/dev/null 2>&1 && ! rpm -q "$pkg" &>/dev/null 2>&1; then
            to_install+=("$pkg")
        fi
    done

    if (( ${#to_install[@]} > 0 )); then
        bnx_info "Installing packages: ${to_install[*]}"
        case "$BNX_OS_FAMILY" in
            debian)
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${to_install[@]}" >/dev/null 2>&1
                ;;
            rhel|fedora)
                dnf install -y -q "${to_install[@]}" >/dev/null 2>&1
                ;;
            arch)
                pacman -S --noconfirm --needed "${to_install[@]}" >/dev/null 2>&1
                ;;
            suse)
                zypper --non-interactive install "${to_install[@]}" >/dev/null 2>&1
                ;;
            alpine)
                apk add --no-progress "${to_install[@]}" >/dev/null 2>&1
                ;;
        esac
        bnx_success "Packages installed: ${to_install[*]}"
    fi
}

# Remove packages
pkg_remove() {
    local packages=("$@")
    case "$BNX_OS_FAMILY" in
        debian)
            DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "${packages[@]}" >/dev/null 2>&1
            apt-get autoremove -y -qq >/dev/null 2>&1
            ;;
        rhel|fedora)
            dnf remove -y -q "${packages[@]}" >/dev/null 2>&1
            ;;
        arch)
            pacman -R --noconfirm "${packages[@]}" >/dev/null 2>&1
            ;;
        suse)
            zypper --non-interactive remove "${packages[@]}" >/dev/null 2>&1
            ;;
        alpine)
            apk del "${packages[@]}" >/dev/null 2>&1
            ;;
    esac
}

# Check if a package is installed
pkg_installed() {
    local pkg="${1}"
    case "$BNX_OS_FAMILY" in
        debian)  dpkg -l "$pkg" &>/dev/null 2>&1 ;;
        rhel|fedora) rpm -q "$pkg" &>/dev/null 2>&1 ;;
        arch)    pacman -Q "$pkg" &>/dev/null 2>&1 ;;
        suse)    zypper search -i "$pkg" &>/dev/null 2>&1 ;;
        alpine)  apk info -e "$pkg" &>/dev/null 2>&1 ;;
        *)       command -v "$pkg" &>/dev/null ;;
    esac
}

# ============================================================
# Install BraanX Core Dependencies
# ============================================================

install_base_deps() {
    bnx_info "Installing base dependencies..."
    local base_packages=(
        curl wget unzip tar gzip bzip2 xz-utils
        ca-certificates gnupg2 apt-transport-https
        jq openssl cron socat dnsutils net-tools
        lsof procps htop
    )

    case "$BNX_OS_FAMILY" in
        debian)
            base_packages+=(software-properties-common)
            ;;
        rhel|fedora)
            base_packages+=(epel-release dnf-utils)
            ;;
        arch)
            # base-devel provides many needed tools
            base_packages+=(base-devel)
            ;;
        suse)
            base_packages+=(zypper-utils)
            ;;
    esac

    pkg_update
    pkg_install "${base_packages[@]}"
    bnx_success "Base dependencies installed"
}

# ============================================================
# Download & Install Xray Core
# ============================================================

install_xray() {
    local xray_version="${1:-latest}"
    local xray_dir="/usr/local/xray"
    local xray_bin="${xray_dir}/xray"
    local install_url

    if [[ "$xray_version" == "latest" ]]; then
        install_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${BNX_ARCH}.zip"
    else
        install_url="https://github.com/XTLS/Xray-core/releases/download/v${xray_version}/Xray-linux-${BNX_ARCH}.zip"
    fi

    bnx_info "Downloading Xray Core (${BNX_ARCH})..."
    mkdir -p "$xray_dir"

    if curl -L -o /tmp/xray.zip "$install_url" --progress-bar 2>&1; then
        unzip -oq /tmp/xray.zip -d "$xray_dir"
        chmod +x "${xray_bin}"
        rm -f /tmp/xray.zip

        # Create systemd service
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
ExecStart=${xray_bin} run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray >/dev/null 2>&1

        local ver
        ver=$("${xray_bin}" version 2>/dev/null | head -1)
        bnx_success "Xray Core installed: ${ver:-installed}"
    else
        bnx_error "Failed to download Xray Core"
        return 1
    fi
}

# ============================================================
# Download & Install Nginx
# ============================================================

install_nginx() {
    if command -v nginx &>/dev/null; then
        bnx_info "Nginx already installed"
        return 0
    fi

    bnx_info "Installing Nginx..."

    case "$BNX_OS_FAMILY" in
        debian)
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian $(lsb_release -cs 2>/dev/null || echo bookworm) nginx" \
                > /etc/apt/sources.list.d/nginx.list
            apt-get update -qq
            apt-get install -y -qq nginx >/dev/null 2>&1
            ;;
        rhel|fedora)
            dnf install -y -q nginx >/dev/null 2>&1
            ;;
        arch)
            pacman -S --noconfirm --needed nginx >/dev/null 2>&1
            ;;
        suse)
            zypper --non-interactive install nginx >/dev/null 2>&1
            ;;
    esac

    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx 2>/dev/null
    bnx_success "Nginx installed and running"
}

# ============================================================
# SSL Certificate Management (Let's Encrypt)
# ============================================================

install_certbot() {
    if command -v certbot &>/dev/null; then
        return 0
    fi

    bnx_info "Installing Certbot..."
    case "$BNX_OS_FAMILY" in
        debian)
            apt-get install -y -qq certbot python3-certbot-nginx >/dev/null 2>&1
            ;;
        rhel|fedora)
            dnf install -y -q certbot python3-certbot-nginx >/dev/null 2>&1
            ;;
        arch)
            pacman -S --noconfirm --needed certbot >/dev/null 2>&1
            ;;
        suse)
            zypper --non-interactive install certbot >/dev/null 2>&1
            ;;
    esac
    bnx_success "Certbot installed"
}

issue_certificate() {
    local domain="${1}"
    local email="${2}"

    if [[ -z "$domain" ]]; then
        bnx_error "Domain name required"
        return 1
    fi

    install_certbot

    bnx_info "Requesting SSL certificate for ${domain}..."
    certbot certonly --nginx -d "$domain" --non-interactive --agree-tos -m "${email:-admin@${domain}}" 2>/dev/null

    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        bnx_success "SSL certificate issued for ${domain}"
        return 0
    else
        bnx_error "Failed to issue SSL certificate"
        return 1
    fi
}

# ============================================================
# Port & Firewall Management
# ============================================================

open_port() {
    local port="${1}"
    local proto="${2:-tcp}"

    # iptables
    if command -v iptables &>/dev/null; then
        iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT
    fi

    # firewalld
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    # ufw
    if command -v ufw &>/dev/null && ufw status | grep -q active; then
        ufw allow "${port}/${proto}" >/dev/null 2>&1
    fi
}

close_port() {
    local port="${1}"
    local proto="${2:-tcp}"

    if command -v iptables &>/dev/null; then
        iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null
    fi

    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi

    if command -v ufw &>/dev/null && ufw status | grep -q active; then
        ufw delete allow "${port}/${proto}" >/dev/null 2>&1
    fi
}

# ============================================================
# Service Management Helpers
# ============================================================

enable_service() {
    local name="${1}"
    systemctl daemon-reload
    systemctl enable "$name" >/dev/null 2>&1
    systemctl start "$name" 2>/dev/null
}

restart_service() {
    local name="${1}"
    systemctl restart "$name" 2>/dev/null
}

stop_service() {
    local name="${1}"
    systemctl stop "$name" 2>/dev/null
    systemctl disable "$name" >/dev/null 2>&1
}

service_status() {
    local name="${1}"
    if systemctl is-active "$name" &>/dev/null; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ============================================================
# Download Helper
# ============================================================

download_file() {
    local url="${1}"
    local dest="${2}"
    local retries="${3:-3}"
    local attempt=1

    while (( attempt <= retries )); do
        if curl -L -o "$dest" --max-time 60 --connect-timeout 15 "$url" --progress-bar 2>&1; then
            return 0
        fi
        bnx_warning "Download attempt ${attempt} failed. Retrying..."
        ((attempt++))
        sleep 2
    done

    bnx_error "Failed to download: $url"
    return 1
}
