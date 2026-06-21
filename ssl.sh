#!/bin/bash
# ============================================================================
# BraanX - SSL Certificate Management
# ============================================================================
# Manages SSL/TLS certificates using acme.sh (Let's Encrypt).
# Handles certificate issuance, renewal, and info display.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# ============================================================================
source /etc/braanx/lib/functions.sh

ACME_HOME="/root/.acme.sh"
ACME_BIN="${ACME_HOME}/acme.sh"
SSL_DIR="/etc/braanx/ssl"
SSL_CERT="${SSL_DIR}/fullchain.pem"
SSL_KEY="${SSL_DIR}/privkey.pem"
BRAANX_CONF="/etc/braanx/braanx.conf"
ACME_LOG="/var/log/braanx/acme.log"

# ----------------------------------------------------------------------------
# install_acme() - Install acme.sh certificate management tool
# ----------------------------------------------------------------------------
install_acme() {
    msg_info "Installing acme.sh..."

    # Install dependencies
    pkg_install curl socat cron

    # Create SSL directory
    mkdir -p "${SSL_DIR}"
    mkdir -p "$(dirname "${ACME_LOG}")"

    # Install acme.sh if not present
    if [[ -f "${ACME_BIN}" ]]; then
        msg_info "acme.sh already installed, updating..."
        "${ACME_BIN}" --upgrade --auto-upgrade 2>/dev/null
    else
        # Download and install acme.sh
        curl -sL https://get.acme.sh | sh -s email=admin@braanx.local 2>/dev/null
        if [[ $? -ne 0 ]]; then
            msg_err "Failed to install acme.sh"
            return 1
        fi
        msg_ok "acme.sh installed to ${ACME_HOME}"
    fi

    # Ensure acme.sh is executable
    chmod +x "${ACME_BIN}" 2>/dev/null

    # Set default CA to Let's Encrypt
    "${ACME_BIN}" --set-default-ca --server letsencrypt 2>/dev/null

    # Enable auto-upgrade
    "${ACME_BIN}" --upgrade --auto-upgrade 2>/dev/null

    msg_ok "acme.sh ready"
}

# ----------------------------------------------------------------------------
# generate_ssl() - Issue a Let's Encrypt certificate for a domain
#   $1 = domain (e.g., vpn.example.com)
#   $2 = email (for Let's Encrypt notifications)
# ----------------------------------------------------------------------------
generate_ssl() {
    local domain="${1}"
    local email="${2}"

    if [[ -z "${domain}" ]]; then
        msg_err "Usage: generate_ssl <domain> [email]"
        return 1
    fi
    [[ -z "${email}" ]] && email="admin@braanx.local"

    msg_info "Requesting SSL certificate for: ${domain}"

    # Ensure acme.sh is installed
    if [[ ! -f "${ACME_BIN}" ]]; then
        install_acme
    fi

    # Check if certificate already exists
    if [[ -f "${SSL_CERT}" && -f "${SSL_KEY}" ]]; then
        local expiry_days
        expiry_days=$(_check_cert_days "${SSL_CERT}")
        if [[ "${expiry_days}" -gt 30 ]]; then
            msg_info "Certificate still valid for ${expiry_days} days"
            return 0
        fi
        msg_info "Certificate expiring soon, renewing..."
    fi

    # Temporarily stop nginx if it is running to free port 80
    local nginx_was_running=false
    if systemctl is-active --quiet nginx; then
        nginx_was_running=true
        msg_info "Stopping Nginx temporarily for certificate issuance..."
        systemctl stop nginx
    fi

    # Issue certificate using standalone mode (port 80)
    "${ACME_BIN}" --issue \
        -d "${domain}" \
        --standalone \
        --httpport 80 \
        --keylength ec-256 \
        --email "${email}" \
        --log "${ACME_LOG}" \
        --force

    local result=$?

    # Restart nginx if it was running
    if [[ "${nginx_was_running}" == "true" ]]; then
        systemctl start nginx 2>/dev/null
    fi

    if [[ ${result} -ne 0 ]]; then
        msg_err "Failed to issue certificate for ${domain}"
        return 1
    fi

    # Install certificate to target directory
    mkdir -p "${SSL_DIR}"

    "${ACME_BIN}" --install-cert \
        -d "${domain}" \
        --ecc \
        --cert-file "${SSL_DIR}/cert.pem" \
        --key-file "${SSL_DIR}/privkey.pem" \
        --fullchain-file "${SSL_DIR}/fullchain.pem" \
        --reloadcmd "systemctl reload nginx" \
        --log "${ACME_LOG}"

    if [[ $? -ne 0 ]]; then
        msg_err "Failed to install certificate files"
        return 1
    fi

    # Set proper permissions
    chmod 644 "${SSL_DIR}/cert.pem" "${SSL_DIR}/fullchain.pem"
    chmod 600 "${SSL_DIR}/privkey.pem"

    # Save to config
    config_set "DOMAIN" "${domain}"
    config_set "SSL_CERT" "${SSL_CERT}"
    config_set "SSL_KEY" "${SSL_KEY}"
    config_set "SSL_EMAIL" "${email}"

    # Set up auto-renewal cron
    _setup_auto_renewal

    msg_ok "SSL certificate issued and installed for ${domain}"
}

# ----------------------------------------------------------------------------
# renew_ssl() - Force renewal of the SSL certificate
#   $1 = domain (optional, reads from config if not provided)
# ----------------------------------------------------------------------------
renew_ssl() {
    local domain="${1}"
    [[ -z "${domain}" ]] && domain=$(config_get "DOMAIN")

    if [[ -z "${domain}" ]]; then
        msg_err "No domain configured. Usage: renew_ssl [domain]"
        return 1
    fi

    msg_info "Force-renewing SSL certificate for: ${domain}"

    "${ACME_BIN}" --renew \
        -d "${domain}" \
        --ecc \
        --force \
        --log "${ACME_LOG}"

    if [[ $? -eq 0 ]]; then
        msg_ok "SSL certificate renewed successfully"
        ssl_info
    else
        msg_err "SSL certificate renewal failed"
        return 1
    fi
}

# ----------------------------------------------------------------------------
# ssl_info() - Display SSL certificate information
# ----------------------------------------------------------------------------
ssl_info() {
    if [[ ! -f "${SSL_CERT}" ]]; then
        msg_warn "No SSL certificate found at ${SSL_CERT}"
        return 0
    fi

    local domain
    domain=$(config_get "DOMAIN")

    draw_header "SSL CERTIFICATE INFO"

    # Certificate details
    echo ""
    openssl x509 -in "${SSL_CERT}" -noout -subject -dates -issuer 2>/dev/null | while read line; do
        msg_info "  ${line}"
    done

    # Days until expiry
    local expiry_days
    expiry_days=$(_check_cert_days "${SSL_CERT}")
    echo ""

    if [[ ${expiry_days} -gt 30 ]]; then
        msg_ok "Certificate valid for ${expiry_days} more days"
    elif [[ ${expiry_days} -gt 0 ]]; then
        msg_warn "Certificate expires in ${expiry_days} days - consider renewal"
    else
        msg_err "Certificate has expired!"
    fi

    echo ""
    draw_table \
        "Domain" "${domain:-unknown}" \
        "Cert Path" "${SSL_CERT}" \
        "Key Path" "${SSL_KEY}" \
        "Expires In" "${expiry_days} days" \
        "ACME Home" "${ACME_HOME}"
}

# ----------------------------------------------------------------------------
# _check_cert_days() - Calculate days until certificate expiry
#   $1 = certificate file path
# Returns: number of days (integer)
# ----------------------------------------------------------------------------
_check_cert_days() {
    local cert="${1}"
    local expiry_date
    local now_date

    if [[ ! -f "${cert}" ]]; then
        echo "0"
        return
    fi

    expiry_date=$(date -d "$(openssl x509 -in "${cert}" -noout -enddate 2>/dev/null | cut -d= -f2)" +%s 2>/dev/null)
    now_date=$(date +%s)

    if [[ -z "${expiry_date}" ]]; then
        echo "0"
        return
    fi

    echo $(( (expiry_date - now_date) / 86400 ))
}

# ----------------------------------------------------------------------------
# _setup_auto_renewal() - Configure cron for automatic certificate renewal
# ----------------------------------------------------------------------------
_setup_auto_renewal() {
    local domain
    domain=$(config_get "DOMAIN")
    [[ -z "${domain}" ]] && return

    # Add cron job for acme.sh renewal (once a week, at random minute/hour)
    local cron_line
    local random_minute=$((RANDOM % 60))
    local random_hour=$((RANDOM % 6))

    cron_line="${random_minute} ${random_hour} * * 0 \"${ACME_BIN}\" --cron --home \"${ACME_HOME}\" >> \"${ACME_LOG}\" 2>&1"

    # Check if cron already has our entry
    if ! crontab -l 2>/dev/null | rg -q "acme.sh.*--cron"; then
        (crontab -l 2>/dev/null; echo "${cron_line}") | crontab -
        msg_info "Auto-renewal cron job added"
    fi
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_acme
export -f generate_ssl
export -f renew_ssl
export -f ssl_info
export -f _check_cert_days
export -f _setup_auto_renewal
