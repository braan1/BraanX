#!/bin/bash
# ============================================================================
# BraanX - OpenVPN Installer
# ============================================================================
# Installs and manages OpenVPN server with both TCP and UDP modes,
# PKI certificate management, and client profile generation.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# Database: /etc/braanx/db/braanx.db
# ============================================================================
source /etc/braanx/lib/functions.sh

OVPN_DIR="/etc/braanx/openvpn"
OVPN_PKI="${OVPN_DIR}/easy-rsa"
OVPN_TCP_PORT=1194
OVPN_UDP_PORT=2200
OVPN_TCP_CONF="/etc/openvpn/server/server-tcp-${OVPN_TCP_PORT}.conf"
OVPN_UDP_CONF="/etc/openvpn/server/server-udp-${OVPN_UDP_PORT}.conf"
OVPN_TEMPLATE="${OVPN_DIR}/client-template.ovpn"
BRAANX_CONF="/etc/braanx/braanx.conf"
BRAANX_DB="/etc/braanx/db/braanx.db"

# ----------------------------------------------------------------------------
# install_openvpn() - Full OpenVPN server installation
# ----------------------------------------------------------------------------
install_openvpn() {
    msg_info "Installing OpenVPN server..."
    pkg_install openvpn easy-rsa iptables netfilter-persistent

    # Create directories
    mkdir -p "${OVPN_DIR}" "${OVPN_DIR}/certs" "${OVPN_DIR}/profiles"
    chmod 700 "${OVPN_DIR}"

    # Initialize PKI with easy-rsa
    _init_pki

    # Generate server configs
    local domain
    local ip_addr
    domain=$(config_get "DOMAIN")
    ip_addr=$(get_public_ip)

    # --- TCP Server Config ---
    msg_info "Creating OpenVPN TCP server config..."
    mkdir -p /etc/openvpn/server /etc/openvpn/ccd

    local tcp_conf
    tcp_conf=$(config_get "OVPN_TCP_PORT")
    [[ -n "${tcp_conf}" ]] && OVPN_TCP_PORT=${tcp_conf}
    OVPN_TCP_CONF="/etc/openvpn/server/server-tcp-${OVPN_TCP_PORT}.conf"

    cat > "${OVPN_TCP_CONF}" << EOF
# BraanX OpenVPN Server - TCP
port ${OVPN_TCP_PORT}
proto tcp-server
dev tun
topology subnet

ca ${OVPN_PKI}/pki/ca.crt
cert ${OVPN_PKI}/pki/issued/server.crt
key ${OVPN_PKI}/pki/private/server.key
dh ${OVPN_PKI}/pki/dh.pem
tls-crypt ${OVPN_PKI}/pki/tls-crypt.key

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp-tcp.txt

# Push routes and DNS
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Keepalive and timeouts
keepalive 10 120
max-clients 100

# Security
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status-tcp.log
log-append /var/log/openvpn/openvpn-tcp.log
verb 3
explicit-exit-notify 0

# Management
management localhost 7505
EOF

    # --- UDP Server Config ---
    msg_info "Creating OpenVPN UDP server config..."
    local udp_conf
    udp_conf=$(config_get "OVPN_UDP_PORT")
    [[ -n "${udp_conf}" ]] && OVPN_UDP_PORT=${udp_conf}
    OVPN_UDP_CONF="/etc/openvpn/server/server-udp-${OVPN_UDP_PORT}.conf"

    cat > "${OVPN_UDP_CONF}" << EOF
# BraanX OpenVPN Server - UDP
port ${OVPN_UDP_PORT}
proto udp
dev tun
topology subnet

ca ${OVPN_PKI}/pki/ca.crt
cert ${OVPN_PKI}/pki/issued/server.crt
key ${OVPN_PKI}/pki/private/server.key
dh ${OVPN_PKI}/pki/dh.pem
tls-crypt ${OVPN_PKI}/pki/tls-crypt.key

server 10.9.0.0 255.255.255.0
ifconfig-pool-persist /var/log/openvpn/ipp-udp.txt

# Push routes and DNS
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Keepalive and timeouts
keepalive 10 120
max-clients 100

# Security
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status-udp.log
log-append /var/log/openvpn/openvpn-udp.log
verb 3
explicit-exit-notify 1

# Management
management localhost 7506
EOF

    # Create log directory
    mkdir -p /var/log/openvpn

    # Enable IP forwarding
    _enable_ip_forwarding

    # Configure NAT with iptables
    _configure_iptables

    # Create client template
    _create_client_template

    # Create systemd service symlinks
    ln -sf /lib/systemd/system/openvpn-server@.service \
        /etc/systemd/system/openvpn-server@server-tcp-${OVPN_TCP_PORT}.service 2>/dev/null
    ln -sf /lib/systemd/system/openvpn-server@.service \
        /etc/systemd/system/openvpn-server@server-udp-${OVPN_UDP_PORT}.service 2>/dev/null
    systemctl daemon-reload

    # Enable and start
    systemctl enable "openvpn-server@server-tcp-${OVPN_TCP_PORT}" &>/dev/null
    systemctl enable "openvpn-server@server-udp-${OVPN_UDP_PORT}" &>/dev/null
    systemctl start "openvpn-server@server-tcp-${OVPN_TCP_PORT}"
    systemctl start "openvpn-server@server-udp-${OVPN_UDP_PORT}"

    # Initialize database
    db_query "CREATE TABLE IF NOT EXISTS openvpn_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        cert_fingerprint TEXT,
        days INTEGER NOT NULL,
        created_at TEXT DEFAULT (datetime('now','localtime')),
        expires_at TEXT,
        active INTEGER DEFAULT 1,
        protocol TEXT DEFAULT 'both'
    )"

    msg_ok "OpenVPN installed - TCP:${OVPN_TCP_PORT} UDP:${OVPN_UDP_PORT}"
}

# ----------------------------------------------------------------------------
# _init_pki() - Initialize PKI with easy-rsa
# ----------------------------------------------------------------------------
_init_pki() {
    msg_info "Initializing PKI (easy-rsa)..."

    # Copy easy-rsa scripts
    if [[ -d /usr/share/easy-rsa ]]; then
        cp -a /usr/share/easy-rsa/* "${OVPN_PKI}/" 2>/dev/null
    elif command -v make-cadir &>/dev/null; then
        make-cadir "${OVPN_PKI}"
    else
        mkdir -p "${OVPN_PKI}"
        # Create a minimal vars file
        cat > "${OVPN_PKI}/vars" << VEOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "California"
set_var EASYRSA_REQ_CITY       "San Francisco"
set_var EASYRSA_REQ_ORG        "BraanX"
set_var EASYRSA_REQ_EMAIL      "admin@braanx.local"
set_var EASYRSA_REQ_OU         "BraanX VPN"
set_var EASYRSA_ALGO           "ec"
set_var EASYRSA_DIGEST         "sha512"
VEOF
    fi

    cd "${OVPN_PKI}" || return 1

    # Initialize PKI (non-interactive)
    if [[ ! -f pki/ca.crt ]]; then
        ./easyrsa --batch init-pki
        ./easyrsa --batch --req-cn "BraanX-CA" build-ca nopass
        msg_ok "CA certificate generated"
    fi

    # Generate server cert
    if [[ ! -f pki/issued/server.crt ]]; then
        ./easyrsa --batch --req-cn "BraanX-Server" gen-req server nopass
        ./easyrsa --batch sign-req server server
        msg_ok "Server certificate generated"
    fi

    # Generate DH params
    if [[ ! -f pki/dh.pem ]]; then
        ./easyrsa --batch gen-dh
        msg_ok "DH parameters generated"
    fi

    # Generate TLS crypt key
    if [[ ! -f pki/tls-crypt.key ]]; then
        openvpn --genkey secret pki/tls-crypt.key
        msg_ok "TLS crypt key generated"
    fi

    cd - >/dev/null
}

# ----------------------------------------------------------------------------
# _enable_ip_forwarding() - Enable kernel IP forwarding
# ----------------------------------------------------------------------------
_enable_ip_forwarding() {
    msg_info "Enabling IP forwarding..."
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i 's/^#*net.ipv4.ip_forward=.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
        if ! rg -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    msg_ok "IP forwarding enabled"
}

# ----------------------------------------------------------------------------
# _configure_iptables() - Set up NAT rules for OpenVPN
# ----------------------------------------------------------------------------
_configure_iptables() {
    msg_info "Configuring iptables NAT rules..."

    local interface
    interface=$(ip route | awk '/default/ {print $5; exit}')
    [[ -z "${interface}" ]] && interface="eth0"

    # NAT for TCP subnet
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "${interface}" -j MASQUERADE
    # NAT for UDP subnet
    iptables -t nat -A POSTROUTING -s 10.9.0.0/24 -o "${interface}" -j MASQUERADE
    # Allow forwarding
    iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
    iptables -A FORWARD -s 10.9.0.0/24 -j ACCEPT
    iptables -A FORWARD -d 10.8.0.0/24 -j ACCEPT
    iptables -A FORWARD -d 10.9.0.0/24 -j ACCEPT

    # Save rules
    netfilter-persistent save 2>/dev/null || {
        # Fallback: save via iptables-save
        iptables-save > /etc/iptables/rules.v4 2>/dev/null
    }

    msg_ok "iptables NAT rules configured for interface ${interface}"
}

# ----------------------------------------------------------------------------
# _create_client_template() - Build a base .ovpn client template
# ----------------------------------------------------------------------------
_create_client_template() {
    local ip_addr
    ip_addr=$(get_public_ip)
    [[ -z "${ip_addr}" ]] && ip_addr="YOUR_SERVER_IP"

    cat > "${OVPN_TEMPLATE}" << EOF
# BraanX OpenVPN Client Profile
# Generated by BraanX VPN Auto-Installer

client
dev tun
proto tcp
remote ${ip_addr} ${OVPN_TCP_PORT}
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3

<ca>
EOF

    # Append CA cert
    if [[ -f "${OVPN_PKI}/pki/ca.crt" ]]; then
        cat "${OVPN_PKI}/pki/ca.crt" >> "${OVPN_TEMPLATE}"
    fi

    echo "</ca>" >> "${OVPN_TEMPLATE}"
    echo "" >> "${OVPN_TEMPLATE}"
    echo "<tls-crypt>" >> "${OVPN_TEMPLATE}"

    # Append tls-crypt key
    if [[ -f "${OVPN_PKI}/pki/tls-crypt.key" ]]; then
        cat "${OVPN_PKI}/pki/tls-crypt.key" >> "${OVPN_TEMPLATE}"
    fi

    echo "</tls-crypt>" >> "${OVPN_TEMPLATE}"
    echo "# KEY and CERT will be inserted here per-user" >> "${OVPN_TEMPLATE}"

    msg_ok "Client template created at ${OVPN_TEMPLATE}"
}

# ----------------------------------------------------------------------------
# add_openvpn_account() - Create a client certificate and .ovpn profile
#   $1 = username
#   $2 = days (validity)
#   $3 = protocol (tcp/udp/both) [optional, default both]
# ----------------------------------------------------------------------------
add_openvpn_account() {
    local username="${1}"
    local days="${2}"
    local protocol="${3:-both}"

    if [[ -z "${username}" || -z "${days}" ]]; then
        msg_err "Usage: add_openvpn_account <username> <days> [tcp|udp|both]"
        return 1
    fi

    local cert_days=${days}
    [[ ${cert_days} -gt 825 ]] && cert_days=825  # max ~2.25 years for easy-rsa

    msg_info "Generating certificate for '${username}' (${cert_days} days)..."

    cd "${OVPN_PKI}" || return 1

    # Generate client cert
    ./easyrsa --batch --req-cn "${username}" gen-req "${username}" nopass
    if [[ $? -ne 0 ]]; then
        msg_err "Failed to generate certificate request for '${username}'"
        cd - >/dev/null
        return 1
    fi

    # Sign with custom validity
    local expire_in
    expire_in=$((cert_days * 86400))
    ./easyrsa --batch --days="${cert_days}" sign-req client "${username}"
    if [[ $? -ne 0 ]]; then
        msg_err "Failed to sign certificate for '${username}'"
        cd - >/dev/null
        return 1
    fi

    # Get certificate fingerprint
    local fingerprint
    fingerprint=$(openssl x509 -in "pki/issued/${username}.crt" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    cd - >/dev/null

    # Build .ovpn profile
    _build_client_profile "${username}" "${protocol}"

    # Calculate expiry date
    local expires_at
    expires_at=$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d 2>/dev/null)
    [[ -z "${expires_at}" ]] && expires_at=$(date +%Y-%m-%d)

    # Insert into database
    db_query "INSERT INTO openvpn_users (username, cert_fingerprint, days, expires_at, protocol)
              VALUES ('${username}', '${fingerprint}', ${days}, '${expires_at}', '${protocol}')"

    # Show result
    draw_header "OPENVPN ACCOUNT CREATED"
    draw_table \
        "Username" "${username}" \
        "Valid Days" "${days}" \
        "Expires" "${expires_at}" \
        "Protocol" "${protocol}" \
        "TCP Port" "${OVPN_TCP_PORT}" \
        "UDP Port" "${OVPN_UDP_PORT}" \
        "Profile" "${OVPN_DIR}/profiles/${username}.ovpn"

    msg_ok "OpenVPN account '${username}' created"
}

# ----------------------------------------------------------------------------
# _build_client_profile() - Generate .ovpn profile for a specific user
#   $1 = username
#   $2 = protocol (tcp/udp/both)
# ----------------------------------------------------------------------------
_build_client_profile() {
    local username="${1}"
    local protocol="${2}"
    local profile="${OVPN_DIR}/profiles/${username}.ovpn"
    local ip_addr
    ip_addr=$(get_public_ip)

    cat > "${profile}" << EOF
# BraanX OpenVPN Profile - ${username}
client
dev tun
EOF

    case "${protocol}" in
        tcp)
            echo "proto tcp" >> "${profile}"
            echo "remote ${ip_addr} ${OVPN_TCP_PORT}" >> "${profile}"
            ;;
        udp)
            echo "proto udp" >> "${profile}"
            echo "remote ${ip_addr} ${OVPN_UDP_PORT}" >> "${profile}"
            ;;
        both)
            echo "proto tcp" >> "${profile}"
            echo "remote ${ip_addr} ${OVPN_TCP_PORT}" >> "${profile}"
            echo "" >> "${profile}"
            echo "# For UDP mode, change proto to udp and port to ${OVPN_UDP_PORT}" >> "${profile}"
            ;;
    esac

    cat >> "${profile}" << EOF
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA512
verb 3
key-direction 1

<ca>
EOF
    cat "${OVPN_PKI}/pki/ca.crt" >> "${profile}"
    cat >> "${profile}" << EOF
</ca>
<cert>
EOF
    cat "${OVPN_PKI}/pki/issued/${username}.crt" >> "${profile}"
    cat >> "${profile}" << EOF
</cert>
<key>
EOF
    cat "${OVPN_PKI}/pki/private/${username}.key" >> "${profile}"
    cat >> "${profile}" << EOF
</key>
<tls-crypt>
EOF
    cat "${OVPN_PKI}/pki/tls-crypt.key" >> "${profile}"
    cat >> "${profile}" << EOF
</tls-crypt>
EOF

    chmod 600 "${profile}"
    msg_ok "Profile saved: ${profile}"
}

# ----------------------------------------------------------------------------
# delete_openvpn_account() - Revoke a client certificate and remove account
#   $1 = username
# ----------------------------------------------------------------------------
delete_openvpn_account() {
    local username="${1}"

    if [[ -z "${username}" ]]; then
        msg_err "Usage: delete_openvpn_account <username>"
        return 1
    fi

    msg_info "Revoking certificate for '${username}'..."

    cd "${OVPN_PKI}" || return 1

    # Revoke certificate
    ./easyrsa --batch revoke "${username}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        # Generate new CRL
        ./easyrsa --batch gen-crl 2>/dev/null
        msg_ok "Certificate revoked"
    else
        msg_warn "Could not revoke certificate (may already be revoked)"
    fi

    cd - >/dev/null

    # Remove profile
    rm -f "${OVPN_DIR}/profiles/${username}.ovpn"

    # Remove cert files
    rm -f "${OVPN_PKI}/pki/issued/${username}.crt"
    rm -f "${OVPN_PKI}/pki/private/${username}.key"
    rm -f "${OVPN_PKI}/pki/reqs/${username}.req"

    # Deactivate in database
    db_query "UPDATE openvpn_users SET active=0 WHERE username='${username}'"

    # Copy CRL to OpenVPN directory if it exists
    cp -f "${OVPN_PKI}/pki/crl.pem" /etc/openvpn/server/ 2>/dev/null

    msg_ok "OpenVPN account '${username}' deleted"
}

# ----------------------------------------------------------------------------
# openvpn_restart() - Restart OpenVPN services
# ----------------------------------------------------------------------------
openvpn_restart() {
    msg_info "Restarting OpenVPN services..."
    systemctl restart "openvpn-server@server-tcp-${OVPN_TCP_PORT}" 2>/dev/null
    systemctl restart "openvpn-server@server-udp-${OVPN_UDP_PORT}" 2>/dev/null
    msg_ok "OpenVPN services restarted"
}

# ----------------------------------------------------------------------------
# openvpn_status() - Show OpenVPN service status and active connections
# ----------------------------------------------------------------------------
openvpn_status() {
    draw_header "OPENVPN SERVICE STATUS"

    # TCP status
    local tcp_status
    tcp_status=$(systemctl is-active "openvpn-server@server-tcp-${OVPN_TCP_PORT}" 2>/dev/null)
    msg_info "OpenVPN TCP (port ${OVPN_TCP_PORT}): ${tcp_status}"

    # UDP status
    local udp_status
    udp_status=$(systemctl is-active "openvpn-server@server-udp-${OVPN_UDP_PORT}" 2>/dev/null)
    msg_info "OpenVPN UDP (port ${OVPN_UDP_PORT}): ${udp_status}"

    # Active connections
    echo ""
    msg_info "Active connections:"
    if [[ -f /var/log/openvpn/openvpn-status-tcp.log ]]; then
        echo "  TCP connections:"
        rg -c "CLIENT_LIST" /var/log/openvpn/openvpn-status-tcp.log 2>/dev/null && \
            rg "CLIENT_LIST" /var/log/openvpn/openvpn-status-tcp.log 2>/dev/null | while read line; do
                echo "    ${line}"
            done
    fi
    if [[ -f /var/log/openvpn/openvpn-status-udp.log ]]; then
        echo "  UDP connections:"
        rg -c "CLIENT_LIST" /var/log/openvpn/openvpn-status-udp.log 2>/dev/null && \
            rg "CLIENT_LIST" /var/log/openvpn/openvpn-status-udp.log 2>/dev/null | while read line; do
                echo "    ${line}"
            done
    fi

    # Account summary
    local total
    total=$(db_query "SELECT COUNT(*) FROM openvpn_users WHERE active=1" 2>/dev/null)
    msg_info "Total active accounts: ${total:-0}"
    echo ""
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_openvpn
export -f add_openvpn_account
export -f delete_openvpn_account
export -f openvpn_restart
export -f openvpn_status
export -f _init_pki
export -f _enable_ip_forwarding
export -f _configure_iptables
export -f _create_client_template
export -f _build_client_profile
