#!/bin/bash
# ============================================================
# BraanX - Auto Account Renewal & Cleanup Cron Job
# Handles expired users, quota enforcement, notifications
# ============================================================

set -euo pipefail

readonly BRAANX_DIR="/etc/braanx"
readonly BNX_USER_DB="${BRAANX_DIR}/braanx.db"
readonly BNX_USER_DIR="${BRAANX_DIR}/users"
readonly BNX_LOG="/var/log/braanx.log"
readonly BNX_BOT_CONF="${BRAANX_DIR}/bot.conf"

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CRON] $1" >> "$BNX_LOG"
}

notify_telegram() {
    local msg="${1}"
    if [[ -f "$BNX_BOT_CONF" ]]; then
        source "$BNX_BOT_CONF"
        if [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
            curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                -H "Content-Type: application/json" \
                -d "{\"chat_id\": \"${ADMIN_ID}\", \"text\": \"${msg}\", \"parse_mode\": \"HTML\"}" >/dev/null 2>&1
        fi
    fi
}

check_expired_users() {
    if [[ ! -f "$BNX_USER_DB" ]] || [[ ! -s "$BNX_USER_DB" ]]; then
        return
    fi

    local now=$(date +%s)
    local expired=()
    local expiring_soon=() # 3 days or less

    while IFS='|' read -r username uuid password created ce expiry quota status la; do
        if [[ "$status" != "active" ]]; then
            continue
        fi

        local remaining=$(( (expiry - now) / 86400 ))

        if (( remaining < 0 )); then
            expired+=("$username")
        elif (( remaining <= 3 )); then
            expiring_soon+=("${username}:${remaining}")
        fi
    done < "$BNX_USER_DB" 2>/dev/null

    # Process expired users
    for username in "${expired[@]}"; do
        sed -i "s/^STATUS=.*/STATUS=expired/" "${BNX_USER_DIR}/${username}" 2>/dev/null
        # Remove SSH access
        id "$username" &>/dev/null && usermod -s /usr/sbin/nologin "$username" 2>/dev/null
        log_msg "User ${username} expired — access revoked"
    done

    # Notify about expirations
    if (( ${#expired[@]} > 0 )); then
        local msg="⏰ <b>Expired Users (${#expired[@]})</b>\n\n"
        for u in "${expired[@]}"; do
            msg+="🔴 <code>${u}</code> — expired\n"
        done
        notify_telegram "$msg"
    fi

    if (( ${#expiring_soon[@]} > 0 )); then
        local msg="⚠️ <b>Expiring Soon</b>\n\n"
        for entry in "${expiring_soon[@]}"; do
            local u="${entry%%:*}"
            local d="${entry##*:}"
            msg+="🔸 <code>${u}</code> — ${d} days left\n"
        done
        notify_telegram "$msg"
    fi
}

cleanup_old_logs() {
    # Keep last 5000 lines of log
    if [[ -f "$BNX_LOG" ]] && (( $(wc -l < "$BNX_LOG") > 5000 )); then
        tail -5000 "$BNX_LOG" > "${BNX_LOG}.tmp"
        mv "${BNX_LOG}.tmp" "$BNX_LOG"
        log_msg "Log file trimmed"
    fi
}

check_cert_expiry() {
    # Check if any Let's Encrypt certs are expiring within 7 days
    if command -v certbot &>/dev/null; then
        local expiring
        expiring=$(certbot certificates 2>/dev/null | grep -A 2 "Expiry Date" | grep -B 1 "days" | head -4)
        if [[ -n "$expiring" ]]; then
            notify_telegram "🔐 <b>Certificate Expiry Warning</b>\n\n${expiring}"
        fi
    fi
}

# ============================================================
# Run all checks
# ============================================================

log_msg "Starting scheduled maintenance..."
check_expired_users
cleanup_old_logs
check_cert_expiry
log_msg "Scheduled maintenance completed"
