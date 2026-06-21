#!/bin/bash
# ============================================================================
# BraanX - DNS Tunneling Support
# ============================================================================
# Provides DNS tunneling services: SlowDNS (dns2tcp) and UDP Gateway (badvpn).
# These allow VPN traffic to traverse DNS ports for censorship evasion.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# ============================================================================
source /etc/braanx/lib/functions.sh

SLOWDNS_DIR="/etc/braanx/slowdns"
UDPGW_DIR="/etc/braanx/udpgw"
BRAANX_CONF="/etc/braanx/braanx.conf"
DNS_PORT=5300
UDPGW_PORTS=(7100 7200 7300)

# ----------------------------------------------------------------------------
# install_slowdns() - Install and configure SlowDNS (dns2tcp) tunnel
# ----------------------------------------------------------------------------
install_slowdns() {
    msg_info "Installing SlowDNS (dns2tcp)..."

    pkg_install dns2tcp bind9utils 2>/dev/null

    mkdir -p "${SLOWDNS_DIR}"

    # Check if dns2tcpd is available
    if ! command -v dns2tcpd &>/dev/null; then
        msg_warn "dns2tcpd not found via package manager, trying compilation..."

        # Install build dependencies
        pkg_install build-essential git autoconf libtool 2>/dev/null

        # Clone and build dns2tcp
        local tmpdir
        tmpdir=$(mktemp -d)
        if git clone --depth 1 https://github.com/zombiedevel/dns2tcp.git "${tmpdir}/dns2tcp" 2>/dev/null; then
            cd "${tmpdir}/dns2tcp"
            autoreconf --install 2>/dev/null
            ./configure --prefix=/usr 2>/dev/null
            make -j$(nproc) 2>/dev/null
            make install 2>/dev/null
            cd - >/dev/null
            rm -rf "${tmpdir}"
            msg_ok "dns2tcp compiled and installed"
        else
            msg_err "Failed to clone dns2tcp repository"
            rm -rf "${tmpdir}"
            return 1
        fi
    fi

    # Get server domain for DNS
    local domain
    domain=$(config_get "DOMAIN")
    local ip_addr
    ip_addr=$(get_public_ip)

    # Generate DNS secret key
    local dns_key
    dns_key=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)

    # Write dns2tcp server config
    cat > "${SLOWDNS_DIR}/dns2tcpd.conf" << EOF
# BraanX - SlowDNS Server Configuration
# dns2tcp server config

listen {
    chroot = "${SLOWDNS_DIR}";
    interface = 0.0.0.0;
    port = ${DNS_PORT};
    user = nobody;
    group = nogroup;
}

domain = "${domain:-dns.braanx.local}";
key = "${dns_key}";
resources {
    ssh : 22;
    openvpn : ${OPENVPN_TCP_PORT:-1194};
}
EOF

    # Set proper permissions
    chown -R nobody:nogroup "${SLOWDNS_DIR}" 2>/dev/null
    touch "${SLOWDNS_DIR}/dns2tcpd.pid"
    chown nobody:nogroup "${SLOWDNS_DIR}/dns2tcpd.pid"

    # Create systemd service
    cat > /etc/systemd/system/slowdns.service << EOF
[Unit]
Description=BraanX SlowDNS (dns2tcp) Server
After=network.target

[Service]
Type=forking
ExecStartPre=/bin/mkdir -p ${SLOWDNS_DIR}
ExecStart=/usr/bin/dns2tcpd -f ${SLOWDNS_DIR}/dns2tcpd.conf -d 1
PIDFile=${SLOWDNS_DIR}/dns2tcpd.pid
ExecStop=/bin/kill -TERM \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    # Save DNS key to config
    config_set "SLOWDNS_KEY" "${dns_key}"
    config_set "SLOWDNS_PORT" "${DNS_PORT}"
    config_set "SLOWDNS_DOMAIN" "${domain:-dns.braanx.local}"

    systemctl daemon-reload
    systemctl enable slowdns &>/dev/null
    systemctl start slowdns

    if systemctl is-active --quiet slowdns; then
        msg_ok "SlowDNS (dns2tcp) running on port ${DNS_PORT}"
    else
        msg_warn "SlowDNS service may not have started - check journalctl -u slowdns"
    fi

    # Open DNS port in firewall
    _open_port "${DNS_PORT}" "udp"
    _open_port "${DNS_PORT}" "tcp"
}

# ----------------------------------------------------------------------------
# install_udpgw() - Install and configure badvpn UDP Gateway
# ----------------------------------------------------------------------------
install_udpgw() {
    msg_info "Installing UDP Gateway (badvpn)..."

    pkg_install build-essential cmake git libssl-dev 2>/dev/null

    mkdir -p "${UDPGW_DIR}"

    local udpgw_bin="/usr/local/bin/badvpn-udpgw"

    # Check if already installed
    if [[ -x "${udpgw_bin}" ]]; then
        msg_info "badvpn-udpgw already installed"
    else
        # Clone and build badvpn
        local tmpdir
        tmpdir=$(mktemp -d)
        if git clone --depth 1 https://github.com/ambrop72/badvpn.git "${tmpdir}/badvpn" 2>/dev/null; then
            cd "${tmpdir}/badvpn"
            mkdir -p build && cd build

            # CMake configuration
            cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
                  -DBUILD_UDPGW=ON \
                  -DBUILD_TUN2TAP=OFF \
                  -DBUILD_TUNDEV=OFF \
                  -DBUILD_DNSTUN=OFF \
                  -DBUILD_NCD=OFF \
                  -DBUILD_SERVAL=OFF \
                  .. 2>/dev/null

            if [[ $? -eq 0 ]]; then
                make -j$(nproc) 2>/dev/null
                cp -f badvpn-udpgw "${udpgw_bin}"
                chmod +x "${udpgw_bin}"
                msg_ok "badvpn-udpgw compiled successfully"
            else
                msg_err "CMake configuration failed for badvpn"
                cd - >/dev/null
                rm -rf "${tmpdir}"
                return 1
            fi

            cd - >/dev/null
            rm -rf "${tmpdir}"
        else
            msg_err "Failed to clone badvpn repository"
            rm -rf "${tmpdir}"
            return 1
        fi
    fi

    # Create systemd services for each UDP gateway port
    local idx=0
    for port in "${UDPGW_PORTS[@]}"; do
        _create_udpgw_service "${port}" "${idx}"
        idx=$((idx + 1))
    done

    config_set "UDPGW_PORTS" "${UDPGW_PORTS[*]}"

    msg_ok "UDP Gateway installed on ports: ${UDPGW_PORTS[*]}"
}

# ----------------------------------------------------------------------------
# _create_udpgw_service() - Create systemd unit for a UDP gateway instance
#   $1 = port
#   $2 = instance index
# ----------------------------------------------------------------------------
_create_udpgw_service() {
    local port="${1}"
    local idx="${2}"
    local name="udpgw-${port}"
    local log_file="/var/log/braanx/udpgw-${port}.log"
    local pid_file="${UDPGW_DIR}/udpgw-${port}.pid"

    mkdir -p /var/log/braanx

    cat > "/etc/systemd/system/${name}.service" << EOF
[Unit]
Description=BraanX UDP Gateway (badvpn) - Port ${port}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/badvpn-udpgw \\
    --listen-addr 127.0.0.1:${port} \\
    --max-clients 200 \\
    --loglevel notice
PIDFile=${pid_file}
Restart=always
RestartSec=5
LimitNOFILE=65535
StandardOutput=append:${log_file}
StandardError=append:${log_file}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${name}" &>/dev/null
    systemctl start "${name}"

    if systemctl is-active --quiet "${name}"; then
        msg_info "UDP Gateway started on port ${port}"
    else
        msg_warn "UDP Gateway on port ${port} may not have started"
    fi
}

# ----------------------------------------------------------------------------
# dnstunnel_status() - Show DNS tunnel and UDP gateway status
# ----------------------------------------------------------------------------
dnstunnel_status() {
    draw_header "DNS TUNNEL STATUS"

    # SlowDNS status
    local slowdns_status
    slowdns_status=$(systemctl is-active slowdns 2>/dev/null)
    local slowdns_port
    slowdns_port=$(config_get "SLOWDNS_PORT")
    local slowdns_domain
    slowdns_domain=$(config_get "SLOWDNS_DOMAIN")

    msg_info "SlowDNS (dns2tcp): ${slowdns_status}"
    draw_table \
        "Status" "${slowdns_status}" \
        "Port" "${slowdns_port:-not configured}" \
        "Domain" "${slowdns_domain:-not configured}" \
        "Key" "$(config_get SLOWDNS_KEY)" \
        "Config" "${SLOWDNS_DIR}/dns2tcpd.conf"

    echo ""

    # UDP Gateway status
    msg_info "UDP Gateway (badvpn-udpgw):"
    for port in "${UDPGW_PORTS[@]}"; do
        local udpgw_status
        udpgw_status=$(systemctl is-active "udpgw-${port}" 2>/dev/null)
        msg_info "  Port ${port}: ${udpgw_status}"
    done

    # Show listening ports
    echo ""
    msg_info "DNS/UDP listening ports:"
    ss -ulnp 2>/dev/null | rg -E "(53[0-9]{2}|7[12]00)" | while read line; do
        echo "  ${line}"
    done
    ss -tlnp 2>/dev/null | rg -E "5300" | while read line; do
        echo "  ${line}"
    done
    echo ""
}

# ----------------------------------------------------------------------------
# _open_port() - Helper to open a port in the firewall
#   $1 = port number
#   $2 = protocol (tcp/udp)
# ----------------------------------------------------------------------------
_open_port() {
    local port="${1}"
    local proto="${2:-tcp}"

    # iptables
    iptables -I INPUT -p "${proto}" --dport "${port}" -j ACCEPT 2>/dev/null

    # Try ufw
    if command -v ufw &>/dev/null; then
        ufw allow "${port}/${proto}" >/dev/null 2>&1
    fi

    # Try firewalld
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" 2>/dev/null
        firewall-cmd --reload 2>/dev/null
    fi
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_slowdns
export -f install_udpgw
export -f dnstunnel_status
export -f _create_udpgw_service
export -f _open_port
