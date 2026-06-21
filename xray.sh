#!/bin/bash
# ============================================================================
# BraanX - XRay Core Installer and Configurator
# ============================================================================
# Manages the XRay proxy core: installation, configuration, user accounts,
# and all supported inbound protocols (VLESS, VMess, Trojan) over
# WebSocket, gRPC, HTTPUpgrade, Reality, and Non-TLS transports.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# Database: /etc/braanx/db/braanx.db
# XRay binary: /usr/local/bin/xray
# XRay config: /usr/local/etc/xray/config.json
# ============================================================================
source /etc/braanx/lib/functions.sh

XRAY_BIN="/usr/local/bin/xray"
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONF="${XRAY_DIR}/config.json"
XRAY_SERVICE="/etc/systemd/system/xray.service"
XRAY_LOG_DIR="/var/log/xray"
SSL_DIR="/etc/braanx/ssl"
BRAANX_CONF="/etc/braanx/braanx.conf"
BRAANX_DB="/etc/braanx/db/braanx.db"

# Internal port assignments for each inbound
# TLS inbounds (proxied via nginx on 443)
PORT_VLESS_WS=2001
PORT_VLESS_GRPC=2002
PORT_VLESS_HUPG=2003
PORT_VMESS_WS=2004
PORT_VMESS_GRPC=2005
PORT_VMESS_HUPG=2006
PORT_TROJAN_WS=2007
PORT_TROJAN_GRPC=2008
PORT_TROJAN_HUPG=2009
# Reality (direct, port 8443)
PORT_VLESS_REALITY=8443
# Non-TLS (proxied via nginx on 80)
PORT_VLESS_NTLS=2011
PORT_VMESS_NTLS=2012
# Fallback destination (nginx fake page)
PORT_FALLBACK=1010

# ----------------------------------------------------------------------------
# install_xray() - Download, install, and configure the XRay core
# ----------------------------------------------------------------------------
install_xray() {
    msg_info "Starting XRay core installation..."

    # --- Detect OS and architecture ---
    local arch
    arch=$(uname -m)
    case "${arch}" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64-v8a" ;;
        armv7l)  arch="arm32-v7a" ;;
        armv6l)  arch="arm32-v6a" ;;
        s390x)   arch="s390x" ;;
        *)
            msg_err "Unsupported architecture: ${arch}"
            return 1
            ;;
    esac
    msg_info "Detected architecture: ${arch}"

    # --- Download latest XRay release ---
    local xray_version
    local download_url
    xray_version=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null)
    if [[ -z "${xray_version}" ]]; then
        msg_err "Failed to determine latest XRay version"
        return 1
    fi
    msg_info "Latest XRay version: ${xray_version}"

    local tmpdir
    tmpdir=$(mktemp -d)
    download_url="https://github.com/XTLS/Xray-core/releases/download/${xray_version}/Xray-linux-${arch}.zip"

    msg_info "Downloading XRay..."
    if ! curl -sLo "${tmpdir}/xray.zip" "${download_url}"; then
        msg_err "Failed to download XRay"
        rm -rf "${tmpdir}"
        return 1
    fi

    # --- Extract and install ---
    msg_info "Extracting XRay archive..."
    unzip -oq "${tmpdir}/xray.zip" -d "${tmpdir}/xray"
    cp -f "${tmpdir}/xray/xray" "${XRAY_BIN}"
    chmod +x "${XRAY_BIN}"
    rm -rf "${tmpdir}"

    # Verify binary
    if [[ ! -x "${XRAY_BIN}" ]]; then
        msg_err "XRay binary installation failed"
        return 1
    fi
    msg_ok "XRay binary installed at ${XRAY_BIN}"

    # --- Create xray user and group ---
    if ! id -u xray &>/dev/null; then
        groupadd -r xray 2>/dev/null
        useradd -r -g xray -s /usr/sbin/nologin -d "${XRAY_DIR}" xray 2>/dev/null
        msg_ok "Created xray user and group"
    else
        msg_info "User 'xray' already exists"
    fi

    # --- Create directories ---
    mkdir -p "${XRAY_DIR}" "${XRAY_LOG_DIR}"
    chown -R xray:xray "${XRAY_DIR}" "${XRAY_LOG_DIR}"

    # --- Generate UUID and x25519 keys ---
    local main_uuid
    local x25519_pub
    local x25519_priv

    main_uuid=$(${XRAY_BIN} uuid)
    msg_info "Main UUID: ${main_uuid}"

    local key_output
    key_output=$(${XRAY_BIN} x25519)
    x25519_pub=$(echo "${key_output}" | head -1 | awk '{print $3}')
    x25519_priv=$(echo "${key_output}" | tail -1 | awk '{print $3}')
    msg_info "x25519 Public Key: ${x25519_pub}"

    # Save keys to config
    config_set "XRAY_UUID" "${main_uuid}"
    config_set "XRAY_X25519_PUB" "${x25519_pub}"
    config_set "XRAY_X25519_PRIV" "${x25519_priv}"
    config_set "XRAY_VERSION" "${xray_version}"

    # --- Create systemd service ---
    msg_info "Creating systemd service..."
    cat > "${XRAY_SERVICE}" << 'SVEOF'
[Unit]
Description=XRay Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN

[Install]
WantedBy=multi-user.target
SVEOF

    systemctl daemon-reload
    msg_ok "Systemd service created"

    # --- Build XRay config ---
    configure_xray

    # --- Enable and start ---
    systemctl enable xray &>/dev/null
    xray_restart

    # --- Initialize database table ---
    db_query "CREATE TABLE IF NOT EXISTS xray_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        uuid TEXT NOT NULL,
        protocol TEXT NOT NULL,
        transport TEXT NOT NULL,
        days INTEGER NOT NULL,
        created_at TEXT DEFAULT (datetime('now','localtime')),
        expires_at TEXT,
        active INTEGER DEFAULT 1,
        traffic_up BIGINT DEFAULT 0,
        traffic_down BIGINT DEFAULT 0
    )"

    msg_ok "XRay core installation completed successfully"
}

# ----------------------------------------------------------------------------
# configure_xray() - Build the complete XRay config.json with all inbounds
# ----------------------------------------------------------------------------
configure_xray() {
    msg_info "Building XRay configuration..."

    local domain
    local ip_addr
    local main_uuid
    local x25519_pub
    local x25519_priv
    local reality_dest
    local reality_server_names

    domain=$(config_get "DOMAIN")
    ip_addr=$(config_get "SERVER_IP")
    [[ -z "${ip_addr}" ]] && ip_addr=$(get_public_ip)
    [[ -z "${ip_addr}" ]] && ip_addr="0.0.0.0"
    main_uuid=$(config_get "XRAY_UUID")
    x25519_pub=$(config_get "XRAY_X25519_PUB")
    x25519_priv=$(config_get "XRAY_X25519_PRIV")

    # Reality short ID and dest
    reality_dest="1.1.1.1:443"
    reality_server_names="www.microsoft.com,www.yahoo.com"

    # SSL cert paths
    local ssl_cert="${SSL_DIR}/fullchain.pem"
    local ssl_key="${SSL_DIR}/privkey.pem"

    # Build config using python3 for reliable JSON generation
    python3 << PYEOF
import json, os, sys

domain = """${domain}"""
ip_addr = """${ip_addr}"""
main_uuid = """${main_uuid}"""
x25519_pub = """${x25519_pub}"""
x25519_priv = """${x25519_priv}"""
reality_dest = """${reality_dest}"""
reality_server_names = "${reality_server_names}"
ssl_cert = """${ssl_cert}"""
ssl_key = """${ssl_key}"""

# Check if TLS certs exist
tls_available = os.path.isfile(ssl_cert) and os.path.isfile(ssl_key)

FALLBACK_PORT = ${PORT_FALLBACK}

# Common TLS stream settings
def tls_stream(cert_path, key_path):
    return {
        "security": "tls",
        "tlsSettings": {
            "serverName": domain if domain else ip_addr,
            "certificates": [{"certFile": cert_path, "keyFile": key_path}],
            "minVersion": "1.2",
            "cipherSuites": [
                "TLS_AES_128_GCM_SHA256",
                "TLS_AES_256_GCM_SHA384",
                "TLS_CHACHA20_POLY1305_SHA256"
            ],
            "alpn": ["h2", "http/1.1"],
            "rejectUnknownSni": False
        }
    }

# Common Reality stream settings
def reality_stream():
    return {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
            "showDests": False,
            "dest": reality_dest,
            "serverNames": reality_server_names.split(","),
            "privateKey": x25519_priv,
            "shortIds": ["", "abcd1234", "0123456789ab"]
        }
    }

# Inbound builder helpers
def make_inbound(port, tag, protocol, stream, clients=None, decryption="none", extra_settings=None):
    inbound = {
        "listen": "127.0.0.1",
        "port": port,
        "tag": tag,
        "protocol": protocol,
        "settings": {
            "clients": clients or [],
            "decryption": decryption,
            "fallbacks": [{"dest": FALLBACK_PORT}]
        },
        "streamSettings": stream
    }
    if extra_settings:
        inbound["settings"].update(extra_settings)
    return inbound

inbounds = []

# === VLESS WebSocket (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VLESS_WS}, "vless-ws", "vless",
    {"network": "ws", "wsSettings": {"path": "/vless-ws"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx"}]
))

# === VLESS gRPC (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VLESS_GRPC}, "vless-grpc", "vless",
    {"network": "grpc", "grpcSettings": {"serviceName": "vless-grpc", "multiMode": True}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx"}]
))

# === VLESS HTTPUpgrade (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VLESS_HUPG}, "vless-hupg", "vless",
    {"network": "httpupgrade", "httpUpgradeSettings": {"path": "/vless-hupg"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx"}]
))

# === VMess WebSocket (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VMESS_WS}, "vmess-ws", "vmess",
    {"network": "ws", "wsSettings": {"path": "/vmess-ws"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx", "alterId": 0}],
    decryption="auto"
))

# === VMess gRPC (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VMESS_GRPC}, "vmess-grpc", "vmess",
    {"network": "grpc", "grpcSettings": {"serviceName": "vmess-grpc", "multiMode": True}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx", "alterId": 0}],
    decryption="auto"
))

# === VMess HTTPUpgrade (TLS) ===
inbounds.append(make_inbound(
    ${PORT_VMESS_HUPG}, "vmess-hupg", "vmess",
    {"network": "httpupgrade", "httpUpgradeSettings": {"path": "/vmess-hupg"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx", "alterId": 0}],
    decryption="auto"
))

# === Trojan WebSocket (TLS) ===
inbounds.append(make_inbound(
    ${PORT_TROJAN_WS}, "trojan-ws", "trojan",
    {"network": "ws", "wsSettings": {"path": "/trojan-ws"}, "security": "none"},
    clients=[{"password": main_uuid, "email": "main@braanx"}],
    decryption="none"
))

# === Trojan gRPC (TLS) ===
inbounds.append(make_inbound(
    ${PORT_TROJAN_GRPC}, "trojan-grpc", "trojan",
    {"network": "grpc", "grpcSettings": {"serviceName": "trojan-grpc", "multiMode": True}, "security": "none"},
    clients=[{"password": main_uuid, "email": "main@braanx"}],
    decryption="none"
))

# === Trojan HTTPUpgrade (TLS) ===
inbounds.append(make_inbound(
    ${PORT_TROJAN_HUPG}, "trojan-hupg", "trojan",
    {"network": "httpupgrade", "httpUpgradeSettings": {"path": "/trojan-hupg"}, "security": "none"},
    clients=[{"password": main_uuid, "email": "main@braanx"}],
    decryption="none"
))

# === VLESS Reality (direct on 8443) ===
inbounds.append({
    "listen": "0.0.0.0",
    "port": ${PORT_VLESS_REALITY},
    "tag": "vless-reality",
    "protocol": "vless",
    "settings": {
        "clients": [
            {
                "id": main_uuid,
                "email": "main@braanx",
                "flow": "xtls-rprx-vision"
            }
        ],
        "decryption": "none",
        "fallbacks": []
    },
    "streamSettings": reality_stream()
})

# === VLESS Non-TLS (port 80) ===
inbounds.append(make_inbound(
    ${PORT_VLESS_NTLS}, "vless-ntls", "vless",
    {"network": "ws", "wsSettings": {"path": "/vless-ntls"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx"}]
))

# === VMess Non-TLS (port 80) ===
inbounds.append(make_inbound(
    ${PORT_VMESS_NTLS}, "vmess-ntls", "vmess",
    {"network": "ws", "wsSettings": {"path": "/vmess-ntls"}, "security": "none"},
    clients=[{"id": main_uuid, "email": "main@braanx", "alterId": 0}],
    decryption="auto"
))

# Routing rules
routing = {
    "rules": [
        {
            "type": "field",
            "inboundTag": ["vless-reality"],
            "outboundTag": "direct"
        },
        {
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "block"
        },
        {
            "type": "field",
            "domain": ["geosite:category-ads-all"],
            "outboundTag": "block"
        }
    ]
}

config = {
    "log": {
        "loglevel": "warning",
        "access": "${XRAY_LOG_DIR}/access.log",
        "error": "${XRAY_LOG_DIR}/error.log"
    },
    "api": {
        "services": ["HandlerService", "StatsService"],
        "tag": "api"
    },
    "stats": {},
    "policy": {
        "levels": {
            "0": {
                "handshake": 4,
                "connIdle": 300,
                "uplinkOnly": 2,
                "downlinkOnly": 5
            }
        },
        "system": {
            "statsInboundUplink": True,
            "statsInboundDownlink": True,
            "statsOutboundUplink": True,
            "statsOutboundDownlink": True
        }
    },
    "inbounds": inbounds,
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"}
    ],
    "routing": routing
}

os.makedirs(os.path.dirname("${XRAY_CONF}"), exist_ok=True)
with open("${XRAY_CONF}", "w") as f:
    json.dump(config, f, indent=2)

print("XRay config written successfully")
PYEOF

    chown xray:xray "${XRAY_CONF}"
    msg_ok "XRay configuration built"
}

# ----------------------------------------------------------------------------
# add_xray_account() - Create a new XRay user for a given protocol
#   $1 = username
#   $2 = protocol  (vless / vmess / trojan)
#   $3 = days      (account validity)
#   $4 = transport (ws / grpc / hupg / reality / ntls) [optional, default ws]
# ----------------------------------------------------------------------------
add_xray_account() {
    local username="${1}"
    local protocol="${2}"
    local days="${3}"
    local transport="${4:-ws}"

    if [[ -z "${username}" || -z "${protocol}" || -z "${days}" ]]; then
        msg_err "Usage: add_xray_account <username> <protocol> <days> [transport]"
        return 1
    fi

    # Validate protocol
    case "${protocol}" in
        vless|vmess|trojan) ;;
        *) msg_err "Invalid protocol: ${protocol}. Use vless, vmess, or trojan."; return 1 ;;
    esac

    # Check for duplicates
    local exists
    exists=$(db_query "SELECT username FROM xray_users WHERE username='${username}' AND protocol='${protocol}' AND active=1")
    if [[ -n "${exists}" ]]; then
        msg_err "User '${username}' already exists for protocol ${protocol}"
        return 1
    fi

    # Generate UUID
    local user_uuid
    user_uuid=$(${XRAY_BIN} uuid)

    # Map transport to tag and port
    local tag port
    case "${protocol}-${transport}" in
        vless-ws)       tag="vless-ws";       port=${PORT_VLESS_WS} ;;
        vless-grpc)     tag="vless-grpc";     port=${PORT_VLESS_GRPC} ;;
        vless-hupg)     tag="vless-hupg";     port=${PORT_VLESS_HUPG} ;;
        vless-reality)  tag="vless-reality";  port=${PORT_VLESS_REALITY} ;;
        vless-ntls)     tag="vless-ntls";     port=${PORT_VLESS_NTLS} ;;
        vmess-ws)       tag="vmess-ws";       port=${PORT_VMESS_WS} ;;
        vmess-grpc)     tag="vmess-grpc";     port=${PORT_VMESS_GRPC} ;;
        vmess-hupg)     tag="vmess-hupg";     port=${PORT_VMESS_HUPG} ;;
        vmess-ntls)     tag="vmess-ntls";     port=${PORT_VMESS_NTLS} ;;
        trojan-ws)      tag="trojan-ws";      port=${PORT_TROJAN_WS} ;;
        trojan-grpc)    tag="trojan-grpc";    port=${PORT_TROJAN_GRPC} ;;
        trojan-hupg)    tag="trojan-hupg";    port=${PORT_TROJAN_HUPG} ;;
        *)
            msg_err "Unsupported transport '${transport}' for protocol '${protocol}'"
            return 1
            ;;
    esac

    # Add user to inbound config
    python3 << PYEOF
import json, sys

username = "${username}"
user_uuid = "${user_uuid}"
tag = "${tag}"
protocol = "${protocol}"
xray_conf = "${XRAY_CONF}"

with open(xray_conf, "r") as f:
    config = json.load(f)

for inbound in config.get("inbounds", []):
    if inbound.get("tag") == tag:
        clients = inbound["settings"].get("clients", [])
        # Build the client object based on protocol
        if protocol == "vless":
            client = {"id": user_uuid, "email": username + "@braanx"}
            if tag == "vless-reality":
                client["flow"] = "xtls-rprx-vision"
        elif protocol == "vmess":
            client = {"id": user_uuid, "email": username + "@braanx", "alterId": 0}
        elif protocol == "trojan":
            client = {"password": user_uuid, "email": username + "@braanx"}
        else:
            sys.exit(1)
        clients.append(client)
        inbound["settings"]["clients"] = clients
        break
else:
    print("ERROR: Tag not found: " + tag, file=sys.stderr)
    sys.exit(1)

with open(xray_conf, "w") as f:
    json.dump(config, f, indent=2)

print("User added to inbound: " + tag)
PYEOF

    if [[ $? -ne 0 ]]; then
        msg_err "Failed to add user to XRay configuration"
        return 1
    fi

    chown xray:xray "${XRAY_CONF}"

    # Calculate expiry date
    local expires_at
    expires_at=$(date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d 2>/dev/null)
    [[ -z "${expires_at}" ]] && expires_at=$(date +%Y-%m-%d)

    # Insert into database
    db_query "INSERT INTO xray_users (username, uuid, protocol, transport, days, expires_at)
              VALUES ('${username}', '${user_uuid}', '${protocol}', '${transport}', ${days}, '${expires_at}')"

    # Restart XRay to pick up new config
    xray_restart

    # Display connection info
    _show_connection_info "${username}" "${user_uuid}" "${protocol}" "${transport}" "${tag}" "${days}" "${expires_at}"

    msg_ok "User '${username}' added successfully"
}

# ----------------------------------------------------------------------------
# _show_connection_info() - Display connection details for a newly created user
# ----------------------------------------------------------------------------
_show_connection_info() {
    local username="${1}"
    local uuid="${2}"
    local protocol="${3}"
    local transport="${4}"
    local tag="${5}"
    local days="${6}"
    local expires_at="${7}"

    local domain
    local ip_addr
    local server_addr

    domain=$(config_get "DOMAIN")
    ip_addr=$(get_public_ip)
    server_addr="${domain:-${ip_addr}}"

    # Determine public port based on transport
    local pub_port
    local path=""
    local sni=""
    local security="none"
    local net_type="ws"

    case "${transport}" in
        ws)   pub_port=443; path="/$(echo ${tag} | sed 's/-ws//')-ws"; net_type="ws" ;;
        grpc) pub_port=443; net_type="grpc" ;;
        hupg) pub_port=443; path="/$(echo ${tag} | sed 's/-hupg//')-hupg"; net_type="httpupgrade" ;;
        reality) pub_port=8443; security="reality"; net_type="tcp" ;;
        ntls)  pub_port=80; path="/$(echo ${tag} | sed 's/-ntls//')-ntls"; net_type="ws" ;;
    esac

    # For TLS transports, set security
    if [[ "${pub_port}" == "443" ]]; then
        security="tls"
        sni="sni=${server_addr}"
    fi

    # Build share link
    local link=""
    local link_fmt=""

    case "${protocol}" in
        vless)
            if [[ "${transport}" == "reality" ]]; then
                link="vless://${uuid}@${ip_addr}:${pub_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$(config_get XRAY_X25519_PUB)&sid=abcd1234&type=tcp#${username}-${transport}"
            elif [[ "${transport}" == "ws" || "${transport}" == "ntls" ]]; then
                link="vless://${uuid}@${server_addr}:${pub_port}?encryption=none&security=${security}&${sni}&type=${net_type}&path=${path}&host=${server_addr}#${username}-${transport}"
            elif [[ "${transport}" == "grpc" ]]; then
                link="vless://${uuid}@${server_addr}:${pub_port}?encryption=none&security=${security}&${sni}&type=grpc&serviceName=${protocol}-grpc&mode=multi#${username}-${transport}"
            elif [[ "${transport}" == "hupg" ]]; then
                link="vless://${uuid}@${server_addr}:${pub_port}?encryption=none&security=${security}&${sni}&type=httpupgrade&path=${path}&host=${server_addr}#${username}-${transport}"
            fi
            ;;
        vmess)
            if [[ "${transport}" == "ws" || "${transport}" == "ntls" ]]; then
                link="vmess://${uuid}@${server_addr}:${pub_port}?encryption=auto&security=${security}&${sni}&type=${net_type}&path=${path}&host=${server_addr}#${username}-${transport}"
            elif [[ "${transport}" == "grpc" ]]; then
                link="vmess://${uuid}@${server_addr}:${pub_port}?encryption=auto&security=${security}&${sni}&type=grpc&serviceName=${protocol}-grpc&mode=multi#${username}-${transport}"
            elif [[ "${transport}" == "hupg" ]]; then
                link="vmess://${uuid}@${server_addr}:${pub_port}?encryption=auto&security=${security}&${sni}&type=httpupgrade&path=${path}&host=${server_addr}#${username}-${transport}"
            fi
            ;;
        trojan)
            if [[ "${transport}" == "ws" ]]; then
                link="trojan://${uuid}@${server_addr}:${pub_port}?security=${security}&${sni}&type=${net_type}&path=${path}&host=${server_addr}#${username}-${transport}"
            elif [[ "${transport}" == "grpc" ]]; then
                link="trojan://${uuid}@${server_addr}:${pub_port}?security=${security}&${sni}&type=grpc&serviceName=${protocol}-grpc&mode=multi#${username}-${transport}"
            elif [[ "${transport}" == "hupg" ]]; then
                link="trojan://${uuid}@${server_addr}:${pub_port}?security=${security}&${sni}&type=httpupgrade&path=${path}&host=${server_addr}#${username}-${transport}"
            fi
            ;;
    esac

    echo ""
    draw_header "XRAY ACCOUNT CREATED"
    draw_table \
        "Username" "${username}" \
        "Protocol" "$(echo ${protocol} | tr '[:lower:]' '[:upper:]')" \
        "Transport" "$(echo ${transport} | tr '[:lower:]' '[:upper:]')" \
        "UUID" "${uuid}" \
        "Server" "${server_addr}" \
        "Port" "${pub_port}" \
        "Valid Days" "${days}" \
        "Expires" "${expires_at}"
    echo ""
    if [[ -n "${link}" ]]; then
        msg_info "Connection Link:"
        echo "${link}"
        echo ""
    fi
}

# ----------------------------------------------------------------------------
# delete_xray_account() - Remove a user from XRay and database
#   $1 = username
#   $2 = protocol (optional - removes all if omitted)
# ----------------------------------------------------------------------------
delete_xray_account() {
    local username="${1}"
    local protocol="${2}"

    if [[ -z "${username}" ]]; then
        msg_err "Usage: delete_xray_account <username> [protocol]"
        return 1
    fi

    # Get user info from database
    local user_info
    if [[ -n "${protocol}" ]]; then
        user_info=$(db_query "SELECT uuid, protocol FROM xray_users WHERE username='${username}' AND protocol='${protocol}' AND active=1")
    else
        user_info=$(db_query "SELECT uuid, protocol FROM xray_users WHERE username='${username}' AND active=1")
    fi

    if [[ -z "${user_info}" ]]; then
        msg_warn "User '${username}' not found"
        return 1
    fi

    # Remove user from XRay config inbounds
    python3 << PYEOF
import json, sys

username = "${username}"
protocol_filter = "${protocol}"
xray_conf = "${XRAY_CONF}"

with open(xray_conf, "r") as f:
    config = json.load(f)

removed_count = 0
for inbound in config.get("inbounds", []):
    tag = inbound.get("tag", "")
    clients = inbound["settings"].get("clients", [])
    original_count = len(clients)

    # Filter out clients matching the username's email suffix
    clients = [c for c in clients if not c.get("email", "").startswith(username + "@braanx")]

    removed = original_count - len(clients)
    removed_count += removed
    inbound["settings"]["clients"] = clients

with open(xray_conf, "w") as f:
    json.dump(config, f, indent=2)

print(f"Removed {removed_count} client entry(ies) for user: {username}")
PYEOF

    chown xray:xray "${XRAY_CONF}"

    # Deactivate in database
    if [[ -n "${protocol}" ]]; then
        db_query "UPDATE xray_users SET active=0 WHERE username='${username}' AND protocol='${protocol}'"
    else
        db_query "UPDATE xray_users SET active=0 WHERE username='${username}'"
    fi

    xray_restart
    msg_ok "User '${username}' deleted"
}

# ----------------------------------------------------------------------------
# list_xray_accounts() - Show all active XRay users
# ----------------------------------------------------------------------------
list_xray_accounts() {
    msg_info "Active XRay Accounts:"
    local accounts
    accounts=$(db_query "SELECT username, protocol, transport, uuid, days, expires_at FROM xray_users WHERE active=1 ORDER BY id")

    if [[ -z "${accounts}" ]]; then
        msg_warn "No active accounts found"
        return 0
    fi

    echo ""
    printf "${BOLD}%-15s %-10s %-8s %-40s %-8s %-12s${RST}\n" "USERNAME" "PROTOCOL" "TRANSPORT" "UUID" "DAYS" "EXPIRES"
    printf "${Y}%-s${RST}\n" "$(printf '%.0s-' {1..100})"
    echo "${accounts}" | while IFS='|' read -r user proto transport uuid days exp; do
        printf "%-15s %-10s %-8s %-40s %-8s %-12s\n" "${user}" "${proto}" "${transport}" "${uuid}" "${days}" "${exp}"
    done
    echo ""
}

# ----------------------------------------------------------------------------
# xray_restart() - Restart the XRay systemd service
# ----------------------------------------------------------------------------
xray_restart() {
    msg_info "Restarting XRay service..."
    systemctl stop xray &>/dev/null
    sleep 1
    systemctl start xray
    if [[ $? -eq 0 ]]; then
        msg_ok "XRay service restarted"
    else
        msg_err "XRay service failed to start"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# xray_status() - Show XRay service status and runtime info
# ----------------------------------------------------------------------------
xray_status() {
    local version
    version=$(${XRAY_BIN} version 2>/dev/null | head -1 | awk '{print $2}')
    [[ -z "${version}" ]] && version="not installed"

    local running
    running=$(systemctl is-active xray 2>/dev/null)

    local uptime
    uptime=$(systemctl show xray --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2)

    local main_uuid
    main_uuid=$(config_get "XRAY_UUID")

    local x25519_pub
    x25519_pub=$(config_get "XRAY_X25519_PUB")

    draw_header "XRAY SERVICE STATUS"
    draw_table \
        "Version" "${version}" \
        "Status" "${running}" \
        "Since" "${uptime:-unknown}" \
        "Main UUID" "${main_uuid:-none}" \
        "x25519 Pub" "${x25519_pub:-none}" \
        "Config" "${XRAY_CONF}" \
        "Binary" "${XRAY_BIN}"

    # Show active accounts count
    local count
    count=$(db_query "SELECT COUNT(*) FROM xray_users WHERE active=1" 2>/dev/null)
    echo ""
    msg_info "Active accounts: ${count:-0}"

    # Show listening ports
    echo ""
    msg_info "XRay internal ports:"
    ss -tlnp 2>/dev/null | grep xray | while read line; do
        echo "  ${line}"
    done
    echo ""
}

# ----------------------------------------------------------------------------
# xray_update() - Update XRay to the latest release
# ----------------------------------------------------------------------------
xray_update() {
    msg_info "Checking for XRay updates..."
    local current_version
    current_version=$(${XRAY_BIN} version 2>/dev/null | head -1 | awk '{print $2}')
    msg_info "Current version: ${current_version}"

    local latest_version
    latest_version=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null)

    if [[ "${current_version}" == "${latest_version}" ]]; then
        msg_ok "XRay is already up to date"
        return 0
    fi

    msg_info "Updating to ${latest_version}..."
    install_xray
    msg_ok "XRay updated successfully"
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_xray
export -f configure_xray
export -f add_xray_account
export -f delete_xray_account
export -f list_xray_accounts
export -f xray_restart
export -f xray_status
export -f xray_update
export -f _show_connection_info
