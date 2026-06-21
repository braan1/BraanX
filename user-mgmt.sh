#!/bin/bash
# ==============================================================================
# BraanX VPN - User Management Library
# ==============================================================================
# Shell-side user management functions used by the TUI menu and callable
# by the Telegram bot via subprocess.
# ==============================================================================

CONF_PATH="/etc/braanx/braanx.conf"
DB_PATH="/etc/braanx/db/braanx.db"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
LOG_PATH="/etc/braanx/log/braanx.log"
ADMIN_FILE="/etc/braanx/bot/admins.txt"
BOT_LOG="/etc/braanx/log/bot.log"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
OVPN_DIR="/etc/openvpn/server"

# --------------- Helpers ---------------

log_msg() {
    local level="$1"
    shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" >> "$LOG_PATH"
}

db_query() {
    local sql="$1"
    sqlite3 "$DB_PATH" "$sql"
}

db_escape() {
    echo "$1" | sed "s/'/''/g"
}

generate_password() {
    tr -dc 'a-zA-Z0-9' < /dev/urandom 2>/dev/null | head -c 12
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())"
}

random_username_prefix() {
    tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 6
}

calc_expiry_date() {
    local days="$1"
    date -d "+${days} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
        date -v+${days}d '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

calc_expiry_date_short() {
    local days="$1"
    date -d "+${days} days" '+%Y-%m-%d' 2>/dev/null || \
        date -v+${days}d '+%Y-%m-%d' 2>/dev/null
}

get_server_ip() {
    curl -s4 ifconfig.me 2>/dev/null || \
        hostname -I 2>/dev/null | awk '{print $1}' || \
        echo "N/A"
}

get_domain() {
    if [ -f "$CONF_PATH" ]; then
        grep -E '^DOMAIN=' "$CONF_PATH" 2>/dev/null | head -1 | cut -d'=' -f2
    fi
    if [ -z "$(get_domain 2>/dev/null)" ]; then
        get_server_ip
    fi
}

# Send Telegram notification via bot
send_telegram_notify() {
    local text="$1"
    if [ ! -f "$CONF_PATH" ] || [ ! -f "$ADMIN_FILE" ]; then
        return
    fi

    local token
    token=$(grep '^TELEGRAM_BOT_TOKEN=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    [ -z "$token" ] && return

    while IFS= read -r chat_id; do
        chat_id=$(echo "$chat_id" | tr -d '[:space:]')
        [ -z "$chat_id" ] && continue
        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="$text" \
            -d parse_mode="HTML" \
            >/dev/null 2>&1
    done < "$ADMIN_FILE"
}

# --------------- Database Init ---------------

init_db() {
    mkdir -p "$(dirname "$DB_PATH")"
    sqlite3 "$DB_PATH" <<'EOSQL'
CREATE TABLE IF NOT EXISTS accounts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    password TEXT,
    uuid TEXT UNIQUE,
    protocol TEXT NOT NULL,
    expiry TEXT NOT NULL,
    data_limit INTEGER DEFAULT 0,
    data_used INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now')),
    last_active TEXT
);
CREATE TABLE IF NOT EXISTS bandwidth_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id INTEGER,
    username TEXT,
    bytes_in INTEGER DEFAULT 0,
    bytes_out INTEGER DEFAULT 0,
    timestamp TEXT DEFAULT (datetime('now')),
    FOREIGN KEY(account_id) REFERENCES accounts(id)
);
CREATE TABLE IF NOT EXISTS bot_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    telegram_id INTEGER UNIQUE NOT NULL,
    username TEXT,
    is_admin INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);
EOSQL
    log_msg "INFO" "Database initialised at $DB_PATH"
}

# --------------- Account Creation ---------------

# Unified entry point: create_account <protocol> <username> <password> <days>
create_account() {
    local protocol="$1"
    local username="$2"
    local password="$3"
    local days="$4"

    case "$protocol" in
        ssh|SSH)
            create_ssh_user "$username" "$password" "$days"
            ;;
        vless|VLESS|vmess|VMess|trojan|Trojan)
            create_xray_user "$username" "$protocol" "$days"
            ;;
        openvpn|OpenVPN)
            create_openvpn_user "$username" "$days"
            ;;
        *)
            echo "ERROR: Unknown protocol '$protocol'"
            return 1
            ;;
    esac
}

# Create SSH system user
# Usage: create_ssh_user <username> <password> <days>
create_ssh_user() {
    local username="$1"
    local password="$2"
    local days="$3"
    local expiry
    local expiry_short

    expiry=$(calc_expiry_date "$days")
    expiry_short=$(calc_expiry_date_short "$days")

    # Check if user already exists
    if id "$username" &>/dev/null; then
        echo "ERROR: User '$username' already exists on the system."
        return 1
    fi

    # Check DB
    local db_check
    db_check=$(db_query "SELECT COUNT(*) FROM accounts WHERE username='$(db_escape "$username")'")
    if [ "$db_check" -gt 0 ]; then
        echo "ERROR: Username '$username' already exists in database."
        return 1
    fi

    # Create the system user (no home dir, bash shell)
    useradd -M -s /bin/bash "$username" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create system user '$username'."
        return 1
    fi

    # Set password
    echo "${username}:${password}" | chpasswd 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to set password for '$username'."
        userdel -r "$username" 2>/dev/null
        return 1
    fi

    # Set account expiry via chage
    chage -E "$expiry_short" "$username" 2>/dev/null

    # Create a restricted shell wrapper if dropbear is used
    if command -v dropbear &>/dev/null; then
        echo "${username}:${password}" >> /etc/dropbear/passwd 2>/dev/null
    fi

    # Insert into database
    db_query "INSERT INTO accounts (username, password, uuid, protocol, expiry, data_limit, is_active)
              VALUES ('$(db_escape "$username")', '$(db_escape "$password")', '', 'SSH', '$expiry', 0, 1)"

    log_msg "INFO" "SSH account created: $username ($days days)"
    echo "SSH account '$username' created. Expiry: $expiry_short"

    # Send Telegram notification
    send_telegram_notify "<b>Account Created</b>&#10;User: <code>$username</code>&#10;Protocol: SSH&#10;Expiry: $expiry_short"
}

# Create XRay protocol user (VLESS, VMess, Trojan)
# Usage: create_xray_user <username> <protocol> <days>
create_xray_user() {
    local username="$1"
    local protocol="$2"
    local days="$3"
    local uuid
    local password
    local expiry

    uuid=$(generate_uuid)
    expiry=$(calc_expiry_date "$days")

    # For Trojan, use a random password instead of UUID
    if [ "$protocol" = "Trojan" ] || [ "$protocol" = "trojan" ]; then
        password=$(generate_password)
    else
        password="$uuid"
    fi

    # Update XRay JSON config
    if [ -f "$XRAY_CONFIG" ]; then
        local proto_lower
        proto_lower=$(echo "$protocol" | tr '[:upper:]' '[:lower:]')

        python3 -c "
import json, sys
config_file = '$XRAY_CONFIG'
uuid_val = '$uuid'
username_val = '$username'
password_val = '$password'
protocol_val = '$proto_lower'

try:
    with open(config_file, 'r') as f:
        cfg = json.load(f)

    added = False
    for inbound in cfg.get('inbounds', []):
        if inbound.get('protocol', '').lower() == protocol_val:
            if 'settings' not in inbound:
                inbound['settings'] = {}
            if 'clients' not in inbound['settings']:
                inbound['settings']['clients'] = []
            client = {'id': uuid_val, 'email': username_val}
            if protocol_val == 'trojan':
                client['password'] = password_val
            inbound['settings']['clients'].append(client)
            added = True
            break

    if added:
        with open(config_file, 'w') as f:
            json.dump(cfg, f, indent=2)
        print('XRAY_CONFIG_UPDATED')
    else:
        print('PROTOCOL_NOT_FOUND')
except Exception as e:
    print('ERROR: ' + str(e))
" 2>/dev/null

        # Restart xray if config was updated
        systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null
    fi

    # Insert into database
    db_query "INSERT INTO accounts (username, password, uuid, protocol, expiry, data_limit, is_active)
              VALUES ('$(db_escape "$username")', '$(db_escape "$password")', '$uuid', '$protocol', '$expiry', 0, 1)"

    log_msg "INFO" "$protocol account created: $username ($days days) uuid=$uuid"

    # Generate connection link
    local domain
    local port
    local ws_path
    local security
    local link

    domain=$(get_domain)
    port=$(grep '^XRAY_PORT=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    port=${port:-443}
    ws_path=$(grep '^XRAY_WS_PATH=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    ws_path=${ws_path:-/}
    security=$(grep '^XRAY_SECURITY=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    security=${security:-tls}

    case "$protocol" in
        VLESS|vless)
            link="vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=ws&path=${ws_path}#${username}"
            ;;
        VMess|vmess)
            # VMess link is base64-encoded JSON - generate via python3
            link=$(python3 -c "
import json, base64
vmess = {
    'v': '2', 'ps': '$username', 'add': '$domain', 'port': '$port',
    'id': '$uuid', 'aid': '0', 'net': 'ws', 'type': 'none',
    'host': '$domain', 'path': '$ws_path', 'tls': '$security'
}
print('vmess://' + base64.b64encode(json.dumps(vmess).encode()).decode())
" 2>/dev/null)
            ;;
        Trojan|trojan)
            link="trojan://${password}@${domain}:${port}?type=ws&path=${ws_path}#${username}"
            ;;
        *)
            link="N/A"
            ;;
    esac

    echo "$protocol account '$username' created. Expiry: $(calc_expiry_date_short "$days")"
    echo "Connection link: $link"

    # Send Telegram notification
    send_telegram_notify "<b>Account Created</b>&#10;User: <code>$username</code>&#10;Protocol: $protocol&#10;Expiry: $(calc_expiry_date_short "$days")"
}

# Create OpenVPN user
# Usage: create_openvpn_user <username> <days>
create_openvpn_user() {
    local username="$1"
    local days="$2"
    local password
    local expiry

    password=$(generate_password)
    expiry=$(calc_expiry_date "$days")

    # Generate client certificate via easy-rsa
    if [ -d "$EASY_RSA_DIR" ]; then
        cd "$EASY_RSA_DIR"
        ./easyrsa build-client-full "$username" nopass 2>/dev/null

        # Build .ovpn profile
        local ca_crt
        local client_crt
        local client_key
        local tls_key
        local server_ip

        ca_crt="$EASY_RSA_DIR/pki/ca.crt"
        client_crt="$EASY_RSA_DIR/pki/issued/${username}.crt"
        client_key="$EASY_RSA_DIR/pki/private/${username}.key"
        tls_key="$OVPN_DIR/ta.key"
        server_ip=$(get_server_ip)

        if [ -f "$client_crt" ] && [ -f "$client_key" ]; then
            local ovpn_file="/etc/openvpn/client/${username}.ovpn"
            mkdir -p /etc/openvpn/client

            cat > "$ovpn_file" << OVPNEOF
client
dev tun
proto udp
remote ${server_ip} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-GCM
auth SHA256
key-direction 1
verb 3
OVPNEOF

            # Embed CA cert
            echo "" >> "$ovpn_file"
            echo "<ca>" >> "$ovpn_file"
            cat "$ca_crt" >> "$ovpn_file" 2>/dev/null
            echo "</ca>" >> "$ovpn_file"

            # Embed client cert
            echo "<cert>" >> "$ovpn_file"
            cat "$client_crt" >> "$ovpn_file" 2>/dev/null
            echo "</cert>" >> "$ovpn_file"

            # Embed client key
            echo "<key>" >> "$ovpn_file"
            cat "$client_key" >> "$ovpn_file" 2>/dev/null
            echo "</key>" >> "$ovpn_file"

            # Embed TLS key if available
            if [ -f "$tls_key" ]; then
                echo "<tls-auth>" >> "$ovpn_file"
                cat "$tls_key" >> "$ovpn_file" 2>/dev/null
                echo "</tls-auth>" >> "$ovpn_file"
            fi

            echo "OpenVPN profile: $ovpn_file"
        else
            echo "WARNING: Certificate files not found for $username"
        fi
    else
        echo "WARNING: Easy-RSA directory not found at $EASY_RSA_DIR"
    fi

    # Insert into database
    db_query "INSERT INTO accounts (username, password, uuid, protocol, expiry, data_limit, is_active)
              VALUES ('$(db_escape "$username")', '$(db_escape "$password")', '', 'OpenVPN', '$expiry', 0, 1)"

    log_msg "INFO" "OpenVPN account created: $username ($days days)"
    echo "OpenVPN account '$username' created. Expiry: $(calc_expiry_date_short "$days")"

    send_telegram_notify "<b>Account Created</b>&#10;User: <code>$username</code>&#10;Protocol: OpenVPN&#10;Expiry: $(calc_expiry_date_short "$days")"
}

# --------------- Account Deletion ---------------

# Unified delete: delete_account <username>
delete_account() {
    local username="$1"
    [ -z "$username" ] && { echo "ERROR: Username required."; return 1; }

    local protocol
    protocol=$(db_query "SELECT protocol FROM accounts WHERE username='$(db_escape "$username")'" | head -1)

    case "$protocol" in
        SSH|ssh)
            delete_ssh_user "$username"
            ;;
        VLESS|vless|VMess|vmess|Trojan|trojan)
            delete_xray_user "$username"
            ;;
        OpenVPN|openvpn)
            delete_openvpn_user "$username"
            ;;
        *)
            echo "WARNING: Unknown protocol '$protocol', removing from DB only."
            db_query "DELETE FROM accounts WHERE username='$(db_escape "$username")'"
            ;;
    esac
}

# Delete SSH system user
delete_ssh_user() {
    local username="$1"

    # Lock and remove the user
    usermod -L "$username" 2>/dev/null
    userdel -r "$username" 2>/dev/null

    # Remove from dropbear if present
    if [ -f /etc/dropbear/passwd ]; then
        sed -i "/^${username}:/d" /etc/dropbear/passwd 2>/dev/null
    fi

    # Remove from database
    db_query "DELETE FROM accounts WHERE username='$(db_escape "$username")'"

    log_msg "INFO" "SSH account deleted: $username"
    echo "SSH account '$username' deleted."

    send_telegram_notify "<b>Account Deleted</b>&#10;User: <code>$username</code>&#10;Protocol: SSH"
}

# Delete XRay user
delete_xray_user() {
    local username="$1"

    local acc_uuid
    acc_uuid=$(db_query "SELECT uuid FROM accounts WHERE username='$(db_escape "$username")'" | head -1)

    if [ -n "$acc_uuid" ] && [ -f "$XRAY_CONFIG" ]; then
        # Remove the client from XRay config using python3
        python3 -c "
import json
config_file = '$XRAY_CONFIG'
uuid_val = '$acc_uuid'
try:
    with open(config_file, 'r') as f:
        cfg = json.load(f)
    modified = False
    for inbound in cfg.get('inbounds', []):
        clients = inbound.get('settings', {}).get('clients', [])
        orig = len(clients)
        inbound['settings']['clients'] = [c for c in clients if c.get('id') != uuid_val]
        if len(inbound['settings']['clients']) < orig:
            modified = True
    if modified:
        with open(config_file, 'w') as f:
            json.dump(cfg, f, indent=2)
except Exception as e:
    print('ERROR: ' + str(e))
" 2>/dev/null

        systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null
    fi

    # Remove from database
    db_query "DELETE FROM accounts WHERE username='$(db_escape "$username")'"

    log_msg "INFO" "XRay account deleted: $username"
    echo "XRay account '$username' deleted."

    send_telegram_notify "<b>Account Deleted</b>&#10;User: <code>$username</code>&#10;Protocol: XRay"
}

# Delete OpenVPN user
delete_openvpn_user() {
    local username="$1"

    # Revoke certificate
    if [ -d "$EASY_RSA_DIR" ]; then
        cd "$EASY_RSA_DIR"
        ./easyrsa revoke "$username" 2>/dev/null
        ./easyrsa gen-crl 2>/dev/null
    fi

    # Remove config file
    rm -f "/etc/openvpn/client/${username}.ovpn"

    # Remove from database
    db_query "DELETE FROM accounts WHERE username='$(db_escape "$username")'"

    log_msg "INFO" "OpenVPN account deleted: $username"
    echo "OpenVPN account '$username' deleted."
}

# --------------- Account Renewal ---------------

# Renew account: renew_account <username> <days>
renew_account() {
    local username="$1"
    local days="$2"
    local new_expiry
    local new_expiry_short
    local protocol

    [ -z "$username" ] && { echo "ERROR: Username required."; return 1; }
    [ -z "$days" ] && days="30"

    new_expiry=$(calc_expiry_date "$days")
    new_expiry_short=$(calc_expiry_date_short "$days")
    protocol=$(db_query "SELECT protocol FROM accounts WHERE username='$(db_escape "$username")'" | head -1)

    # Update database
    db_query "UPDATE accounts SET expiry='$new_expiry', is_active=1 WHERE username='$(db_escape "$username")'"

    # Update system user expiry for SSH
    if [ "$protocol" = "SSH" ]; then
        if id "$username" &>/dev/null; then
            chage -E "$new_expiry_short" "$username" 2>/dev/null
            usermod -U "$username" 2>/dev/null
        fi
    fi

    log_msg "INFO" "Account renewed: $username +$days days (new expiry: $new_expiry_short)"
    echo "Account '$username' renewed. New expiry: $new_expiry_short"

    send_telegram_notify "<b>Account Renewed</b>&#10;User: <code>$username</code>&#10;New Expiry: $new_expiry_short"
}

# --------------- List Accounts ---------------

# List all accounts: list_accounts
list_accounts() {
    local count
    count=$(db_query "SELECT COUNT(*) FROM accounts")

    if [ "$count" -eq 0 ]; then
        echo "No accounts found."
        return
    fi

    printf "%-4s %-16s %-8s %-10s %-12s %-20s %s\n" \
        "#" "Username" "Protocol" "Status" "Expiry" "Data Used/Limit" "Last Active"
    printf "%s\n" "--------------------------------------------------------------------------------------------"

    db_query "SELECT * FROM accounts ORDER BY id DESC" | while IFS='|' read -r id username password uuid protocol expiry data_limit data_used is_active created_at last_active; do
        [ -z "$id" ] && continue

        # Determine status
        local status
        local now_ts
        now_ts=$(date '+%Y-%m-%d %H:%M:%S')

        if [ "$is_active" = "0" ]; then
            status="INACTIVE"
        elif [[ "$expiry" < "$now_ts" ]]; then
            status="EXPIRED"
        else
            # Check if expiring within 3 days
            local exp_epoch
            local now_epoch
            exp_epoch=$(date -d "$expiry" '+%s' 2>/dev/null || echo 0)
            now_epoch=$(date '+%s')
            local diff_days
            diff_days=$(( (exp_epoch - now_epoch) / 86400 ))
            if [ "$diff_days" -le 3 ]; then
                status="EXPIRING"
            else
                status="ACTIVE"
            fi
        fi

        # Format data usage
        local data_str
        if [ "$data_limit" -gt 0 ]; then
            data_str="$(format_bytes "$data_used")/$(format_bytes "$data_limit")"
        else
            data_str="$(format_bytes "$data_used")/Unlimited"
        fi

        local la="${last_active:-Never}"

        printf "%-4s %-16s %-8s %-10s %-12s %-20s %s\n" \
            "$id" "$username" "$protocol" "$status" "${expiry%% *}" "$data_str" "$la"
    done
}

# --------------- Trial Account ---------------

# Create trial account: trial_account
trial_account() {
    local username="trial-$(random_username_prefix)"
    local password
    password=$(generate_password)

    create_ssh_user "$username" "$password" 1

    # Set data limit to 500 MB
    db_query "UPDATE accounts SET data_limit=524288000 WHERE username='$(db_escape "$username")'"

    log_msg "INFO" "Trial account created: $username"
    echo "Trial account: $username / $password (1 day, 500MB limit)"
}

# --------------- Check Expired Accounts ---------------

# Check and deactivate expired accounts
check_expired() {
    local expired_list
    expired_list=$(db_query "SELECT username, protocol FROM accounts WHERE is_active=1 AND expiry < datetime('now')")

    if [ -z "$expired_list" ]; then
        return
    fi

    echo "$expired_list" | while IFS='|' read -r username protocol; do
        [ -z "$username" ] && continue

        # Deactivate in database
        db_query "UPDATE accounts SET is_active=0 WHERE username='$(db_escape "$username")'"

        # Lock SSH user
        if [ "$protocol" = "SSH" ]; then
            usermod -L "$username" 2>/dev/null
        fi

        log_msg "INFO" "Account expired: $username ($protocol)"
    done

    # Notify via Telegram
    local count
    count=$(echo "$expired_list" | wc -l)
    send_telegram_notify "<b>Expired Accounts</b>&#10;$count account(s) have expired and been deactivated."

    echo "$count expired account(s) deactivated."
}

# --------------- Show Account Info ---------------

# Show detailed info for an account: show_account_info <username>
show_account_info() {
    local username="$1"
    [ -z "$username" ] && { echo "ERROR: Username required."; return 1; }

    local row
    row=$(db_query "SELECT * FROM accounts WHERE username='$(db_escape "$username")'" | head -1)
    [ -z "$row" ] && { echo "Account '$username' not found."; return 1; }

    local id pw uuid proto expiry dlimit dused active created last_active
    IFS='|' read -r id pw uuid proto expiry dlimit dused active created last_active <<< "$row"

    echo "=========================================="
    echo "  Account Details: $username"
    echo "=========================================="
    echo "  ID:        $id"
    echo "  Username:  $username"
    echo "  Protocol:  $proto"
    echo "  UUID:      ${uuid:-N/A}"
    echo "  Expiry:    $expiry"
    echo "  Status:    $([ "$active" = "1" ] && echo "Active" || echo "Inactive")"
    echo "  Created:   $created"
    echo "  Last Seen: ${last_active:-Never}"
    echo "  Data:      $(format_bytes "$dused") / $([ "$dlimit" -gt 0 ] && format_bytes "$dlimit" || echo "Unlimited")"
    echo "=========================================="
    echo ""

    # Show connection info
    generate_connection_link "$username" "$proto" "$uuid" "$pw"
}

# --------------- Generate Connection Link ---------------

# Generate protocol connection links
# Usage: generate_connection_link <username> <protocol> [uuid] [password]
generate_connection_link() {
    local username="$1"
    local protocol="$2"
    local uuid_val="$3"
    local password="$4"

    local domain
    local port
    local ws_path
    local security
    local server_ip

    domain=$(get_domain)
    port=$(grep '^XRAY_PORT=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    port=${port:-443}
    ws_path=$(grep '^XRAY_WS_PATH=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    ws_path=${ws_path:-/}
    security=$(grep '^XRAY_SECURITY=' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2)
    security=${security:-tls}
    server_ip=$(get_server_ip)

    case "$protocol" in
        SSH|ssh)
            echo "Connection: ssh ${username}@${server_ip}"
            ;;
        VLESS|vless)
            echo "VLESS Link:"
            echo "vless://${uuid_val}@${domain}:${port}?encryption=none&security=${security}&type=ws&path=${ws_path}#${username}"
            ;;
        VMess|vmess)
            echo "VMess Link:"
            python3 -c "
import json, base64
vmess = {
    'v': '2', 'ps': '$username', 'add': '$domain', 'port': '$port',
    'id': '$uuid_val', 'aid': '0', 'net': 'ws', 'type': 'none',
    'host': '$domain', 'path': '$ws_path', 'tls': '$security'
}
print('vmess://' + base64.b64encode(json.dumps(vmess).encode()).decode())
" 2>/dev/null
            ;;
        Trojan|trojan)
            echo "Trojan Link:"
            echo "trojan://${password}@${domain}:${port}?type=ws&path=${ws_path}#${username}"
            ;;
        OpenVPN|openvpn)
            local ovpn_file="/etc/openvpn/client/${username}.ovpn"
            if [ -f "$ovpn_file" ]; then
                echo "OpenVPN Config: $ovpn_file"
            else
                echo "OpenVPN config file not found."
            fi
            ;;
        *)
            echo "Unknown protocol: $protocol"
            ;;
    esac
}

# --------------- Format Bytes ---------------

format_bytes() {
    local num="$1"
    [ -z "$num" ] && num=0

    if [ "$num" -ge 1073741824 ]; then
        echo "$(echo "scale=1; $num / 1073741824" | bc) GB"
    elif [ "$num" -ge 1048576 ]; then
        echo "$(echo "scale=1; $num / 1048576" | bc) MB"
    elif [ "$num" -ge 1024 ]; then
        echo "$(echo "scale=1; $num / 1024" | bc) KB"
    else
        echo "${num} B"
    fi
}

# --------------- Bandwidth Logging ---------------

# Log bandwidth for an account
# Usage: log_bandwidth <username> <bytes_in> <bytes_out>
log_bandwidth() {
    local username="$1"
    local bytes_in="$2"
    local bytes_out="$3"

    local account_id
    account_id=$(db_query "SELECT id FROM accounts WHERE username='$(db_escape "$username")'" | head -1)

    if [ -n "$account_id" ]; then
        db_query "INSERT INTO bandwidth_log (account_id, username, bytes_in, bytes_out)
                  VALUES ('$account_id', '$(db_escape "$username")', $bytes_in, $bytes_out)"

        # Update cumulative data_used
        db_query "UPDATE accounts SET data_used = data_used + ($bytes_in + $bytes_out),
                  last_active = datetime('now') WHERE username='$(db_escape "$username")'"
    fi
}

# --------------- Main Entry (source-able library) ---------------

# If executed directly (not sourced), run the CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        create)
            [ -z "$4" ] && { echo "Usage: $0 create <protocol> <username> <password> <days>"; exit 1; }
            init_db
            create_account "$2" "$3" "$4" "$5"
            ;;
        delete)
            [ -z "$2" ] && { echo "Usage: $0 delete <username>"; exit 1; }
            delete_account "$2"
            ;;
        renew)
            [ -z "$3" ] && { echo "Usage: $0 renew <username> <days>"; exit 1; }
            renew_account "$2" "$3"
            ;;
        list)
            list_accounts
            ;;
        trial)
            init_db
            trial_account
            ;;
        info)
            [ -z "$2" ] && { echo "Usage: $0 info <username>"; exit 1; }
            show_account_info "$2"
            ;;
        check-expired)
            check_expired
            ;;
        link)
            [ -z "$2" ] && { echo "Usage: $0 link <username>"; exit 1; }
            local _row _proto _uuid _pw
            _row=$(db_query "SELECT protocol, uuid, password FROM accounts WHERE username='$(db_escape "$2")'" | head -1)
            IFS='|' read -r _proto _uuid _pw <<< "$_row"
            generate_connection_link "$2" "$_proto" "$_uuid" "$_pw"
            ;;
        init)
            init_db
            echo "Database initialised."
            ;;
        *)
            echo "BraanX User Management Library"
            echo ""
            echo "Usage: $0 <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  init                          Initialise database"
            echo "  create <proto> <user> <pw> <days>  Create account"
            echo "  delete <user>                 Delete account"
            echo "  renew <user> <days>           Renew account"
            echo "  list                          List all accounts"
            echo "  trial                         Create trial account"
            echo "  info <user>                   Show account details"
            echo "  link <user>                   Generate connection link"
            echo "  check-expired                 Deactivate expired accounts"
            echo ""
            echo "Protocols: SSH, VLESS, VMess, Trojan, OpenVPN"
            ;;
    esac
fi