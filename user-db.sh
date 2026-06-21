#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - User Database Management
# Version: 1.0.0
# ============================================================

[[ -n "$_BNX_DB_LOADED" ]] && return 0
_BNX_DB_LOADED=1

BNX_USER_DB="/etc/braanx/braanx.db"
BNX_USER_DIR="/etc/braanx/users"
BNX_LOG_FILE="/var/log/braanx.log"

# Initialize database
init_user_db() {
    mkdir -p /etc/braanx
    mkdir -p "$BNX_USER_DIR"
    touch "$BNX_USER_DB"
    chmod 600 "$BNX_USER_DB"
    mkdir -p "$(dirname "$BNX_LOG_FILE")"
    touch "$BNX_LOG_FILE"
}

# ============================================================
# User CRUD Operations
# ============================================================

# Create a new user
user_create() {
    local username="${1}"
    local expiry_days="${2:-30}"
    local quota="${3:-unlimited}"

    if [[ -z "$username" ]]; then
        bnx_error "Username is required"
        return 1
    fi

    if user_exists "$username"; then
        bnx_error "User '$username' already exists"
        return 1
    fi

    local created_at created_epoch expiry_epoch
    created_at=$(date '+%Y-%m-%d %H:%M:%S')
    created_epoch=$(date +%s)
    expiry_epoch=$(( created_epoch + (expiry_days * 86400) ))

    # Generate UUID for the user
    local uuid
    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || echo "$RANDOM$RANDOM")

    # Generate random password for SSH users
    local password
    password=$(openssl rand -base64 12 2>/dev/null | tr -d '/+=' | head -c 12)

    # Save to database
    echo "${username}|${uuid}|${password}|${created_at}|${created_epoch}|${expiry_epoch}|${quota}|active|$(date +%s)" >> "$BNX_USER_DB"

    # Create individual user file
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

    log_event "USER_CREATE" "Created user: ${username} (expiry: ${expiry_days}d, quota: ${quota})"
    bnx_success "User '$username' created successfully"
}

# Check if user exists
user_exists() {
    local username="${1}"
    [[ -f "${BNX_USER_DIR}/${username}" ]] && return 0
    return 1
}

# Get user data
user_get() {
    local username="${1}"
    local field="${2:-}"

    local user_file="${BNX_USER_DIR}/${username}"
    if [[ ! -f "$user_file" ]]; then
        bnx_error "User '$username' not found"
        return 1
    fi

    if [[ -n "$field" ]]; then
        grep "^${field}=" "$user_file" 2>/dev/null | cut -d= -f2-
    else
        cat "$user_file"
    fi
}

# Delete user
user_delete() {
    local username="${1}"

    if ! user_exists "$username"; then
        bnx_error "User '$username' not found"
        return 1
    fi

    # Remove from main DB
    sed -i "/^${username}|/d" "$BNX_USER_DB"

    # Remove user file
    rm -f "${BNX_USER_DIR}/${username}"

    # Remove SSH user if exists
    if id "$username" &>/dev/null; then
        userdel -r "$username" 2>/dev/null
    fi

    log_event "USER_DELETE" "Deleted user: ${username}"
    bnx_success "User '$username' deleted"
}

# Extend user expiry
user_extend() {
    local username="${1}"
    local extra_days="${2}"

    if ! user_exists "$username"; then
        bnx_error "User '$username' not found"
        return 1
    fi

    local user_file="${BNX_USER_DIR}/${username}"
    local current_epoch
    current_epoch=$(grep "^EXPIRY_EPOCH=" "$user_file" | cut -d= -f2)

    if [[ -z "$current_epoch" ]] || (( current_epoch < $(date +%s) )); then
        new_epoch=$(($(date +%s) + (extra_days * 86400)))
    else
        new_epoch=$(( current_epoch + (extra_days * 86400) ))
    fi

    sed -i "s/^EXPIRY_EPOCH=.*/EXPIRY_EPOCH=${new_epoch}/" "$user_file"

    log_event "USER_EXTEND" "Extended user ${username} by ${extra_days} days"
    bnx_success "User '$username' extended by ${extra_days} days"
}

# Ban/unban user
user_ban() {
    local username="${1}"
    if ! user_exists "$username"; then
        bnx_error "User '$username' not found"
        return 1
    fi
    local user_file="${BNX_USER_DIR}/${username}"
    sed -i "s/^STATUS=.*/STATUS=banned/" "$user_file"
    log_event "USER_BAN" "Banned user: ${username}"
    bnx_success "User '$username' has been banned"
}

user_unban() {
    local username="${1}"
    if ! user_exists "$username"; then
        bnx_error "User '$username' not found"
        return 1
    fi
    local user_file="${BNX_USER_DIR}/${username}"
    sed -i "s/^STATUS=.*/STATUS=active/" "$user_file"
    log_event "USER_UNBAN" "Unbanned user: ${username}"
    bnx_success "User '$username' has been unbanned"
}

# Check if user is active and not expired
user_is_active() {
    local username="${1}"
    local user_file="${BNX_USER_DIR}/${username}"

    if [[ ! -f "$user_file" ]]; then
        return 1
    fi

    local status expiry_epoch
    status=$(grep "^STATUS=" "$user_file" | cut -d= -f2)
    expiry_epoch=$(grep "^EXPIRY_EPOCH=" "$user_file" | cut -d= -f2)

    [[ "$status" == "active" && "$expiry_epoch" -gt $(date +%s) ]]
}

# Get user expiry as human-readable
user_expiry_str() {
    local username="${1}"
    local epoch
    epoch=$(user_get "$username" EXPIRY_EPOCH)
    if [[ -n "$epoch" ]]; then
        date -d "@$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null || \
            date -r "$epoch" '+%Y-%m-%d %H:%M' 2>/dev/null
    fi
}

# Get remaining days
user_remaining_days() {
    local username="${1}"
    local epoch
    epoch=$(user_get "$username" EXPIRY_EPOCH)
    if [[ -n "$epoch" ]]; then
        local remaining=$(( (epoch - $(date +%s)) / 86400 ))
        echo "$remaining"
    fi
}

# ============================================================
# User Listing & Display
# ============================================================

# List all users
user_list_all() {
    if [[ ! -f "$BNX_USER_DB" ]] || [[ ! -s "$BNX_USER_DB" ]]; then
        bnx_info "No users found"
        return 0
    fi

    echo ""
    printf "  ${BNX_BOLD}${BNX_CYAN}%-16s %-36s %-12s %-8s %-10s${BNX_RESET}\n" \
        "USERNAME" "UUID" "EXPIRY" "STATUS" "QUOTA"
    printf "  ${BNX_DIM}%-16s %-36s %-12s %-8s %-10s${BNX_RESET}\n" \
        "───────────────" "────────────────────────────────────" "────────────" "────────" "──────────"

    while IFS='|' read -r username uuid password created_at created_epoch expiry_epoch quota status last_active; do
        local expiry_str
        expiry_str=$(date -d "@$expiry_epoch" '+%Y-%m-%d' 2>/dev/null || date -r "$expiry_epoch" '+%Y-%m-%d' 2>/dev/null)

        local status_color
        case "$status" in
            active)
                local now epoch_int
                now=$(date +%s)
                epoch_int="${expiry_epoch}"
                if (( epoch_int > now )); then
                    status_color="${BNX_GREEN}● active${BNX_RESET}"
                else
                    status_color="${BNX_RED}● expired${BNX_RESET}"
                fi
                ;;
            banned)  status_color="${BNX_RED}● banned${BNX_RESET}" ;;
            *)       status_color="${BNX_YELLOW}● ${status}${BNX_RESET}" ;;
        esac

        printf "  ${BNX_WHITE}%-16s${BNX_RESET} ${BNX_DIM}%-36s${BNX_RESET} ${BNX_GRAY}%-12s${BNX_RESET} %-40b ${BNX_GRAY}%-10s${BNX_RESET}\n" \
            "$username" "$uuid" "$expiry_str" "$status_color" "$quota"
    done < "$BNX_USER_DB"
    echo ""
}

# Count users
user_count() {
    if [[ -f "$BNX_USER_DB" ]]; then
        wc -l < "$BNX_USER_DB" 2>/dev/null | tr -d ' '
    else
        echo "0"
    fi
}

# Get active user count
user_count_active() {
    local count=0
    local now=$(date +%s)
    while IFS='|' read -r username uuid password created_at created_epoch expiry_epoch quota status last_active; do
        if [[ "$status" == "active" ]] && (( expiry_epoch > now )); then
            ((count++))
        fi
    done < "$BNX_USER_DB" 2>/dev/null
    echo "$count"
}

# ============================================================
# SSH User Management
# ============================================================

ssh_user_create() {
    local username="${1}"
    local password="${2:-}"

    if [[ -z "$password" ]]; then
        password=$(user_get "$username" PASSWORD)
    fi

    if id "$username" &>/dev/null; then
        bnx_info "SSH user '$username' already exists"
        return 0
    fi

    # Create system user with restricted shell
    useradd -m -s /bin/bash "$username" 2>/dev/null || \
        useradd -m -s /usr/sbin/nologin "$username" 2>/dev/null

    echo "${username}:${password}" | chpasswd
    usermod -aG www-data "$username" 2>/dev/null

    bnx_success "SSH user '$username' created"
}

ssh_user_delete() {
    local username="${1}"
    if id "$username" &>/dev/null; then
        userdel -r "$username" 2>/dev/null
        bnx_success "SSH user '$username' removed"
    fi
}

# ============================================================
# Logging
# ============================================================

log_event() {
    local event_type="${1}"
    local message="${2}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${event_type}] ${message}" >> "$BNX_LOG_FILE"
}

get_log_entries() {
    local count="${1:-20}"
    tail -n "$count" "$BNX_LOG_FILE" 2>/dev/null
}
