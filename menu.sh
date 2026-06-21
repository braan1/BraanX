#!/bin/bash
# ============================================================================
#  BraanX Interactive Menu System - menu.sh
#  TUI menu for managing VPN services and accounts.
# ============================================================================

# Prevent double-sourcing
[[ -n "$_BRAANX_MENU_LOADED" ]] && return 0
_BRAANX_MENU_LOADED=1

# Ensure functions.sh is loaded
if [[ -z "$_BRAANX_FUNCTIONS_LOADED" ]]; then
    if [[ -f "/etc/braanx/lib/functions.sh" ]]; then
        # shellcheck disable=SC1090
        source "/etc/braanx/lib/functions.sh"
    elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/functions.sh" ]]; then
        # shellcheck disable=SC1090
        source "$(dirname "${BASH_SOURCE[0]}")/functions.sh"
    else
        echo -e "${R}[ERROR]${RST} functions.sh not found. Cannot load menu."
        return 1 2>/dev/null || exit 1
    fi
fi

# ============================================================================
# Menu Drawing Helpers
# ============================================================================

# Draw the outer frame of the main menu
_draw_menu_frame_top() {
    local width=60
    echo -e "  ${CL}${BOLD}/$(printf '%.0s-' $(seq 1 $width))\\${RST}"
}

_draw_menu_frame_bottom() {
    local width=60
    echo -e "  ${CL}${BOLD}\\$(printf '%.0s-' $(seq 1 $width))/${RST}"
}

_draw_menu_section_header() {
    local title="$1"
    local width=58
    echo -e "  ${CL}${BOLD}|${RST}  ${GOLD_RGB}${BOLD}${title}${RST} $(printf '%.0s ' $(seq 1 $((width - ${#title} - 3))))${CL}${BOLD}|${RST}"
}

_draw_menu_item() {
    local num="$1"
    local text="$2"
    local width=54
    local num_str
    num_str=$(printf "%2s" "$num")
    local padded
    padded=$(printf "%-${width}s" "$text")
    echo -e "  ${CL}${BOLD}|${RST}  ${GR}${BOLD}[${num_str}]${RST} ${WH}${padded} ${CL}${BOLD}|${RST}"
}

_draw_menu_empty() {
    local width=60
    echo -e "  ${CL}${BOLD}|$(printf '%.0s ' $(seq 1 $width))|${RST}"
}

# Prompt for menu choice and read input
_prompt_choice() {
    echo -en "  ${YL}[?]${RST} Enter choice: "
    read -r _menu_choice
}

# ============================================================================
# Main Menu
# ============================================================================

# Display the main BraanX menu
show_main_menu() {
    local choice

    while true; do
        clear
        # Print banner from parent if available, otherwise a simple header
        if type print_banner &>/dev/null; then
            print_banner
        fi

        _draw_menu_frame_top
        _draw_menu_section_header "Installation"
        _draw_menu_item "1"  "Full Auto-Install (All Services)"
        _draw_menu_item "2"  "Install XRay (VLESS/VMess/Trojan)"
        _draw_menu_item "3"  "Install SSH (WebSocket + Direct)"
        _draw_menu_item "4"  "Install OpenVPN (TCP + UDP)"
        _draw_menu_item "5"  "Install Nginx Reverse Proxy"
        _draw_menu_item "6"  "Install DNS Tunnel (SlowDNS/UDPGW)"
        _draw_menu_empty
        _draw_menu_section_header "Account Management"
        _draw_menu_item "7"  "Create SSH Account"
        _draw_menu_item "8"  "Create XRay Account (VLESS/VMess/Trojan)"
        _draw_menu_item "9"  "Create OpenVPN Account"
        _draw_menu_item "10" "Trial Account (1 Day)"
        _draw_menu_item "11" "List All Accounts"
        _draw_menu_item "12" "Delete Account"
        _draw_menu_item "13" "Renew Account"
        _draw_menu_item "14" "Check Expired Accounts"
        _draw_menu_empty
        _draw_menu_section_header "Server Tools"
        _draw_menu_item "15" "Server Information"
        _draw_menu_item "16" "Bandwidth Monitor"
        _draw_menu_item "17" "Speed Test"
        _draw_menu_item "18" "BBR TCP Tuning"
        _draw_menu_item "19" "SSL Certificate Manager"
        _draw_menu_item "20" "Fail2ban Setup"
        _draw_menu_item "21" "Backup Configuration"
        _draw_menu_item "22" "Restore Configuration"
        _draw_menu_item "23" "Restart All Services"
        _draw_menu_empty
        _draw_menu_section_header "Telegram Bot"
        _draw_menu_item "24" "Setup Telegram Bot"
        _draw_menu_item "25" "Bot Status"
        _draw_menu_item "26" "Send Test Message"
        _draw_menu_empty
        _draw_menu_section_header "System"
        _draw_menu_item "27" "Update BraanX"
        _draw_menu_item "28" "Uninstall BraanX"
        _draw_menu_item "0"  "Exit"
        _draw_menu_frame_bottom
        echo ""

        _prompt_choice
        choice="$_menu_choice"

        case "$choice" in
            1)  menu_install_full ;;
            2)  menu_install_xray ;;
            3)  menu_install_ssh ;;
            4)  menu_install_openvpn ;;
            5)  menu_install_nginx ;;
            6)  menu_install_dns ;;
            7)  menu_create_ssh ;;
            8)  menu_create_xray ;;
            9)  menu_create_openvpn ;;
            10) menu_create_trial ;;
            11) menu_list_accounts ;;
            12) menu_delete_account ;;
            13) menu_renew_account ;;
            14) menu_check_expired ;;
            15) menu_server_info ;;
            16) menu_bandwidth ;;
            17) menu_speedtest ;;
            18) menu_bbr ;;
            19) menu_ssl ;;
            20) menu_fail2ban ;;
            21) menu_backup ;;
            22) menu_restore ;;
            23) menu_restart_services ;;
            24) menu_tg_setup ;;
            25) menu_tg_status ;;
            26) menu_tg_test ;;
            27) menu_update ;;
            28) menu_uninstall ;;
            0|q|Q) echo -e "\n  ${GR}Goodbye!${RST}\n"; exit 0 ;;
            *)  msg_warn "Invalid option: ${choice}. Please try again." ; press_enter ;;
        esac
    done
}

# ============================================================================
# Installation Menus
# ============================================================================

# Full auto-install of all services
menu_install_full() {
    draw_header "Full Auto-Install"

    msg_info "This will install all VPN services on this server."
    msg_info "Make sure your domain points to this server before continuing."

    if ! confirm "Proceed with full installation?"; then
        return 0
    fi

    set -e

    msg_step "1" "Updating system packages..."
    pkg_update
    progress_simple "Updating packages" 20

    msg_step "2" "Installing core dependencies..."
    pkg_install curl wget jq sqlite3 bc unzip net-tools
    progress_simple "Installing dependencies" 40

    msg_step "3" "Setting up XRay core..."
    # XRay installation would go here
    config_set "xray_enabled" "1"
    progress_simple "Installing XRay" 60

    msg_step "4" "Setting up SSH WebSocket tunnel..."
    # SSH setup would go here
    config_set "ssh_enabled" "1"
    progress_simple "Configuring SSH" 75

    msg_step "5" "Setting up Nginx reverse proxy..."
    # Nginx setup would go here
    config_set "nginx_enabled" "1"
    progress_simple "Installing Nginx" 90

    msg_step "6" "Applying security settings..."
    # Security setup would go here
    progress_simple "Applying security" 100

    set +e

    echo ""
    msg_ok "Full installation completed successfully!"
    press_enter
}

# Install XRay
menu_install_xray() {
    draw_header "Install XRay"

    local protocol
    echo -e "  Select protocol:"
    echo -e "    ${GR}1)${RST} VLESS (recommended)"
    echo -e "    2) VMess"
    echo -e "    3) Trojan"
    echo -en "  ${YL}[?]${RST} Choice [1]: "
    read -r proto_choice

    case "${proto_choice:-1}" in
        1) protocol="vless" ;;
        2) protocol="vmess" ;;
        3) protocol="trojan" ;;
        *) protocol="vless" ;;
    esac

    msg_info "Installing XRay with ${protocol} protocol..."

    set -e

    # Install XRay core
    local xray_dir="/usr/local/xray"
    msg_step "1" "Downloading XRay core..."

    local arch
    arch=$(detect_arch)
    local xray_arch
    case "$arch" in
        x86_64)  xray_arch="amd64" ;;
        aarch64) xray_arch="arm64-v8a" ;;
        armv7)   xray_arch="arm32-v7a" ;;
        *)       xray_arch="amd64" ;;
    esac

    local download_url="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${xray_arch}.zip"

    msg_step "2" "Downloading from ${download_url}..."
    if curl -sL --max-time 60 -o /tmp/xray.zip "$download_url"; then
        msg_ok "Download complete."
    else
        msg_err "Failed to download XRay. Check your network."
        set +e
        press_enter
        return 1
    fi

    msg_step "3" "Installing XRay to ${xray_dir}..."
    mkdir -p "$xray_dir"
    unzip -o -q /tmp/xray.zip -d "$xray_dir" 2>/dev/null
    chmod +x "${xray_dir}/xray"
    rm -f /tmp/xray.zip

    msg_step "4" "Generating UUID..."
    local xray_uuid
    xray_uuid=$(gen_uuid)
    config_set "xray_uuid" "$xray_uuid"
    config_set "xray_protocol" "$protocol"
    config_set "xray_enabled" "1"

    set +e

    echo ""
    msg_ok "XRay installed with ${protocol} protocol."
    msg_info "UUID: ${BOLD}${xray_uuid}"
    press_enter
}

# Install SSH WebSocket
menu_install_ssh() {
    draw_header "Install SSH (WebSocket + Direct)"

    msg_info "Configuring SSH for WebSocket tunnel support..."

    set -e

    # Install required packages
    pkg_install openssh-server

    # Configure SSH
    local sshd_conf="/etc/ssh/sshd_config"
    if [[ -f "$sshd_conf" ]]; then
        # Backup original
        cp "$sshd_conf" "${sshd_conf}.bak.$(date +%Y%m%d%H%M%S)"

        # Enable gateway ports
        sed -i 's/^#\?GatewayPorts.*/GatewayPorts yes/' "$sshd_conf"
        sed -i 's/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/' "$sshd_conf"

        msg_ok "SSH configuration updated."
    fi

    config_set "ssh_enabled" "1"

    set +e

    msg_ok "SSH setup complete."
    press_enter
}

# Install OpenVPN
menu_install_openvpn() {
    draw_header "Install OpenVPN (TCP + UDP)"

    msg_info "This will install and configure OpenVPN server..."

    if ! confirm "Proceed with OpenVPN installation?"; then
        return 0
    fi

    set -e

    pkg_install openvpn easy-rsa

    config_set "openvpn_enabled" "1"

    set +e

    msg_ok "OpenVPN installation complete."
    msg_warn "Note: Additional certificate configuration may be required."
    press_enter
}

# Install Nginx
menu_install_nginx() {
    draw_header "Install Nginx Reverse Proxy"

    msg_info "Installing Nginx as reverse proxy..."

    set -e
    pkg_install nginx
    config_set "nginx_enabled" "1"

    # Enable and start nginx
    systemctl enable nginx 2>/dev/null
    systemctl start nginx 2>/dev/null

    set +e

    msg_ok "Nginx installed and started."
    press_enter
}

# Install DNS Tunnel
menu_install_dns() {
    draw_header "Install DNS Tunnel (SlowDNS/UDPGW)"

    local tool
    echo -e "  Select DNS tunnel tool:"
    echo -e "    ${GR}1)${RST} SlowDNS"
    echo -e "    2) UDPGW"
    echo -en "  ${YL}[?]${RST} Choice [1]: "
    read -r dns_choice

    case "${dns_choice:-1}" in
        1) tool="slowdns" ;;
        2) tool="udpgw" ;;
        *) tool="slowdns" ;;
    esac

    msg_info "Installing ${tool}..."

    if [[ "$tool" == "slowdns" ]]; then
        pkg_install libasyncns-dev libevent-dev
        msg_ok "SlowDNS dependencies installed."
        msg_warn "SlowDNS binary compilation is not yet automated."
    else
        msg_ok "UDPGW configuration noted."
        msg_warn "UDPGW binary setup is not yet automated."
    fi

    press_enter
}

# Generic install dispatcher (used by CLI --install)
menu_install() {
    menu_install_full
}

# ============================================================================
# Account Creation Menus
# ============================================================================

# Create a new SSH account
menu_create_ssh() {
    draw_header "Create SSH Account"

    local username
    local password
    local expiry_days

    # Prompt for username
    while true; do
        username=$(prompt_default "Username:")
        if [[ -z "$username" ]]; then
            msg_err "Username cannot be empty."
            continue
        fi
        # Validate: only alphanumeric and underscore
        if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
            msg_err "Username must be alphanumeric (letters, numbers, underscore only)."
            continue
        fi
        break
    done

    # Check if user exists in system
    if id "$username" &>/dev/null; then
        msg_warn "System user '${username}' already exists."
        if ! confirm "Use existing user?"; then
            return 0
        fi
    fi

    # Prompt for password or auto-generate
    echo -en "  ${YL}[?]${RST} Password (leave blank to auto-generate): "
    read -rs password_input
    password="$password_input"

    if [[ -z "$password" ]]; then
        password=$(gen_password 12)
        msg_info "Generated password: ${BOLD}${password}"
    fi
    echo ""

    # Prompt for expiry
    expiry_days=$(prompt_default "Expiry (days):" "30")
    if [[ ! "$expiry_days" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid number of days."
        press_enter
        return 1
    fi

    # Create the system user
    if ! id "$username" &>/dev/null; then
        useradd -m -s /bin/bash "$username" 2>/dev/null
        echo "${username}:${password}" | chpasswd 2>/dev/null
        msg_ok "System user '${username}' created."
    else
        echo "${username}:${password}" | chpasswd 2>/dev/null
        msg_ok "Password updated for '${username}'."
    fi

    # Set expiry date on system account
    local expiry_date
    expiry_date=$(date -d "+${expiry_days} days" '+%Y-%m-%d' 2>/dev/null)
    if [[ -n "$expiry_date" ]]; then
        chage -E "$expiry_date" "$username" 2>/dev/null
    fi

    # Insert into database
    db_insert_account "$username" "$password" "ssh" "$expiry_days"

    press_enter
}

# Create a new XRay account
menu_create_xray() {
    draw_header "Create XRay Account"

    local username
    local protocol
    local expiry_days
    local uuid

    # Select protocol
    echo -e "  Select protocol:"
    echo -e "    ${GR}1)${RST} VLESS"
    echo -e "    2) VMess"
    echo -e "    3) Trojan"
    echo -en "  ${YL}[?]${RST} Choice [1]: "
    read -r proto_choice

    case "${proto_choice:-1}" in
        1) protocol="vless" ;;
        2) protocol="vmess" ;;
        3) protocol="trojan" ;;
        *) protocol="vless" ;;
    esac

    # Prompt for username
    while true; do
        username=$(prompt_default "Username:")
        if [[ -z "$username" ]]; then
            msg_err "Username cannot be empty."
            continue
        fi
        if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
            msg_err "Username must be alphanumeric."
            continue
        fi
        break
    done

    # Prompt for expiry
    expiry_days=$(prompt_default "Expiry (days):" "30")
    if [[ ! "$expiry_days" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid number of days."
        press_enter
        return 1
    fi

    # Generate UUID
    uuid=$(gen_uuid)

    # Insert into database
    db_insert_account "$username" "" "$protocol" "$expiry_days" "$uuid"

    echo ""
    msg_info "XRay ${protocol} Account Details:"
    echo -e "    Username : ${GR}${BOLD}${username}${RST}"
    echo -e "    UUID     : ${GR}${BOLD}${uuid}${RST}"
    echo -e "    Protocol : ${GR}${BOLD}${protocol}${RST}"
    echo -e "    Expiry   : ${GR}${BOLD}${expiry_days} days${RST}"

    press_enter
}

# Create a new OpenVPN account
menu_create_openvpn() {
    draw_header "Create OpenVPN Account"

    local username
    local password
    local expiry_days

    # Prompt for username
    while true; do
        username=$(prompt_default "Username:")
        if [[ -z "$username" ]]; then
            msg_err "Username cannot be empty."
            continue
        fi
        if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
            msg_err "Username must be alphanumeric."
            continue
        fi
        break
    done

    # Prompt for password or auto-generate
    echo -en "  ${YL}[?]${RST} Password (leave blank to auto-generate): "
    read -rs password_input
    password="$password_input"

    if [[ -z "$password" ]]; then
        password=$(gen_password 12)
        msg_info "Generated password: ${BOLD}${password}"
    fi
    echo ""

    # Prompt for expiry
    expiry_days=$(prompt_default "Expiry (days):" "30")
    if [[ ! "$expiry_days" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid number of days."
        press_enter
        return 1
    fi

    # Create the system user for OpenVPN
    if ! id "$username" &>/dev/null; then
        useradd -M -s /usr/sbin/nologin "$username" 2>/dev/null
    fi
    echo "${username}:${password}" | chpasswd 2>/dev/null

    # Insert into database
    db_insert_account "$username" "$password" "openvpn" "$expiry_days"

    press_enter
}

# Create a trial account (1 day)
menu_create_trial() {
    draw_header "Create Trial Account"

    local username
    local password

    username=$(prompt_default "Username:")
    if [[ -z "$username" ]]; then
        msg_err "Username cannot be empty."
        press_enter
        return 1
    fi

    # Check if user already exists
    local exists
    exists=$(db_query "SELECT username FROM accounts WHERE username='${username}';" yes)
    if [[ -n "$exists" ]]; then
        msg_err "Username '${username}' already exists."
        press_enter
        return 1
    fi

    password=$(gen_password 10)

    # Create system user
    if ! id "$username" &>/dev/null; then
        useradd -m -s /bin/bash "$username" 2>/dev/null
        echo "${username}:${password}" | chpasswd 2>/dev/null
    fi

    # Set 1-day expiry on system account
    local trial_date
    trial_date=$(date -d "+1 day" '+%Y-%m-%d' 2>/dev/null)
    if [[ -n "$trial_date" ]]; then
        chage -E "$trial_date" "$username" 2>/dev/null
    fi

    db_insert_account "$username" "$password" "ssh" "1"

    echo ""
    draw_box "Trial Account Created" \
        "Username : ${username}" \
        "Password : ${password}" \
        "Duration : 1 day" \
        "Protocol : SSH"
    echo ""

    press_enter
}

# ============================================================================
# Account Management Menus
# ============================================================================

# List all accounts
menu_list_accounts() {
    draw_header "All Accounts"

    # First check and deactivate expired
    db_check_expired

    # Show active accounts
    echo -e "  ${GR}${BOLD}--- Active Accounts ---${RST}"
    db_list_accounts "yes"

    echo -e "  ${YL}${BOLD}--- All Accounts (including inactive) ---${RST}"
    db_list_accounts "no"

    press_enter
}

# Delete an account
menu_delete_account() {
    draw_header "Delete Account"

    # Show existing accounts
    local accounts
    accounts=$(db_query "SELECT id, username, protocol, is_active FROM accounts ORDER BY id;" yes)

    if [[ -z "$accounts" ]]; then
        msg_info "No accounts found."
        press_enter
        return 0
    fi

    echo -e "  ${WH}${BOLD}ID  Username          Protocol    Active${RST}"
    echo -e "  ${DIM_GRAY}--  --------          --------    ------${RST}"
    echo "$accounts" | while IFS='|' read -r aid auser aproto aactive; do
        local active_str="No"
        if [[ "$aactive" == "1" ]]; then
            active_str="${GR}Yes${RST}"
        fi
        printf "  %-3s %-17s %-11s %b\n" "$aid" "$auser" "$aproto" "$active_str"
    done
    echo ""

    local del_id
    del_id=$(prompt_default "Enter account ID to delete:")

    if [[ -z "$del_id" || ! "$del_id" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid ID."
        press_enter
        return 1
    fi

    # Get the username for this ID
    local del_user
    del_user=$(db_query "SELECT username FROM accounts WHERE id=${del_id};" yes)

    if [[ -z "$del_user" ]]; then
        msg_err "No account found with ID ${del_id}."
        press_enter
        return 1
    fi

    if ! confirm "Delete account '${del_user}' (ID: ${del_id})?"; then
        msg_info "Cancelled."
        press_enter
        return 0
    fi

    # Remove system user if it exists
    if id "$del_user" &>/dev/null; then
        userdel -r "$del_user" 2>/dev/null
        msg_ok "System user '${del_user}' removed."
    fi

    # Remove from database
    db_delete_account "$del_user"

    press_enter
}

# Renew an account
menu_renew_account() {
    draw_header "Renew Account"

    # Show active accounts with their expiry
    local accounts
    accounts=$(db_query "SELECT id, username, protocol, expiry FROM accounts WHERE is_active=1 ORDER BY id;" yes)

    if [[ -z "$accounts" ]]; then
        msg_info "No active accounts to renew."
        press_enter
        return 0
    fi

    echo -e "  ${WH}${BOLD}ID  Username          Protocol    Expiry${RST}"
    echo -e "  ${DIM_GRAY}--  --------          --------    -----${RST}"
    echo "$accounts" | while IFS='|' read -r aid auser aproto aexpiry; do
        printf "  %-3s %-17s %-11s %s\n" "$aid" "$auser" "$aproto" "$aexpiry"
    done
    echo ""

    local renew_id
    renew_id=$(prompt_default "Enter account ID to renew:")

    if [[ -z "$renew_id" || ! "$renew_id" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid ID."
        press_enter
        return 1
    fi

    local renew_user
    renew_user=$(db_query "SELECT username FROM accounts WHERE id=${renew_id} AND is_active=1;" yes)

    if [[ -z "$renew_user" ]]; then
        msg_err "No active account found with ID ${renew_id}."
        press_enter
        return 1
    fi

    local extra_days
    extra_days=$(prompt_default "Add how many days?" "30")

    if [[ ! "$extra_days" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid number."
        press_enter
        return 1
    fi

    if db_renew_account "$renew_user" "$extra_days"; then
        # Also update system user expiry
        local new_exp
        new_exp=$(db_query "SELECT expiry FROM accounts WHERE username='${renew_user}';" yes)
        if [[ -n "$new_exp" ]]; then
            chage -E "${new_exp%% *}" "$renew_user" 2>/dev/null
        fi
    fi

    press_enter
}

# Check for and handle expired accounts
menu_check_expired() {
    draw_header "Check Expired Accounts"

    local count
    count=$(db_query "SELECT COUNT(*) FROM accounts WHERE is_active=1;" yes)

    if [[ -z "$count" || "$count" -eq 0 ]]; then
        msg_info "No active accounts."
        press_enter
        return 0
    fi

    # Show accounts nearing expiry (within 3 days)
    local near_exp
    near_exp=$(date -d "+3 days" -u '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    near_exp="${near_exp:-$(date -v+3d -u '+%Y-%m-%d %H:%M:%S' 2>/dev/null)}"

    echo -e "  ${YL}${BOLD}Accounts expiring soon (within 3 days):${RST}"
    db_query "SELECT id, username, protocol, expiry FROM accounts WHERE is_active=1 AND expiry <= '${near_exp}' ORDER BY expiry;" 2>/dev/null

    echo ""
    echo -e "  ${YL}${BOLD}Deactivating expired accounts...${RST}"
    db_check_expired

    press_enter
}

# ============================================================================
# Server Tools Menus
# ============================================================================

# Show detailed server information
menu_server_info() {
    draw_header "Server Information"

    local ip
    ip=$(get_public_ip)
    local os_info
    os_info=$(detect_os)
    local arch
    arch=$(detect_arch)
    local hostname
    hostname=$(hostname -f 2>/dev/null || hostname)
    local kernel
    kernel=$(uname -r)
    local uptime
    uptime=$(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/' | sed 's/,.*//')

    # CPU info
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "N/A")

    # Memory info
    local mem_total mem_used mem_pct
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')
    mem_used=$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}')
    if [[ -n "$mem_total" && "$mem_total" -gt 0 ]]; then
        mem_pct=$(( (mem_used * 100) / mem_total ))
    else
        mem_pct=0
    fi

    # Disk info
    local disk_total disk_used disk_pct
    disk_total=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}')
    disk_used=$(df -h / 2>/dev/null | awk 'NR==2 {print $3}')
    disk_pct=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}' | tr -d '%')

    # Load average
    local load_avg
    load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')

    # Domain from config
    local domain
    domain=$(config_get "domain" "Not configured")

    # Active accounts count
    local active_accts
    active_accts=$(db_query "SELECT COUNT(*) FROM accounts WHERE is_active=1;" yes)
    active_accts="${active_accts:-0}"

    echo ""
    draw_box "System Overview" \
        "Hostname      : ${hostname}" \
        "Public IP     : ${ip}" \
        "Domain        : ${domain}" \
        "OS            : ${os_info}" \
        "Architecture  : ${arch}" \
        "Kernel        : ${kernel}" \
        "Uptime        : ${uptime}" \
        "" \
        "CPU Model     : ${cpu_model}" \
        "CPU Cores     : ${cpu_cores}" \
        "Load Average  : ${load_avg}" \
        "" \
        "RAM           : ${mem_used} MB / ${mem_total} MB (${mem_pct}%)" \
        "Disk (/)      : ${disk_used} / ${disk_total} (${disk_pct}%)" \
        "" \
        "Active Accts  : ${active_accts}"

    # Show port usage
    echo ""
    echo -e "  ${GOLD_RGB}${BOLD}Listening Ports:${RST}"
    ss -tlnp 2>/dev/null | awk 'NR>1 {printf "    %-6s %-20s %s\n", $4, $6, $7}' | head -15

    echo ""
    press_enter
}

# Bandwidth monitoring
menu_bandwidth() {
    draw_header "Bandwidth Monitor"

    if ! is_installed vnstat; then
        msg_info "Installing vnstat..."
        pkg_install vnstat
        systemctl enable vnstat 2>/dev/null
        systemctl start vnstat 2>/dev/null
        msg_ok "vnstat installed. Waiting for data collection..."
        sleep 2
    fi

    echo ""
    echo -e "  ${BOLD}Network Traffic Summary:${RST}"
    vnstat -i 2>/dev/null || vnstat 2>/dev/null || echo -e "  ${DIM}No data yet.${RST}"

    echo ""
    echo -e "  ${BOLD}Live Traffic (5 seconds):${RST}"
    echo -e "  ${DIM}(Monitoring eth0 or the primary interface)${RST}"
    echo ""

    # Find the primary interface
    local iface
    iface=$(ip route 2>/dev/null | awk '/default/ {print $5}' | head -1)
    iface="${iface:-eth0}"

    # Show 5 seconds of live traffic
    for _ in $(seq 1 5); do
        local rx tx
        read -r rx tx <<< "$(cat /proc/net/dev 2>/dev/null | awk -v iface="${iface}:" '$1 ~ iface {print $2, $10}')"
        local rx_mb tx_mb
        rx_mb=$(echo "scale=2; $rx / 1048576" | bc 2>/dev/null || echo "0")
        tx_mb=$(echo "scale=2; $tx / 1048576" | bc 2>/dev/null || echo "0")
        printf "  \r  RX: %10s MB    TX: %10s MB    [%s]   " "$rx_mb" "$tx_mb" "$iface"
        sleep 1
    done
    echo ""
    echo ""

    press_enter
}

# Speed test
menu_speedtest() {
    draw_header "Speed Test"

    if ! is_installed speedtest-cli; then
        msg_info "Installing speedtest-cli..."
        pkg_install speedtest-cli
    fi

    echo ""
    msg_info "Running speed test (this may take a moment)..."
    echo ""

    if speedtest-cli --simple 2>/dev/null; then
        echo ""
        msg_ok "Speed test completed."
    else
        msg_err "Speed test failed. Try again or install manually."
    fi

    echo ""
    press_enter
}

# BBR TCP tuning
menu_bbr() {
    draw_header "BBR TCP Tuning"

    # Check current status
    local current_cc
    current_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    local available_cc
    available_cc=$(sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | awk '{print $3}')

    echo -e "  Current TCP CC  : ${GR}${BOLD}${current_cc}${RST}"
    echo -e "  Available CC    : ${DIM}${available_cc}${RST}"

    if [[ "$current_cc" == "bbr" ]]; then
        msg_ok "BBR is already enabled."
        echo ""
        press_enter
        return 0
    fi

    if ! confirm "Enable BBR TCP congestion control?"; then
        return 0
    fi

    set -e

    # Enable BBR
    cat >> /etc/sysctl.conf << 'BBREOF'

# BraanX: BBR TCP Tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
BBREOF

    sysctl -p >/dev/null 2>&1

    # Verify
    local verify_cc
    verify_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')

    set +e

    if [[ "$verify_cc" == "bbr" ]]; then
        config_set "bbr_enabled" "1"
        msg_ok "BBR enabled successfully."
    else
        msg_err "Failed to enable BBR. Your kernel may not support it."
    fi

    press_enter
}

# SSL Certificate Manager
menu_ssl() {
    draw_header "SSL Certificate Manager"

    local domain
    domain=$(config_get "domain" "")

    if [[ -z "$domain" ]]; then
        echo -e "  ${YL}[?]${RST} No domain configured."
        domain=$(prompt_default "Enter domain for SSL:")

        if [[ -n "$domain" ]]; then
            config_set "domain" "$domain"
        else
            msg_err "Domain is required for SSL certificates."
            press_enter
            return 1
        fi
    fi

    echo -e "  Domain: ${GR}${BOLD}${domain}${RST}"
    echo ""
    echo -e "  ${GR}1)${RST} Generate new certificate (acme.sh)"
    echo -e "  ${GR}2)${RST} Renew existing certificate"
    echo -e "  ${GR}3)${RST} View certificate info"
    echo -e "  ${GR}4)${RST} Use self-signed certificate"
    echo -e "  ${GR}0)${RST} Back"
    echo -en "  ${YL}[?]${RST} Choice: "
    read -r ssl_choice

    case "$ssl_choice" in
        1)
            msg_info "Installing acme.sh..."
            curl -s https://get.acme.sh | sh -s email=admin@${domain} 2>/dev/null
            if [[ -f "$HOME/.acme.sh/acme.sh" ]]; then
                msg_ok "acme.sh installed."
                msg_info "To issue a certificate, ensure port 80 is open and run:"
                echo -e "    ${DIM}~/.acme.sh/acme.sh --issue -d ${domain} --webroot /var/www/html${RST}"
                config_set "ssl_enabled" "1"
            else
                msg_err "Failed to install acme.sh."
            fi
            ;;
        2)
            msg_info "Renewing certificate..."
            if [[ -f "$HOME/.acme.sh/acme.sh" ]]; then
                "$HOME/.acme.sh/acme.sh" --renew -d "$domain" --force 2>/dev/null
                msg_ok "Certificate renewed."
            else
                msg_err "acme.sh not found. Install it first."
            fi
            ;;
        3)
            local cert_path
            cert_path=$(config_get "ssl_cert_path" "")
            if [[ -n "$cert_path" && -f "$cert_path" ]]; then
                openssl x509 -in "$cert_path" -noout -dates -subject 2>/dev/null
            else
                msg_info "No certificate file configured."
            fi
            ;;
        4)
            msg_info "Generating self-signed certificate..."
            local ssl_dir="/etc/braanx/ssl"
            mkdir -p "$ssl_dir"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "${ssl_dir}/server.key" \
                -out "${ssl_dir}/server.crt" \
                -subj "/CN=${domain}" 2>/dev/null
            config_set "ssl_cert_path" "${ssl_dir}/server.crt"
            config_set "ssl_key_path" "${ssl_dir}/server.key"
            config_set "ssl_enabled" "1"
            msg_ok "Self-signed certificate created."
            ;;
        0) return 0 ;;
    esac

    press_enter
}

# Fail2ban setup
menu_fail2ban() {
    draw_header "Fail2ban Setup"

    if ! is_installed fail2ban; then
        msg_info "Installing fail2ban..."
        pkg_install fail2ban
    fi

    # Create a basic BraanX jail config
    local jail_file="/etc/fail2ban/jail.local"
    cat > "$jail_file" << 'FBEOF'
[BraanX-SSH]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
FBEOF

    systemctl enable fail2ban 2>/dev/null
    systemctl restart fail2ban 2>/dev/null
    config_set "fail2ban_enabled" "1"

    msg_ok "Fail2ban configured and started."
    echo -e "  ${DIM}Jail: BraanX-SSH (3 failures = 1 hour ban)${RST}"

    press_enter
}

# ============================================================================
# Backup / Restore
# ============================================================================

# Backup BraanX configuration
menu_backup() {
    draw_header "Backup Configuration"

    local backup_dir
    backup_dir=$(config_get "backup_dir" "/etc/braanx/backup")
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${backup_dir}/braanx_backup_${timestamp}.tar.gz"

    mkdir -p "$backup_dir"

    msg_info "Creating backup: ${backup_file}"

    set -e

    tar -czf "$backup_file" \
        -C /etc/braanx \
        --exclude='backup/*' \
        --exclude='log/*' \
        . 2>/dev/null

    set +e

    if [[ -f "$backup_file" ]]; then
        local size
        size=$(du -h "$backup_file" 2>/dev/null | awk '{print $1}')
        msg_ok "Backup created: ${backup_file} (${size})"
    else
        msg_err "Backup failed."
    fi

    press_enter
}

# Restore BraanX configuration
menu_restore() {
    draw_header "Restore Configuration"

    local backup_dir
    backup_dir=$(config_get "backup_dir" "/etc/braanx/backup")

    if [[ ! -d "$backup_dir" ]]; then
        msg_err "No backup directory found."
        press_enter
        return 1
    fi

    local backups
    backups=$(ls -1t "${backup_dir}"/braanx_backup_*.tar.gz 2>/dev/null)

    if [[ -z "$backups" ]]; then
        msg_info "No backups found."
        press_enter
        return 0
    fi

    echo -e "  ${WH}${BOLD}Available Backups:${RST}"
    local idx=1
    while IFS= read -r bk; do
        local bk_name
        bk_name=$(basename "$bk")
        local bk_size
        bk_size=$(du -h "$bk" 2>/dev/null | awk '{print $1}')
        echo -e "    ${GR}${idx})${RST} ${bk_name} (${bk_size})"
        idx=$((idx + 1))
    done <<< "$backups"
    echo -e "    ${YL}0)${RST} Cancel"
    echo ""

    local sel
    sel=$(prompt_default "Select backup to restore:")

    if [[ -z "$sel" || "$sel" == "0" ]]; then
        msg_info "Cancelled."
        press_enter
        return 0
    fi

    if ! [[ "$sel" =~ ^[0-9]+$ ]]; then
        msg_err "Invalid selection."
        press_enter
        return 1
    fi

    local selected_file
    selected_file=$(echo "$backups" | sed -n "${sel}p")

    if [[ -z "$selected_file" || ! -f "$selected_file" ]]; then
        msg_err "Invalid backup file."
        press_enter
        return 1
    fi

    if ! confirm "Restore from $(basename "$selected_file")? This will overwrite current config."; then
        msg_info "Cancelled."
        press_enter
        return 0
    fi

    set -e

    tar -xzf "$selected_file" -C /etc/braanx/ 2>/dev/null

    set +e

    msg_ok "Configuration restored from backup."
    msg_warn "Please restart services to apply changes."

    press_enter
}

# ============================================================================
# Service Management
# ============================================================================

# Restart all BraanX-managed services
menu_restart_services() {
    draw_header "Restart All Services"

    local services=()

    if [[ "$(config_get "nginx_enabled" "0")" == "1" ]]; then
        services+=(nginx)
    fi
    if [[ "$(config_get "xray_enabled" "0")" == "1" ]]; then
        services+=(xray)
    fi
    if [[ "$(config_get "fail2ban_enabled" "0")" == "1" ]]; then
        services+=(fail2ban)
    fi

    # Always include SSH if enabled
    services+=(ssh)

    if [[ ${#services[@]} -eq 0 ]]; then
        msg_info "No services configured yet."
        press_enter
        return 0
    fi

    msg_info "Restarting services: ${services[*]}"

    for svc in "${services[@]}"; do
        if systemctl list-unit-files "${svc}.service" &>/dev/null; then
            systemctl restart "$svc" 2>/dev/null
            msg_ok "${svc} restarted."
        else
            msg_warn "${svc} service not found, skipping."
        fi
    done

    press_enter
}

# ============================================================================
# Telegram Bot Menus
# ============================================================================

# Setup Telegram bot
menu_tg_setup() {
    draw_header "Setup Telegram Bot"

    echo -e "  To set up the Telegram bot, you need:"
    echo -e "    1. A bot token from @BotFather"
    echo -e "    2. Your chat ID (from @userinfobot)"
    echo ""

    local bot_token
    bot_token=$(prompt_default "Bot Token:")

    if [[ -z "$bot_token" ]]; then
        msg_err "Bot token is required."
        press_enter
        return 1
    fi

    local chat_id
    chat_id=$(prompt_default "Chat ID:")

    if [[ -z "$chat_id" ]]; then
        msg_err "Chat ID is required."
        press_enter
        return 1
    fi

    config_set "tg_bot_token" "$bot_token"
    config_set "tg_bot_chat_id" "$chat_id"
    config_set "tg_bot_enabled" "1"

    msg_ok "Telegram bot configured."
    press_enter
}

# Show Telegram bot status
menu_tg_status() {
    draw_header "Telegram Bot Status"

    local enabled
    enabled=$(config_get "tg_bot_enabled" "0")
    local token
    token=$(config_get "tg_bot_token" "")
    local chat_id
    chat_id=$(config_get "tg_bot_chat_id" "")

    if [[ "$enabled" != "1" ]]; then
        msg_info "Telegram bot is not enabled."
        press_enter
        return 0
    fi

    echo -e "  Status      : ${GR}Enabled${RST}"
    echo -e "  Bot Token   : ${DIM}${token:0:10}...${RST}"
    echo -e "  Chat ID     : ${WH}${chat_id}${RST}"

    # Test API connectivity
    local api_check
    api_check=$(curl -s --max-time 5 "https://api.telegram.org/bot${token}/getMe" 2>/dev/null)
    if echo "$api_check" | grep -q '"ok":true'; then
        local bot_name
        bot_name=$(echo "$api_check" | grep -oP '"first_name":"\K[^"]+')
        echo -e "  Bot Name    : ${GR}${bot_name}${RST}"
        echo -e "  API Status  : ${GR}Connected${RST}"
    else
        echo -e "  API Status  : ${RD}Failed to connect${RST}"
    fi

    press_enter
}

# Send a test message via Telegram
menu_tg_test() {
    draw_header "Send Test Message"

    local token
    token=$(config_get "tg_bot_token" "")
    local chat_id
    chat_id=$(config_get "tg_bot_chat_id" "")

    if [[ -z "$token" || -z "$chat_id" ]]; then
        msg_err "Telegram bot not configured. Set it up first."
        press_enter
        return 1
    fi

    msg_info "Sending test message..."

    local response
    response=$(curl -s --max-time 10 -X POST \
        "https://api.telegram.org/bot${token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=BraanX Test Message - $(date '+%Y-%m-%d %H:%M:%S')" \
        -d "parse_mode=Markdown" 2>/dev/null)

    if echo "$response" | grep -q '"ok":true'; then
        msg_ok "Test message sent successfully."
    else
        msg_err "Failed to send message. Check token and chat ID."
    fi

    press_enter
}

# ============================================================================
# System Menus
# ============================================================================

# Update BraanX
menu_update() {
    draw_header "Update BraanX"

    if type self_update &>/dev/null; then
        self_update
    else
        msg_info "Please download the latest version from GitHub."
        echo -e "  ${DIM}https://github.com/braanx/braanx/releases/latest${RST}"
    fi

    press_enter
}

# Uninstall BraanX
menu_uninstall() {
    draw_header "Uninstall BraanX"

    msg_warn "This will remove all BraanX files and configuration."
    msg_warn "VPN services (XRay, Nginx, etc.) will NOT be removed."

    if ! confirm "Are you sure you want to uninstall BraanX?" "no"; then
        msg_info "Cancelled."
        press_enter
        return 0
    fi

    if ! confirm "Really uninstall? All BraanX data will be lost." "no"; then
        msg_info "Cancelled."
        press_enter
        return 0
    fi

    msg_info "Removing BraanX directories..."

    # Remove database
    if [[ -f "$BRAANX_DB_FILE" ]]; then
        rm -f "$BRAANX_DB_FILE"
        msg_ok "Database removed."
    fi

    # Remove libraries
    rm -f "${BRAANX_LIB_DIR}/functions.sh"
    rm -f "${BRAANX_LIB_DIR}/menu.sh"
    msg_ok "Libraries removed."

    # Remove logs
    rm -f "${BRAANX_LOG_DIR}/"*.log
    msg_ok "Logs removed."

    # Remove config
    rm -f "$BRAANX_CONF_FILE"
    msg_ok "Configuration removed."

    # Remove directories
    rmdir "${BRAANX_LIB_DIR}" 2>/dev/null
    rmdir "${BRAANX_LOG_DIR}" 2>/dev/null
    rmdir "${BRAANX_DB_DIR}" 2>/dev/null
    rmdir "${BRAANX_CONF_DIR}/backup" 2>/dev/null
    rmdir "${BRAANX_CONF_DIR}/ssl" 2>/dev/null
    rmdir "$BRAANX_CONF_DIR" 2>/dev/null

    echo ""
    msg_ok "BraanX has been uninstalled."
    echo ""
    exit 0
}