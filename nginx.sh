#!/bin/bash
# ============================================================================
# BraanX - Nginx Reverse Proxy Installer
# ============================================================================
# Configures Nginx as a reverse proxy for WebSocket and gRPC VPN tunnels.
# Handles TLS termination on port 443 and non-TLS on port 80.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# ============================================================================
source /etc/braanx/lib/functions.sh

NGINX_CONF="/etc/nginx/nginx.conf"
BRAANX_NGINX="/etc/nginx/conf.d/braanx.conf"
SSL_DIR="/etc/braanx/ssl"
BRAANX_CONF="/etc/braanx/braanx.conf"
SSL_CERT="${SSL_DIR}/fullchain.pem"
SSL_KEY="${SSL_DIR}/privkey.pem"
FAKE_PAGE="/var/www/braanx/index.html"

# XRay internal ports
PORT_VLESS_WS=2001
PORT_VLESS_GRPC=2002
PORT_VLESS_HUPG=2003
PORT_VMESS_WS=2004
PORT_VMESS_GRPC=2005
PORT_VMESS_HUPG=2006
PORT_TROJAN_WS=2007
PORT_TROJAN_GRPC=2008
PORT_TROJAN_HUPG=2009
PORT_VLESS_NTLS=2011
PORT_VMESS_NTLS=2012
PORT_SSH_WS=2222

# ----------------------------------------------------------------------------
# install_nginx() - Install Nginx and configure main nginx.conf
# ----------------------------------------------------------------------------
install_nginx() {
    msg_info "Installing Nginx..."
    pkg_install nginx

    # Backup original config
    cp -f "${NGINX_CONF}" "${NGINX_CONF}.bak" 2>/dev/null

    # Write optimized nginx.conf
    cat > "${NGINX_CONF}" << EOF
# BraanX - Nginx Main Configuration
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Log format showing real IP
    log_format braanx_log '\$remote_addr - \$remote_user [\$time_local] '
                          '"\$request" \$status \$body_bytes_sent '
                          '"\$http_referer" "\$http_user_agent" '
                          '\$http_x_forwarded_for \$upstream_addr '
                          '\$request_time \$upstream_response_time';

    access_log /var/log/nginx/access.log braanx_log;
    error_log  /var/log/nginx/error.log warn;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 120s;
    keepalive_requests 10000;
    reset_timedout_connection on;
    client_body_timeout 60s;
    send_timeout 60s;

    # Buffer sizes
    client_header_buffer_size 4k;
    large_client_header_buffers 8 8k;
    client_max_body_size 64m;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    # Include site configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

    msg_ok "Nginx main configuration written"

    # Generate site configuration
    configure_nginx

    # Create fake page directory
    mkdir -p /var/www/braanx
    _create_fake_page

    # Test and start
    _nginx_test_and_start
}

# ----------------------------------------------------------------------------
# configure_nginx() - Generate the BraanX site config with all proxy locations
# ----------------------------------------------------------------------------
configure_nginx() {
    msg_info "Configuring Nginx reverse proxy..."

    local domain
    local ip_addr
    domain=$(config_get "DOMAIN")
    ip_addr=$(get_public_ip)
    local server_name="${domain:-${ip_addr}}"

    # Check if TLS certificates exist
    local has_tls="false"
    [[ -f "${SSL_CERT}" && -f "${SSL_KEY}" ]] && has_tls="true"

    cat > "${BRAANX_NGINX}" << EOF
# ============================================================================
# BraanX Nginx Reverse Proxy Configuration
# Auto-generated - do not edit manually
# ============================================================================

# --------------------------------------------------------------------------
# HTTPS Server (Port 443) - TLS Termination
# --------------------------------------------------------------------------
EOF

    if [[ "${has_tls}" == "true" ]]; then
        cat >> "${BRAANX_NGINX}" << EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${server_name};

    # SSL Configuration
    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:50m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer" always;

    # Error pages
    error_page 502 503 504 /50x.html;
    location = /50x.html {
        root /var/www/braanx;
    }

    # ---- VLESS WebSocket ----
    location /vless-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VLESS_WS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- VMess WebSocket ----
    location /vmess-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VMESS_WS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- Trojan WebSocket ----
    location /trojan-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_TROJAN_WS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- SSH-over-WebSocket ----
    location /ssh-ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_SSH_WS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # ---- VLESS gRPC ----
    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:${PORT_VLESS_GRPC};
        include /etc/nginx/snippets/grpc-proxy-params.conf;
    }

    # ---- VMess gRPC ----
    location /vmess-grpc {
        grpc_pass grpc://127.0.0.1:${PORT_VMESS_GRPC};
        include /etc/nginx/snippets/grpc-proxy-params.conf;
    }

    # ---- Trojan gRPC ----
    location /trojan-grpc {
        grpc_pass grpc://127.0.0.1:${PORT_TROJAN_GRPC};
        include /etc/nginx/snippets/grpc-proxy-params.conf;
    }

    # ---- VLESS HTTPUpgrade ----
    location /vless-hupg {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VLESS_HUPG};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- VMess HTTPUpgrade ----
    location /vmess-hupg {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VMESS_HUPG};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- Trojan HTTPUpgrade ----
    location /trojan-hupg {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_TROJAN_HUPG};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- Default location (fallback fake page) ----
    location / {
        proxy_pass http://127.0.0.1:1010;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
    else
        msg_warn "No TLS certificates found - skipping HTTPS server block"
    fi

    # --------------------------------------------------------------------------
    # HTTP Server (Port 80) - Non-TLS
    # --------------------------------------------------------------------------
    cat >> "${BRAANX_NGINX}" << EOF

server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};

    # Redirect to HTTPS if TLS is available
EOF

    if [[ "${has_tls}" == "true" ]]; then
        cat >> "${BRAANX_NGINX}" << EOF
    # Redirect root to HTTPS (except non-TLS paths)
    location / {
        return 301 https://\$host\$request_uri;
    }
EOF
    else
        cat >> "${BRAANX_NGINX}" << EOF
    location / {
        proxy_pass http://127.0.0.1:1010;
        proxy_set_header Host \$host;
    }
EOF
    fi

    cat >> "${BRAANX_NGINX}" << EOF

    # ---- VLESS Non-TLS WebSocket ----
    location /vless-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VLESS_NTLS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # ---- VMess Non-TLS WebSocket ----
    location /vmess-ntls {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${PORT_VMESS_NTLS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
EOF

    # --------------------------------------------------------------------------
    # Fake Page Server (Port 1010) - Maintenance / camouflage page
    # --------------------------------------------------------------------------
    cat >> "${BRAANX_NGINX}" << EOF

server {
    listen 1010;
    server_name _;

    root /var/www/braanx;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Create gRPC proxy params snippet
    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/grpc-proxy-params.conf << EOF
grpc_pass_header Server;
grpc_set_header Host \$host;
grpc_set_header X-Real-IP \$remote_addr;
grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
grpc_socket_keepalive on;
grpc_read_timeout 300s;
grpc_send_timeout 300s;
EOF

    msg_ok "Nginx braanx.conf generated"
}

# ----------------------------------------------------------------------------
# _create_fake_page() - Generate the camouflage web page
# ----------------------------------------------------------------------------
_create_fake_page() {
    cat > "${FAKE_PAGE}" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Server Online</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 0; display: flex; justify-content: center; align-items: center; min-height: 100vh; background: #f5f5f5; }
        .container { text-align: center; padding: 40px; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-bottom: 10px; }
        p { color: #666; }
        .status { display: inline-block; width: 10px; height: 10px; border-radius: 50%; background: #4caf50; margin-right: 8px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Web Server Online</h1>
        <p><span class="status"></span>All systems operational.</p>
        <p style="font-size: 12px; color: #999; margin-top: 20px;">HTTP Server</p>
    </div>
</body>
</html>
HTMLEOF

    chown -R www-data:www-data /var/www/braanx 2>/dev/null || chown -R nginx:nginx /var/www/braanx 2>/dev/null
    msg_ok "Fake web page created"
}

# ----------------------------------------------------------------------------
# _nginx_test_and_start() - Validate config and start Nginx
# ----------------------------------------------------------------------------
_nginx_test_and_start() {
    msg_info "Testing Nginx configuration..."
    if nginx -t 2>/dev/null; then
        msg_ok "Nginx configuration is valid"
        systemctl enable nginx &>/dev/null
        systemctl restart nginx
        if systemctl is-active --quiet nginx; then
            msg_ok "Nginx started successfully"
        else
            msg_err "Nginx failed to start"
            return 1
        fi
    else
        msg_err "Nginx configuration test failed"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# nginx_restart() - Restart Nginx service
# ----------------------------------------------------------------------------
nginx_restart() {
    msg_info "Restarting Nginx..."
    if nginx -t 2>/dev/null; then
        systemctl restart nginx
        msg_ok "Nginx restarted"
    else
        msg_err "Nginx config test failed - not restarting"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# nginx_status() - Show Nginx service status and info
# ----------------------------------------------------------------------------
nginx_status() {
    local status
    status=$(systemctl is-active nginx 2>/dev/null)

    draw_header "NGINX STATUS"
    draw_table \
        "Status" "${status}" \
        "Main Config" "${NGINX_CONF}" \
        "Site Config" "${BRAANX_NGINX}" \
        "SSL Cert" "${SSL_CERT}" \
        "SSL Key" "${SSL_KEY}"

    # Show listening ports
    echo ""
    msg_info "Nginx listening ports:"
    ss -tlnp 2>/dev/null | rg nginx | while read line; do
        echo "  ${line}"
    done
    echo ""

    # Check config validity
    if nginx -t 2>/dev/null; then
        msg_ok "Configuration is valid"
    else
        msg_err "Configuration has errors"
    fi
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_nginx
export -f configure_nginx
export -f nginx_restart
export -f nginx_status
export -f _create_fake_page
export -f _nginx_test_and_start
