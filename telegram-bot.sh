#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - Telegram Bot
# Full remote management via Telegram
# Version: 1.0.0
# ============================================================

set -euo pipefail

readonly BRAANX_DIR="/etc/braanx"
readonly BNX_BOT_CONF="${BRAANX_DIR}/bot.conf"
readonly BNX_USER_DB="/etc/braanx/braanx.db"
readonly BNX_USER_DIR="/etc/braanx/users"
readonly BNX_LOG="/var/log/braanx.log"

# ============================================================
# Configuration
# ============================================================

if [[ -f "$BNX_BOT_CONF" ]]; then
    source "$BNX_BOT_CONF"
else
    echo "Bot config not found at ${BNX_BOT_CONF}" >&2
    exit 1
fi

BOT_TOKEN="${BOT_TOKEN:-}"
ADMIN_ID="${ADMIN_ID:-}"
BOT_ENABLED="${BOT_ENABLED:-false}"

if [[ -z "$BOT_TOKEN" || -z "$ADMIN_ID" ]]; then
    echo "BOT_TOKEN and ADMIN_ID required in ${BNX_BOT_CONF}" >&2
    exit 1
fi

# Telegram Bot API base URL
readonly TG_API="https://api.telegram.org/bot${BOT_TOKEN}"

# Session state storage
readonly BNX_BOT_STATE="${BRAANX_DIR}/bot-state"
readonly BNX_BOT_PENDING="${BRAANX_DIR}/bot-pending"
readonly BNX_BOT_LAST_MSG="${BRAANX_DIR}/bot-last-msg"

mkdir -p "${BRAANX_DIR}"
touch "$BNX_BOT_STATE" "$BNX_BOT_PENDING" "$BNX_BOT_LAST_MSG"

# ============================================================
# Telegram API Helpers
# ============================================================

# Send message
tg_send() {
    local chat_id="${1}"
    local text="${2}"
    local parse_mode="${3:-HTML}"
    local keyboard="${4:-}"
    local disable_webpage="true"

    local data="{\"chat_id\": \"${chat_id}\", \"text\": $(echo "$text" | jq -Rs .), \"parse_mode\": \"${parse_mode}\", \"disable_web_page_preview\": ${disable_webpage}}"

    if [[ -n "$keyboard" ]]; then
        data=$(echo "$data" | jq --argjson kb "$keyboard" '. + {reply_markup: $kb}')
    fi

    curl -s -X POST "${TG_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$data" >/dev/null 2>&1
}

# Send with inline keyboard
tg_send_keyboard() {
    local chat_id="${1}"
    local text="${2}"
    local keyboard="${3}"
    tg_send "$chat_id" "$text" "HTML" "$keyboard"
}

# Send message with reply keyboard markup
tg_send_menu() {
    local chat_id="${1}"
    local text="${2}"

    local keyboard=$(cat <<EOF
{
    "keyboard": [
        [{"text": "📊 Dashboard"}, {"text": "👤 Users"}],
        [{"text": "➕ Create User"}, {"text": "🗑 Delete User"}],
        [{"text": "📅 Extend Expiry"}, {"text": "🔒 Ban/Unban"}],
        [{"text": "🔧 Services"}, {"text": "📈 System Info"}],
        [{"text": "📝 Logs"}, {"text": "⚙️ Settings"}],
        [{"text": "🔄 Restart Service"}],
        [{"text": "🏠 Main Menu"}]
    ],
    "resize_keyboard": true,
    "one_time_keyboard": false
}
EOF
    )

    tg_send "$chat_id" "$text" "HTML" "$keyboard"
}

# Edit existing message
tg_edit() {
    local chat_id="${1}"
    local message_id="${2}"
    local text="${3}"
    local keyboard="${4:-}"

    local data="{\"chat_id\": \"${chat_id}\", \"message_id\": \"${message_id}\", \"text\": $(echo "$text" | jq -Rs .), \"parse_mode\": \"HTML\"}"

    if [[ -n "$keyboard" ]]; then
        data=$(echo "$data" | jq --argjson kb "$keyboard" '. + {reply_markup: $kb}')
    fi

    curl -s -X POST "${TG_API}/editMessageText" \
        -H "Content-Type: application/json" \
        -d "$data" >/dev/null 2>&1
}

# Answer callback query
tg_answer_callback() {
    local callback_id="${1}"
    local text="${2:-}"

    curl -s -X POST "${TG_API}/answerCallbackQuery" \
        -H "Content-Type: application/json" \
        -d "{\"callback_query_id\": \"${callback_id}\", \"text\": \"${text}\"}" >/dev/null 2>&1
}

# Send alert
tg_alert() {
    local chat_id="${1}"
    local text="${2}"
    tg_send "$chat_id" "⚠️ <b>${text}</b>" "HTML"
}

# ============================================================
# Bot Command Handlers
# ============================================================

cmd_start() {
    local chat_id="${1}"
    tg_send_menu "$chat_id" "👋 <b>Welcome to BraanX Bot</b>

Your server is connected and ready for remote management.

<i>Use the menu buttons below to control your VPN services.</i>"
}

cmd_help() {
    local chat_id="${1}"
    tg_send "$chat_id" "📖 <b>BraanX Bot Help</b>

<b>Dashboard</b> — View server status & active services
<b>Users</b> — List all user accounts
<b>Create User</b> — Add a new VPN user
<b>Delete User</b> — Remove a user
<b>Extend Expiry</b> — Extend a user's access time
<b>Ban/Unban</b> — Ban or unban a user
<b>Services</b> — Start/stop/restart services
<b>System Info</b> — CPU, RAM, Disk, Network stats
<b>Logs</b> — View recent activity logs
<b>Settings</b> — Bot configuration
<b>Restart Service</b> — Restart a specific service

💡 <i>Use /menu to return to the main menu at any time.</i>"
}

cmd_menu() {
    local chat_id="${1}"
    tg_send_menu "$chat_id" "🏠 <b>BraanX Control Panel</b>"
}

# ============================================================
# Dashboard
# ============================================================

cmd_dashboard() {
    local chat_id="${1}"
    local msg_id="${2:-}"

    local ipv4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")
    local hostname=$(hostname -f 2>/dev/null || hostname)
    local uptime=$(uptime -p 2>/dev/null || uptime)
    local total_ram=$(free -m | awk '/Mem:/ {print $2}')
    local used_ram=$(free -m | awk '/Mem:/ {print $3}')
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_pct=$(df -h / | awk 'NR==2 {print $5}')
    local active_users=0
    local total_users=0

    if [[ -f "$BNX_USER_DB" ]]; then
        total_users=$(wc -l < "$BNX_USER_DB" | tr -d ' ')
        local now=$(date +%s)
        while IFS='|' read -r u uuid pass created ce expiry quota status la; do
            [[ "$status" == "active" && "$expiry" -gt "$now" ]] && ((active_users++))
        done < "$BNX_USER_DB" 2>/dev/null
    fi

    # Service status
    local xray_st="🔴"
    systemctl is-active xray &>/dev/null && xray_st="🟢"
    local nginx_st="🔴"
    systemctl is-active nginx &>/dev/null && nginx_st="🟢"
    local ssh_st="🔴"
    systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null && ssh_st="🟢"
    local fail2ban_st="🔴"
    systemctl is-active fail2ban &>/dev/null && fail2ban_st="🟢"

    local msg=$(cat <<EOF
📊 <b>BraanX Dashboard</b>

🖥 <b>Server</b>
   Hostname: <code>${hostname}</code>
   IPv4: <code>${ipv4}</code>
   Uptime: <code>${uptime}</code>

💾 <b>Resources</b>
   RAM: ${used_ram}MB / ${total_ram}MB
   Disk: ${disk_pct} used

👥 <b>Users</b>
   Active: <b>${active_users}</b> / Total: ${total_users}

🔧 <b>Services</b>
   Xray: ${xray_st} | Nginx: ${nginx_st} | SSH: ${ssh_st} | Fail2ban: ${fail2ban_st}
EOF
    )

    if [[ -n "$msg_id" ]]; then
        tg_edit "$chat_id" "$msg_id" "$msg"
    else
        tg_send "$chat_id" "$msg"
    fi
}

# ============================================================
# User Management via Bot
# ============================================================

cmd_users_list() {
    local chat_id="${1}"

    if [[ ! -f "$BNX_USER_DB" ]] || [[ ! -s "$BNX_USER_DB" ]]; then
        tg_send "$chat_id" "📋 <b>No users found</b>\n\nCreate users with ➕ Create User"
        return
    fi

    local msg="👥 <b>User List</b>\n\n"

    while IFS='|' read -r username uuid password created ce expiry quota status la; do
        local expiry_str
        expiry_str=$(date -d "@$expiry" '+%Y-%m-%d' 2>/dev/null || date -r "$expiry" '+%Y-%m-%d' 2>/dev/null)
        local now=$(date +%s)

        local status_icon="🟢"
        if [[ "$status" == "banned" ]]; then
            status_icon="🔴"
        elif (( expiry < now )); then
            status_icon="⚠️"
        fi

        msg+="  ${status_icon} <code>${username}</code> — Exp: <code>${expiry_str}</code> | Quota: <code>${quota}</code>\n"
    done < "$BNX_USER_DB" 2>/dev/null

    msg+="\n💡 Tap username to copy"

    tg_send "$chat_id" "$msg"
}

cmd_create_user() {
    local chat_id="${1}"
    echo "CREATE_USER" > "$BNX_BOT_STATE"
    echo "$chat_id" > "$BNX_BOT_PENDING"
    tg_send "$chat_id" "➕ <b>Create New User</b>\n\nReply with the username (or username,expiry_days,quota_gb):\n\n<b>Examples:</b>\n<code>john</code> (default 30 days)\n<code>john,7</code> (7 days)\n<code>john,30,10</code> (30 days, 10GB quota)\n\nReply /cancel to abort."
}

handle_create_user() {
    local chat_id="${1}"
    local text="${2}"

    local username expiry quota

    IFS=',' read -r username expiry quota <<< "$text"

    [[ -z "$username" ]] && {
        tg_send "$chat_id" "❌ Username is required. Try again or /cancel"
        return
    }

    expiry="${expiry:-30}"
    quota="${quota:-unlimited}"
    [[ "$quota" == "0" ]] && quota="unlimited"
    [[ "$quota" != "unlimited" ]] && quota="${quota}GB"

    # Check if user exists
    if grep -q "^${username}|" "$BNX_USER_DB" 2>/dev/null; then
        tg_send "$chat_id" "❌ User <code>${username}</code> already exists"
        return
    fi

    # Create user in BraanX DB
    local created_at=$(date '+%Y-%m-%d %H:%M:%S')
    local created_epoch=$(date +%s)
    local expiry_epoch=$(( created_epoch + (expiry * 86400) ))
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM-$RANDOM")
    local password=$(openssl rand -base64 12 2>/dev/null | tr -d '/+=' | head -c 12)
    local expiry_str
    expiry_str=$(date -d "@$expiry_epoch" '+%Y-%m-%d' 2>/dev/null || date -r "$expiry_epoch" '+%Y-%m-%d' 2>/dev/null)

    echo "${username}|${uuid}|${password}|${created_at}|${created_epoch}|${expiry_epoch}|${quota}|active|$(date +%s)" >> "$BNX_USER_DB"

    mkdir -p "$BNX_USER_DIR"
    cat > "${BNX_USER_DIR}/${username}" <<EOF
USERNAME=${username}
UUID=${uuid}
PASSWORD=${password}
CREATED=${created_at}
CREATED_EPOCH=${created_epoch}
EXPIRY_EPOCH=${expiry_epoch}
QUOTA=${quota}
STATUS=active
SERVICES=
EOF

    # Create SSH user
    useradd -m -s /bin/bash "$username" 2>/dev/null && \
        echo "${username}:${password}" | chpasswd 2>/dev/null

    # Log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [USER_CREATE] User ${username} created via Telegram (expiry: ${expiry}d, quota: ${quota})" >> "$BNX_LOG"

    tg_send "$chat_id" "✅ <b>User Created</b>

👤 <b>Username:</b> <code>${username}</code>
🔑 <b>Password:</b> <code>${password}</code>
🆔 <b>UUID:</b> <code>${uuid}</code>
📅 <b>Expiry:</b> <code>${expiry_str}</code>
📦 <b>Quota:</b> <code>${quota}</code>"

    # Reset state
    echo "" > "$BNX_BOT_STATE"
    echo "" > "$BNX_BOT_PENDING"
}

cmd_delete_user() {
    local chat_id="${1}"
    echo "DELETE_USER" > "$BNX_BOT_STATE"
    echo "$chat_id" > "$BNX_BOT_PENDING"
    tg_send "$chat_id" "🗑 <b>Delete User</b>\n\nReply with the username to delete:\n\nReply /cancel to abort."
}

handle_delete_user() {
    local chat_id="${1}"
    local username="${2}"

    if ! grep -q "^${username}|" "$BNX_USER_DB" 2>/dev/null; then
        tg_send "$chat_id" "❌ User <code>${username}</code> not found"
        return
    fi

    sed -i "/^${username}|/d" "$BNX_USER_DB"
    rm -f "${BNX_USER_DIR}/${username}"
    id "$username" &>/dev/null && userdel -r "$username" 2>/dev/null

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [USER_DELETE] User ${username} deleted via Telegram" >> "$BNX_LOG"

    tg_send "$chat_id" "✅ User <code>${username}</code> has been deleted"
    echo "" > "$BNX_BOT_STATE"
    echo "" > "$BNX_BOT_PENDING"
}

cmd_extend() {
    local chat_id="${1}"
    echo "EXTEND_USER" > "$BNX_BOT_STATE"
    echo "$chat_id" > "$BNX_BOT_PENDING"
    tg_send "$chat_id" "📅 <b>Extend User Expiry</b>\n\nReply with: <code>username,days</code>\n\nExample: <code>john,30</code>\n\nReply /cancel to abort."
}

handle_extend() {
    local chat_id="${1}"
    local text="${2}"
    local username extra_days
    IFS=',' read -r username extra_days <<< "$text"

    [[ -z "$username" ]] && {
        tg_send "$chat_id" "❌ Invalid format. Use: username,days"
        return
    }

    extra_days="${extra_days:-30}"

    local user_file="${BNX_USER_DIR}/${username}"
    if [[ ! -f "$user_file" ]]; then
        tg_send "$chat_id" "❌ User <code>${username}</code> not found"
        return
    fi

    local current_epoch
    current_epoch=$(grep "^EXPIRY_EPOCH=" "$user_file" | cut -d= -f2)
    local now=$(date +%s)
    local new_epoch

    if (( current_epoch < now )); then
        new_epoch=$(( now + (extra_days * 86400) ))
    else
        new_epoch=$(( current_epoch + (extra_days * 86400) ))
    fi

    sed -i "s/^EXPIRY_EPOCH=.*/EXPIRY_EPOCH=${new_epoch}/" "$user_file"
    # Also update main DB
    local new_expiry_str
    new_expiry_str=$(date -d "@$new_epoch" '+%Y-%m-%d' 2>/dev/null || date -r "$new_epoch" '+%Y-%m-%d' 2>/dev/null)

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [USER_EXTEND] User ${username} extended by ${extra_days}d via Telegram" >> "$BNX_LOG"

    tg_send "$chat_id" "✅ User <code>${username}</code> extended by <b>${extra_days} days</b>\n\nNew expiry: <code>${new_expiry_str}</code>"
    echo "" > "$BNX_BOT_STATE"
    echo "" > "$BNX_BOT_PENDING"
}

cmd_ban() {
    local chat_id="${1}"
    echo "BAN_USER" > "$BNX_BOT_STATE"
    echo "$chat_id" > "$BNX_BOT_PENDING"
    tg_send "$chat_id" "🔒 <b>Ban/Unban User</b>\n\nReply with: <code>username</code> to toggle ban status\n\nReply /cancel to abort."
}

handle_ban() {
    local chat_id="${1}"
    local username="${2}"

    local user_file="${BNX_USER_DIR}/${username}"
    if [[ ! -f "$user_file" ]]; then
        tg_send "$chat_id" "❌ User <code>${username}</code> not found"
        return
    fi

    local current_status
    current_status=$(grep "^STATUS=" "$user_file" | cut -d= -f2)

    if [[ "$current_status" == "banned" ]]; then
        sed -i "s/^STATUS=.*/STATUS=active/" "$user_file"
        tg_send "$chat_id" "✅ User <code>${username}</code> has been <b>unbanned</b>"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [USER_UNBAN] User ${username} unbanned via Telegram" >> "$BNX_LOG"
    else
        sed -i "s/^STATUS=.*/STATUS=banned/" "$user_file"
        tg_send "$chat_id" "🔒 User <code>${username}</code> has been <b>banned</b>"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [USER_BAN] User ${username} banned via Telegram" >> "$BNX_LOG"
    fi

    echo "" > "$BNX_BOT_STATE"
    echo "" > "$BNX_BOT_PENDING"
}

# ============================================================
# Service Controls
# ============================================================

cmd_services() {
    local chat_id="${1}"

    local msg="🔧 <b>Service Controls</b>\n\n"
    msg+="Select a service to toggle:\n"

    local services=("xray" "nginx" "ssh" "dropbear" "openvpn" "fail2ban" "wireguard")
    local keyboard_rows=()
    local row=""

    for svc in "${services[@]}"; do
        local status_icon="🔴"
        systemctl is-active "$svc" &>/dev/null && status_icon="🟢"
        row+="{\"text\": \"${status_icon} ${svc^^}\"}"
        if (( ${#keyboard_rows[@]} % 2 == 0 && ${#row} > 10 )); then
            keyboard_rows+=("$row")
            row=""
        fi
    done

    tg_send_keyboard "$chat_id" "$msg" "[{\"inline_keyboard\": [[{\"text\": \"🟢 XRAY\"}, {\"text\": \"🟢 NGINX\"}]]}]"
}

# ============================================================
# System Info
# ============================================================

cmd_system_info() {
    local chat_id="${1}"

    local os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    local kernel=$(uname -r)
    local arch=$(uname -m)
    local uptime=$(uptime -p 2>/dev/null)
    local total_ram=$(free -m | awk '/Mem:/ {print $2}')
    local used_ram=$(free -m | awk '/Mem:/ {print $3}')
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    local disk_pct=$(df -h / | awk 'NR==2 {print $5}')
    local cpu_cores=$(nproc)
    local cpu_model=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    local tcp_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    local load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')

    tg_send "$chat_id" "📈 <b>System Information</b>

🖥 <b>System</b>
   OS: <code>${os_name}</code>
   Kernel: <code>${kernel}</code>
   Arch: <code>${arch}</code>
   Uptime: <code>${uptime}</code>

💾 <b>Resources</b>
   CPU: <code>${cpu_cores} cores — ${cpu_model}</code>
   RAM: <code>${used_ram}MB / ${total_ram}MB</code>
   Disk: <code>${disk_used} / ${disk_total} (${disk_pct})</code>
   Load: <code>${load}</code>

🌐 <b>Network</b>
   TCP CC: <code>${tcp_cc}</code>"
}

# ============================================================
# Logs
# ============================================================

cmd_logs() {
    local chat_id="${1}"

    local entries
    entries=$(tail -20 "$BNX_LOG" 2>/dev/null)

    if [[ -z "$entries" ]]; then
        tg_send "$chat_id" "📝 <b>Recent Logs</b>\n\nNo recent log entries found."
        return
    fi

    local msg="📝 <b>Recent Logs (last 20)</b>\n\n<code>"
    msg+=$(echo "$entries" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    msg+="</code>"

    # Telegram message limit is 4096 chars
    if (( ${#msg} > 4000 )); then
        msg=$(echo "$entries" | tail -10 | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        msg="📝 <b>Recent Logs (last 10)</b>\n\n<code>${msg}</code>"
    fi

    tg_send "$chat_id" "$msg"
}

# ============================================================
# Restart Service
# ============================================================

cmd_restart() {
    local chat_id="${1}"
    echo "RESTART_SVC" > "$BNX_BOT_STATE"
    echo "$chat_id" > "$BNX_BOT_PENDING"
    tg_send "$chat_id" "🔄 <b>Restart Service</b>\n\nReply with service name:\n<code>xray</code>\n<code>nginx</code>\n<code>ssh</code>\n<code>dropbear</code>\n<code>openvpn</code>\n<code>fail2ban</code>\n\nReply /cancel to abort."
}

handle_restart() {
    local chat_id="${1}"
    local service="${2}"

    if systemctl restart "$service" 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BOT] Service ${service} restarted via Telegram" >> "$BNX_LOG"
        tg_send "$chat_id" "✅ Service <code>${service}</code> restarted successfully"
    else
        tg_send "$chat_id" "❌ Failed to restart <code>${service}</code>. Check service name."
    fi

    echo "" > "$BNX_BOT_STATE"
    echo "" > "$BNX_BOT_PENDING"
}

# ============================================================
# Expiry Check Cron (runs from crontab)
# ============================================================

cron_check_expiry() {
    if [[ ! -f "$BNX_USER_DB" ]]; then
        return
    fi

    local now=$(date +%s)
    local expired_users=()

    while IFS='|' read -r username uuid password created ce expiry quota status la; do
        if [[ "$status" == "active" && "$expiry" -lt "$now" ]]; then
            expired_users+=("$username")
            # Update status
            if [[ -f "${BNX_USER_DIR}/${username}" ]]; then
                sed -i "s/^STATUS=.*/STATUS=expired/" "${BNX_USER_DIR}/${username}"
            fi
            # Remove SSH access
            id "$username" &>/dev/null && usermod -s /usr/sbin/nologin "$username" 2>/dev/null

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [EXPIRY] User ${username} expired" >> "$BNX_LOG"
        fi
    done < "$BNX_USER_DB" 2>/dev/null

    # Notify admin via Telegram
    if (( ${#expired_users[@]} > 0 )) && [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
        local msg="⏰ <b>Users Expired</b>\n\n"
        for u in "${expired_users[@]}"; do
            msg+="🔴 <code>${u}</code>\n"
        done
        tg_send "$ADMIN_ID" "$msg"
    fi
}

# ============================================================
# Main Message Loop
# ============================================================

process_update() {
    local update="${1}"
    local message=$(echo "$update" | jq -r '.message // empty')
    local callback_query=$(echo "$update" | jq -r '.callback_query // empty')

    if [[ -n "$callback_query" && "$callback_query" != "null" ]]; then
        # Handle callback buttons
        local cb_id=$(echo "$callback_query" | jq -r '.id')
        local cb_data=$(echo "$callback_query" | jq -r '.data')
        local cb_chat=$(echo "$callback_query" | jq -r '.message.chat.id')
        local cb_msg_id=$(echo "$callback_query" | jq -r '.message.message_id')

        tg_answer_callback "$cb_id" ""
        return
    fi

    # Handle text messages
    [[ "$message" == "null" || -z "$message" ]] && return

    local chat_id=$(echo "$message" | jq -r '.chat.id')
    local text=$(echo "$message" | jq -r '.text // empty')

    # Auth check
    if [[ "$chat_id" != "$ADMIN_ID" ]]; then
        tg_send "$chat_id" "🔒 Unauthorized access"
        return
    fi

    # Command handling
    case "$text" in
        /start|/menu|🏠\ Main\ Menu)
            cmd_menu "$chat_id"
            ;;
        /help)
            cmd_help "$chat_id"
            ;;
        /dashboard|📊\ Dashboard)
            cmd_dashboard "$chat_id"
            ;;
        /users|👤\ Users)
            cmd_users_list "$chat_id"
            ;;
        /create|➕\ Create\ User)
            cmd_create_user "$chat_id"
            ;;
        /delete|🗑\ Delete\ User)
            cmd_delete_user "$chat_id"
            ;;
        /extend|📅\ Extend\ Expiry)
            cmd_extend "$chat_id"
            ;;
        /ban|🔒\ Ban/Unban)
            cmd_ban "$chat_id"
            ;;
        /services|🔧\ Services)
            cmd_services "$chat_id"
            ;;
        /sysinfo|📈\ System\ Info)
            cmd_system_info "$chat_id"
            ;;
        /logs|📝\ Logs)
            cmd_logs "$chat_id"
            ;;
        /settings|⚙️\ Settings)
            tg_send "$chat_id" "⚙️ <b>Settings</b>\n\nBot is configured via:\n<code>${BNX_BOT_CONF}</code>\n\nAdmin ID: <code>${ADMIN_ID}</code>\nNotifications: <b>${NOTIFY_NEW_USER:-true}</b>"
            ;;
        /restart|🔄\ Restart\ Service)
            cmd_restart "$chat_id"
            ;;
        /cancel)
            echo "" > "$BNX_BOT_STATE"
            echo "" > "$BNX_BOT_PENDING"
            tg_send_menu "$chat_id" "❌ Action cancelled"
            ;;
        *)
            # Handle pending states
            local state=$(cat "$BNX_BOT_STATE" 2>/dev/null)
            case "$state" in
                CREATE_USER)   handle_create_user "$chat_id" "$text" ;;
                DELETE_USER)   handle_delete_user "$chat_id" "$text" ;;
                EXTEND_USER)    handle_extend "$chat_id" "$text" ;;
                BAN_USER)      handle_ban "$chat_id" "$text" ;;
                RESTART_SVC)   handle_restart "$chat_id" "$text" ;;
                *) tg_send "$chat_id" "🤔 Unknown command. Use /menu for options." ;;
            esac
            ;;
    esac
}

# ============================================================
# Polling Loop
# ============================================================

run_bot() {
    local offset=0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BOT] BraanX Telegram Bot started" >> "$BNX_LOG"

    while true; do
        local updates
        updates=$(curl -s "${TG_API}/getUpdates?offset=${offset}&timeout=30&allowed_updates=[\"message\"]" 2>/dev/null)

        local count=$(echo "$updates" | jq -r '.result | length')
        if [[ "$count" -gt 0 && "$count" != "null" ]]; then
            for ((i=0; i<count; i++)); do
                local update=$(echo "$updates" | jq -r ".result[$i]")
                local update_id=$(echo "$update" | jq -r '.update_id')
                offset=$((update_id + 1))
                process_update "$update" &
            done
            wait
        fi
    done
}

# Run in cron mode (for expiry checks)
if [[ "${1:-}" == "--cron" ]]; then
    cron_check_expiry
    exit 0
fi

# Run in daemon mode
run_bot
