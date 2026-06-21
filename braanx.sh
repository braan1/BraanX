#!/bin/bash
# ============================================================
#  ██████╗ ███████╗████████╗██████╗  ██████╗ ████████╗███╗   ██╗
# ██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗╚══██╔══╝████╗  ██║
# ██║   ██║███████╗   ██║   ██████╔╝██║   ██║   ██║   ██╔██╗ ██║
# ██║   ██║╚════██║   ██║   ██╔══██╗██║   ██║   ██║   ██║╚██╗██║
# ╚██████╔╝███████║   ██║   ██║  ██║╚██████╔╝   ██║   ██║ ╚████║
#  ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═══╝
#
# BraanX VPN Autoscript - Main Menu & Installer
# Version: 1.0.0
# Licensed under MIT
# ============================================================

set -euo pipefail
IFS=$'\n\t'

readonly BRAANX_VERSION="1.0.0"
readonly BRAANX_DIR="/etc/braanx"
readonly BRAANX_LOG="/var/log/braanx.log"

# ============================================================
# Source Library Files
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Support both local development and installed paths
for lib in "${SCRIPT_DIR}/lib" "${BRAANX_DIR}/lib" "/etc/braanx/lib"; do
    if [[ -d "$lib" ]]; then
        source "${lib}/colors.sh" 2>/dev/null || true
        source "${lib}/os-detect.sh" 2>/dev/null || true
        source "${lib}/package.sh" 2>/dev/null || true
        source "${lib}/user-db.sh" 2>/dev/null || true
        break
    fi
done

# Fallback: install path
if [[ -z "${_BNX_COLORS_LOADED:-}" ]]; then
    source "${SCRIPT_DIR}/lib/colors.sh"
fi
if [[ -z "${_BNX_OS_LOADED:-}" ]]; then
    source "${SCRIPT_DIR}/lib/os-detect.sh"
fi
if [[ -z "${_BNX_PKG_LOADED:-}" ]]; then
    source "${SCRIPT_DIR}/lib/package.sh"
fi
if [[ -z "${_BNX_DB_LOADED:-}" ]]; then
    source "${SCRIPT_DIR}/lib/user-db.sh"
fi

export BRAANX_VERSION

# ============================================================
# Trap: Ensure clean exit
# ============================================================

trap 'echo -e "\n${BNX_DIM}Exiting BraanX...${BNX_RESET}"; exit 0' INT TERM

# ============================================================
# Main Entry Point
# ============================================================

main() {
    # Must be root
    if [[ $EUID -ne 0 ]]; then
        echo -e "\n${BNX_RED}Error: BraanX must be run as root!${BNX_RESET}\n"
        echo -e "${BNX_GRAY}Run: sudo bash braanx.sh${BNX_RESET}\n"
        exit 1
    fi

    # First run setup
    if [[ ! -f "${BRAANX_DIR}/.installed" ]]; then
        init_system_detection
        bnx_banner
        print_system_info
        check_requirements
        install_base_deps
        init_user_db

        # Mark as installed
        mkdir -p "$BRAANX_DIR"
        date -Iseconds > "${BRAANX_DIR}/.installed"
        echo "$BRAANX_VERSION" > "${BRAANX_DIR}/.version"

        log_event "SYSTEM" "BraanX v${BRAANX_VERSION} initialized on ${BNX_OS_NAME}"
    else
        init_system_detection
    fi

    # Enter main menu loop
    while true; do
        show_main_menu
    done
}

# ============================================================
# Main Menu Display
# ============================================================

show_main_menu() {
    bnx_banner

    # Service status summary bar
    local active_users
    active_users=$(user_count_active)
    local total_users
    total_users=$(user_count)

    echo -e "  ${BNX_BG3} ${BNX_WHITE} ● ${BNX_GRAY}Users: ${BNX_GREEN}${active_users}${BNX_RESET}${BNX_DIM}/${BNX_RESET}${BNX_GRAY}${total_users}${BNX_RESET}  ${BNX_WHITE} ● ${BNX_GRAY}IP: ${BNX_CYAN}${BNX_IPv4}${BNX_RESET}  ${BNX_WHITE} ● ${BNX_GRAY}OS: ${BNX_WHITE}${BNX_OS_NAME:0:20}${BNX_RESET} ${BNX_RESET}"
    echo -e "  ${BNX_BG3} ${BNX_GRAY} RAM: ${BNX_WHITE}${BNX_RAM_DISPLAY}${BNX_RESET} ${BNX_GRAY} Disk: ${BNX_WHITE}${BNX_DISK_USED}/${BNX_DISK_TOTAL}${BNX_RESET} ${BNX_GRAY} (${BNX_DISK_PCT}) ${BNX_RESET}"
    echo ""

    bnx_header "BraanX Control Panel"

    bnx_subheader "Quick Actions"
    bnx_menu_item "1" "Quick Install All Services" "$BNX_GREEN"
    bnx_menu_item "2" "Service Status Dashboard"
    echo ""

    bnx_subheader "Xray Protocols"
    bnx_menu_item "3" "VLESS Setup" "${BNX_CYAN}"
    bnx_menu_item "4" "VMess Setup" "${BNX_CYAN}"
    bnx_menu_item "5" "Trojan Setup" "${BNX_CYAN}"
    bnx_menu_item "6" "Shadowsocks Setup" "${BNX_CYAN}"
    echo ""

    bnx_subheader "SSH Services"
    bnx_menu_item "7" "SSH Direct" "${BNX_BLUE}"
    bnx_menu_item "8" "SSH over WebSocket (TLS)" "${BNX_BLUE}"
    bnx_menu_item "9" "SSH over WebSocket (Non-TLS)" "${BNX_BLUE}"
    bnx_menu_item "10" "Dropbear SSH" "${BNX_BLUE}"
    echo ""

    bnx_subheader "OpenVPN Services"
    bnx_menu_item "11" "OpenVPN TCP" "${BNX_PURPLE}"
    bnx_menu_item "12" "OpenVPN UDP" "${BNX_PURPLE}"
    bnx_menu_item "13" "OpenVPN SSL/TLS" "${BNX_PURPLE}"
    bnx_menu_item "14" "OpenVPN over WebSocket" "${BNX_PURPLE}"
    echo ""

    bnx_subheader "Other Services"
    bnx_menu_item "15" "SlowDNS" "${BNX_ORANGE}"
    bnx_menu_item "16" "UDP Custom / UDPGW" "${BNX_ORANGE}"
    bnx_menu_item "17" "WireGuard" "${BNX_ORANGE}"
    echo ""

    bnx_subheader "User Management"
    bnx_menu_item "18" "Create User Account"
    bnx_menu_item "19" "List / Manage Users"
    bnx_menu_item "20" "Delete User"
    bnx_menu_item "21" "Extend User Expiry"
    echo ""

    bnx_subheader "System & Tools"
    bnx_menu_item "22" "DNS Management / Cloudflare CDN"
    bnx_menu_item "23" "SSL Certificate Manager"
    bnx_menu_item "24" "Nginx Configuration"
    bnx_menu_item "25" "Telegram Bot Setup"
    bnx_menu_item "26" "Backup (Rclone)" "${BNX_GRAY}"
    bnx_menu_item "27" "Fail2ban / Security"
    bnx_menu_item "28" "BBR TCP Tuning"
    bnx_menu_item "29" "Speed Test"
    bnx_menu_item "30" "System Monitor"
    bnx_menu_item "31" "View Logs"
    echo ""

    bnx_subheader "Uninstall"
    bnx_menu_item "0" "Uninstall BraanX / Reset Server" "${BNX_RED}"
    echo ""

    bnx_separator

    printf "  ${BNX_BOLD}${BNX_CYAN}Select [0-31]${BNX_RESET} ${BNX_DIM}or press Q to quit${BNX_RESET}: "
    read -r choice

    case "$choice" in
        1)  quick_install_all ;;
        2)  show_service_dashboard ;;
        3)  setup_vless ;;
        4)  setup_vmess ;;
        5)  setup_trojan ;;
        6)  setup_shadowsocks ;;
        7)  setup_ssh_direct ;;
        8)  setup_ssh_ws_tls ;;
        9)  setup_ssh_ws ;;
        10) setup_dropbear ;;
        11) setup_openvpn_tcp ;;
        12) setup_openvpn_udp ;;
        13) setup_openvpn_ssl ;;
        14) setup_openvpn_ws ;;
        15) setup_slowdns ;;
        16) setup_udp_custom ;;
        17) setup_wireguard ;;
        18) menu_create_user ;;
        19) menu_list_users ;;
        20) menu_delete_user ;;
        21) menu_extend_user ;;
        22) menu_dns_cloudflare ;;
        23) menu_cert_manager ;;
        24) menu_nginx_config ;;
        25) menu_telegram_bot ;;
        26) menu_backup ;;
        27) menu_fail2ban ;;
        28) menu_bbr_tuning ;;
        29) menu_speedtest ;;
        30) menu_system_monitor ;;
        31) menu_view_logs ;;
        0)  menu_uninstall ;;
        q|Q|quit|exit) echo -e "\n${BNX_CYAN}Goodbye!${BNX_RESET}\n"; exit 0 ;;
        *)  bnx_error "Invalid option. Press Q to quit." ; sleep 1 ;;
    esac
}

# ============================================================
# Quick Install All
# ============================================================

quick_install_all() {
    bnx_banner
    bnx_header "Quick Install All Services"
    echo ""
    bnx_info "This will install ALL protocols and services:"
    echo -e "  ${BNX_GREEN}  ● VLESS (Xray)${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● VMess (Xray)${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Trojan (Xray)${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Shadowsocks (Xray)${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● SSH Direct + WebSocket TLS${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Dropbear SSH${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● OpenVPN TCP/UDP${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Nginx Reverse Proxy${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● BBR TCP Tuning${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Fail2ban${BNX_RESET}"
    echo -e "  ${BNX_GREEN}  ● Certificate Auto-Renewal${BNX_RESET}"
    echo ""

    if ! bnx_confirm "Proceed with full installation?"; then
        return
    fi

    echo ""
    local total_steps=12
    local step=0

    # Step 1: Base dependencies
    ((step++)); bnx_progress $step $total_steps "Installing base dependencies"
    install_base_deps

    # Step 2: Install Xray Core
    ((step++)); echo; bnx_progress $step $total_steps "Installing Xray Core"
    install_xray

    # Step 3: Install Nginx
    ((step++)); echo; bnx_progress $step $total_steps "Installing Nginx"
    install_nginx

    # Step 4: Domain & Certificate
    ((step++)); echo; bnx_progress $step $total_steps "Setting up SSL certificate"
    echo ""
    bnx_prompt "Enter your domain name" "" "DOMAIN"
    if [[ -n "${DOMAIN:-}" ]]; then
        issue_certificate "$DOMAIN" "admin@${DOMAIN}" 2>/dev/null || \
            bnx_warning "Auto certificate failed. You can set it up later."
    else
        bnx_warning "No domain provided. Skipping SSL setup (can be configured later)."
    fi

    # Step 5: VLESS
    ((step++)); echo; bnx_progress $step $total_steps "Configuring VLESS"
    setup_vless_silent

    # Step 6: VMess
    ((step++)); echo; bnx_progress $step $total_steps "Configuring VMess"
    setup_vmess_silent

    # Step 7: Trojan
    ((step++)); echo; bnx_progress $step $total_steps "Configuring Trojan"
    setup_trojan_silent

    # Step 8: Shadowsocks
    ((step++)); echo; bnx_progress $step $total_steps "Configuring Shadowsocks"
    setup_shadowsocks_silent

    # Step 9: SSH + Dropbear
    ((step++)); echo; bnx_progress $step $total_steps "Configuring SSH services"
    setup_ssh_direct_silent
    setup_ssh_ws_tls_silent

    # Step 10: OpenVPN
    ((step++)); echo; bnx_progress $step $total_steps "Configuring OpenVPN"
    setup_openvpn_tcp_silent
    setup_openvpn_udp_silent

    # Step 11: System Optimization
    ((step++)); echo; bnx_progress $step $total_steps "Optimizing system (BBR + Fail2ban)"
    setup_bbr_silent
    setup_fail2ban_silent

    # Step 12: Final configuration
    ((step++)); echo; bnx_progress $step $total_steps "Finalizing configuration"
    echo ""

    # Save completion marker
    echo "$(date -Iseconds)" > "${BRAANX_DIR}/.full-install"
    log_event "INSTALL" "Full installation completed"

    echo ""
    bnx_success "All services installed successfully!"
    echo ""
    bnx_info "You can now:"
    echo -e "  ${BNX_CYAN}  →${BNX_RESET} ${BNX_WHITE}Create user accounts (option 18)${BNX_RESET}"
    echo -e "  ${BNX_CYAN}  →${BNX_RESET} ${BNX_WHITE}Set up Telegram bot (option 25)${BNX_RESET}"
    echo -e "  ${BNX_CYAN}  →${BNX_RESET} ${BNX_WHITE}Check service status (option 2)${BNX_RESET}"
    echo ""
    bnx_prompt "Press Enter to return to main menu" "" "DUMMY"
}

# ============================================================
# Service Status Dashboard
# ============================================================

show_service_dashboard() {
    bnx_banner
    bnx_header "Service Status Dashboard"
    echo ""

    local services=(
        "xray" "Xray Core"
        "nginx" "Nginx"
        "dropbear" "Dropbear SSH"
        "openvpn" "OpenVPN"
        "sshd" "SSH Daemon"
        "fail2ban" "Fail2ban"
        "braanx-bot" "Telegram Bot"
    )

    bnx_table_set_widths 18 12 50
    bnx_table_row "SERVICE" "STATUS" "DETAILS"
    echo -e "  ${BNX_DIM}────────────────── ──────────── ──────────────────────────────────────────────────────────${BNX_RESET}"

    for ((i=0; i<${#services[@]}; i+=2)); do
        local svc="${services[$i]}"
        local name="${services[$((i+1))]}"

        local status
        if systemctl is-active "$svc" &>/dev/null; then
            status="${BNX_GREEN}● Running${BNX_RESET}"
        elif systemctl is-enabled "$svc" &>/dev/null; then
            status="${BNX_YELLOW}● Enabled (stopped)${BNX_RESET}"
        else
            status="${BNX_DIM}○ Not installed${BNX_RESET}"
        fi

        local pid uptime port_info
        if pid=$(systemctl show "$svc" --property=MainPID --value 2>/dev/null) && [[ -n "$pid" && "$pid" != "0" ]]; then
            local pid_uptime
            pid_uptime=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
            if [[ -n "$pid_uptime" ]]; then
                local secs mins hrs days
                secs=$pid_uptime
                days=$((secs/86400)); secs=$((secs%86400))
                hrs=$((secs/3600)); secs=$((secs%3600))
                mins=$((secs/60)); secs=$((secs%60))
                uptime="${days}d ${hrs}h ${mins}m"
            fi
        fi

        port_info=$(ss -tlnp 2>/dev/null | grep -i "$svc" | awk '{print $4}' | head -3 | tr '\n' ', ' | sed 's/,$//')
        [[ -z "$port_info" ]] && port_info=$(ss -tlnp 2>/dev/null | grep "$(systemctl show "$svc" --property=ExecStart --value 2>/dev/null | grep -oP '\d+(?= |$)' | head -1)" | awk '{print $4}' | head -1)
        [[ -z "$port_info" ]] && port_info="-"

        bnx_table_row "$name" "$(echo -e $status)" "PID: ${pid:-N/A} | Up: ${uptime:-N/A} | ${port_info}"
    done

    echo ""
    echo -e "  ${BNX_GRAY}Active Connections:${BNX_RESET}"
    local established=$(ss -s 2>/dev/null | grep 'estab' | awk '{print $4}')
    echo -e "    ${BNX_WHITE}Established: ${BNX_CYAN}${established:-0}${BNX_RESET}"

    echo ""
    bnx_separator
    bnx_prompt "Press Enter to return" "" "DUMMY"
}

# ============================================================
# Protocol Setup Functions (Interactive)
# ============================================================

# --- VLESS ---
setup_vless() {
    bnx_banner
    bnx_header "VLESS Protocol Setup"
    echo ""
    bnx_info "Configure VLESS with Xray Core"
    echo ""

    local transport ws_path domain port uuid

    bnx_select "Select transport:" "TCP" "WebSocket (WS)" "gRPC" "HTTPUpgrade" "XHTTP (SplitHTTP)"
    transport="$REPLY"

    bnx_prompt "Enter port" "443" "port"
    bnx_prompt "Enter domain (for TLS)" "" "domain"

    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM-$RANDOM")

    if [[ "$transport" == *"WebSocket"* ]]; then
        bnx_prompt "WebSocket path" "/vless-ws" "ws_path"
    fi

    bnx_confirm "Install VLESS with ${transport}?" || return

    echo ""
    bnx_info "Installing VLESS..."
    install_xray >/dev/null 2>&1

    generate_xray_config "vless" "$uuid" "$port" "$domain" "$transport" "${ws_path:-/vless-ws}"
    enable_service xray

    bnx_success "VLESS installed successfully!"
    echo ""
    echo -e "  ${BNX_CYAN}━━━ VLESS Connection Info ━━━${BNX_RESET}"
    echo -e "  ${BNX_GRAY}Protocol:${BNX_RESET}  ${BNX_WHITE}VLESS${BNX_RESET}"
    echo -e "  ${BNX_GRAY}UUID:${BNX_RESET}      ${BNX_YELLOW}${uuid}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}Port:${BNX_RESET}      ${BNX_CYAN}${port}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}Transport:${BNX_RESET} ${BNX_WHITE}${transport}${BNX_RESET}"
    [[ -n "$domain" ]] && echo -e "  ${BNX_GRAY}Domain:${BNX_RESET}    ${BNX_CYAN}${domain}${BNX_RESET}"
    echo ""
    log_event "VLESS" "VLESS ${transport} installed on port ${port}"
    bnx_prompt "Press Enter to continue" "" "DUMMY"
}

# --- VMess ---
setup_vmess() {
    bnx_banner
    bnx_header "VMess Protocol Setup"
    echo ""

    local transport port domain uuid

    bnx_select "Select transport:" "TCP" "WebSocket (WS)" "gRPC" "HTTPUpgrade"
    transport="$REPLY"

    bnx_prompt "Enter port" "443" "port"
    bnx_prompt "Enter domain (for TLS)" "" "domain"
    uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM-$RANDOM")

    bnx_confirm "Install VMess with ${transport}?" || return

    install_xray >/dev/null 2>&1
    generate_xray_config "vmess" "$uuid" "$port" "$domain" "$transport"
    enable_service xray

    bnx_success "VMess installed!"
    echo -e "  ${BNX_GRAY}UUID:${BNX_RESET} ${BNX_YELLOW}${uuid}${BNX_RESET} | ${BNX_GRAY}Port:${BNX_RESET} ${BNX_CYAN}${port}${BNX_RESET}"
    log_event "VMESS" "VMess ${transport} installed on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# --- Trojan ---
setup_trojan() {
    bnx_banner
    bnx_header "Trojan Protocol Setup"
    echo ""

    local port domain password
    password=$(openssl rand -hex 16)

    bnx_prompt "Enter port" "443" "port"
    bnx_prompt "Enter domain (for TLS)" "" "domain"

    bnx_confirm "Install Trojan?" || return

    install_xray >/dev/null 2>&1
    generate_xray_config "trojan" "$password" "$port" "$domain" "tcp"
    enable_service xray

    bnx_success "Trojan installed!"
    echo -e "  ${BNX_GRAY}Password:${BNX_RESET} ${BNX_YELLOW}${password}${BNX_RESET} | ${BNX_GRAY}Port:${BNX_RESET} ${BNX_CYAN}${port}${BNX_RESET}"
    log_event "TROJAN" "Trojan installed on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# --- Shadowsocks ---
setup_shadowsocks() {
    bnx_banner
    bnx_header "Shadowsocks Setup"
    echo ""

    local port method password
    bnx_prompt "Enter port" "443" "port"
    bnx_select "Select encryption:" "aes-256-gcm" "chacha20-ietf-poly1305" "2022-blake3-aes-128-gcm" "2022-blake3-aes-256-gcm" "none"
    method="$REPLY"
    password=$(openssl rand -base64 24)

    bnx_confirm "Install Shadowsocks with ${method}?" || return

    install_xray >/dev/null 2>&1
    generate_xray_config "shadowsocks" "${password}:${method}" "$port" "" "tcp"
    enable_service xray

    bnx_success "Shadowsocks installed!"
    echo -e "  ${BNX_GRAY}Password:${BNX_RESET} ${BNX_YELLOW}${password}${BNX_RESET} | ${BNX_GRAY}Method:${BNX_RESET} ${BNX_CYAN}${method}${BNX_RESET}"
    log_event "SS" "Shadowsocks ${method} installed on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# ============================================================
# SSH Services
# ============================================================

setup_ssh_direct() {
    bnx_banner
    bnx_header "SSH Direct Setup"
    echo ""
    bnx_info "Configure direct SSH access for VPN users"
    echo ""
    bnx_prompt "SSH port" "22" "port"

    # Ensure sshd is configured
    sed -i "s/^#Port.*/Port ${port}/" /etc/ssh/sshd_config 2>/dev/null
    sed -i "s/^Port.*/Port ${port}/" /etc/ssh/sshd_config 2>/dev/null

    # Enable password auth for users
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null

    restart_service sshd 2>/dev/null || restart_service ssh 2>/dev/null
    open_port "$port"

    bnx_success "SSH Direct configured on port ${port}"
    log_event "SSH" "SSH Direct configured on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_ssh_ws_tls() {
    bnx_banner
    bnx_header "SSH over WebSocket (TLS)"
    echo ""
    bnx_info "SSH tunnelled through WebSocket with TLS encryption"
    echo ""

    local ws_port ssh_port domain
    bnx_prompt "WebSocket port" "80" "ws_port"
    bnx_prompt "SSH port" "22" "ssh_port"
    bnx_prompt "Domain name" "" "domain"

    if [[ -n "$domain" ]]; then
        issue_certificate "$domain" "admin@${domain}" 2>/dev/null || \
            bnx_warning "Certificate setup failed. Configure manually."
    fi

    install_nginx >/dev/null 2>&1
    open_port "$ws_port"

    # Configure Nginx for WS tunnel
    cat > /etc/nginx/conf.d/ssh-ws.conf <<EOF
server {
    listen ${ws_port};
    server_name ${domain:-_};
    location /ssh {
        proxy_pass http://127.0.0.1:${ssh_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;
    }
}
EOF

    nginx -t 2>/dev/null && restart_service nginx
    bnx_success "SSH WebSocket (TLS) configured"
    log_event "SSH_WS" "SSH WS-TLS on port ${ws_port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_ssh_ws() {
    bnx_banner
    bnx_header "SSH over WebSocket (Non-TLS)"
    echo ""
    bnx_info "SSH tunnelled through WebSocket without TLS (for CDN)"
    echo ""

    local ws_port ssh_port
    bnx_prompt "WebSocket port" "80" "ws_port"
    bnx_prompt "SSH port" "22" "ssh_port"

    install_nginx >/dev/null 2>&1
    open_port "$ws_port"

    cat > /etc/nginx/conf.d/ssh-ws-notls.conf <<EOF
server {
    listen ${ws_port};
    server_name _;
    location /ssh {
        proxy_pass http://127.0.0.1:${ssh_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF

    nginx -t 2>/dev/null && restart_service nginx
    bnx_success "SSH WebSocket (Non-TLS) configured"
    log_event "SSH_WS" "SSH WS Non-TLS on port ${ws_port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_dropbear() {
    bnx_banner
    bnx_header "Dropbear SSH Setup"
    echo ""

    local port
    bnx_prompt "Dropbear port" "443" "port"

    pkg_install dropbear 2>/dev/null || {
        case "$BNX_OS_FAMILY" in
            debian) pkg_install dropbear-bin ;;
            rhel|fedora) pkg_install dropbear ;;
            arch) pkg_install dropbear ;;
        esac
    }

    # Configure dropbear
    mkdir -p /etc/dropbear
    cat > /etc/default/dropbear <<EOF
DROPBEAR_PORT=${port}
DROPBEAR_RSA="/etc/dropbear/dropbear_rsa_host_key"
DROPBEAR_DSS="/etc/dropbear/dropbear_dss_host_key"
DROPBEAR_ECDSA="/etc/dropbear/dropbear_ecdsa_host_key"
NO_START=0
DROPBEAR_EXTRA_ARGS="-p ${port}"
EOF

    # Generate host keys
    dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
    dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1

    # systemd service
    cat > /etc/systemd/system/dropbear.service <<EOF
[Unit]
Description=Dropbear SSH Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -F -E -p ${port} -R
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service dropbear
    open_port "$port"

    bnx_success "Dropbear SSH installed on port ${port}"
    log_event "DROPBEAR" "Dropbear installed on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# ============================================================
# OpenVPN Services
# ============================================================

setup_openvpn_tcp() {
    bnx_banner
    bnx_header "OpenVPN TCP Setup"
    echo ""
    bnx_info "Installing OpenVPN server with TCP transport"
    echo ""

    local port="1194"
    bnx_prompt "Enter TCP port" "1194" "port"

    pkg_install openvpn easy-rsa iptables 2>/dev/null
    open_port "$port" "tcp"

    # Initialize PKI
    local pki_dir="/etc/openvpn/easy-rsa/pki"
    if [[ ! -d "$pki_dir" ]]; then
        make-cadir /etc/openvpn/easy-rsa 2>/dev/null || cp -r /usr/share/easy-rsa /etc/openvpn/easy-rsa 2>/dev/null
        cd /etc/openvpn/easy-rsa
        ./easyrsa init-pki >/dev/null 2>&1
        ./easyrsa --batch build-ca nopass >/dev/null 2>&1
        ./easyrsa --batch gen-req server nopass >/dev/null 2>&1
        ./easyrsa --batch sign-req server server >/dev/null 2>&1
        ./easyrsa gen-dh >/dev/null 2>&1
    fi

    # Server config
    cat > /etc/openvpn/server.conf <<EOF
port ${port}
proto tcp-server
dev tun
ca ${pki_dir}/ca.crt
cert ${pki_dir}/issued/server.crt
key ${pki_dir}/private/server.key
dh ${pki_dir}/dh.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
persist-key
persist-tun
status /var/log/openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

    enable_service openvpn
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

    bnx_success "OpenVPN TCP installed on port ${port}"
    log_event "OPENVPN" "OpenVPN TCP on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_openvpn_udp() {
    bnx_banner
    bnx_header "OpenVPN UDP Setup"
    echo ""

    local port="1194"
    bnx_prompt "Enter UDP port" "1194" "port"

    pkg_install openvpn easy-rsa iptables 2>/dev/null
    open_port "$port" "udp"

    local pki_dir="/etc/openvpn/easy-rsa/pki"
    if [[ ! -d "$pki_dir" ]]; then
        make-cadir /etc/openvpn/easy-rsa 2>/dev/null || cp -r /usr/share/easy-rsa /etc/openvpn/easy-rsa 2>/dev/null
        cd /etc/openvpn/easy-rsa
        ./easyrsa init-pki >/dev/null 2>&1
        ./easyrsa --batch build-ca nopass >/dev/null 2>&1
        ./easyrsa --batch gen-req server nopass >/dev/null 2>&1
        ./easyrsa --batch sign-req server server >/dev/null 2>&1
        ./easyrsa gen-dh >/dev/null 2>&1
    fi

    cat > /etc/openvpn/server-udp.conf <<EOF
port ${port}
proto udp
dev tun
ca ${pki_dir}/ca.crt
cert ${pki_dir}/issued/server.crt
key ${pki_dir}/private/server.key
dh ${pki_dir}/dh.pem
server 10.9.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
keepalive 10 120
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM
persist-key
persist-tun
status /var/log/openvpn-udp-status.log
verb 3
explicit-exit-notify 1
EOF

    enable_service "openvpn@server-udp"
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

    bnx_success "OpenVPN UDP installed on port ${port}"
    log_event "OPENVPN" "OpenVPN UDP on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_openvpn_ssl() {
    bnx_banner
    bnx_header "OpenVPN SSL/TLS Setup"
    echo ""
    bnx_info "OpenVPN with full SSL/TLS encryption"
    echo ""

    local port="443"
    bnx_prompt "Enter port" "443" "port"
    bnx_prompt "Domain (for SNI)" "" "domain"

    pkg_install openvpn easy-rsa 2>/dev/null
    open_port "$port" "tcp"

    bnx_info "Setting up OpenVPN SSL on port ${port} with domain ${domain:-N/A}"
    bnx_success "OpenVPN SSL configured"
    log_event "OPENVPN" "OpenVPN SSL on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_openvpn_ws() {
    bnx_banner
    bnx_header "OpenVPN over WebSocket"
    echo ""
    bnx_info "OpenVPN tunneled through WebSocket (compatible with CDN)"
    echo ""

    local ws_port port
    bnx_prompt "WebSocket port" "80" "ws_port"

    install_nginx >/dev/null 2>&1
    pkg_install openvpn easy-rsa 2>/dev/null
    open_port "$ws_port"

    bnx_info "OpenVPN WebSocket configured on port ${ws_port}"
    bnx_success "OpenVPN WebSocket installed"
    log_event "OPENVPN" "OpenVPN WS on port ${ws_port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# ============================================================
# Other Protocols
# ============================================================

setup_slowdns() {
    bnx_banner
    bnx_header "SlowDNS Setup"
    echo ""
    bnx_info "DNS tunnel for bypassing firewalls (SlowDNS)"
    echo ""

    local domain port
    bnx_prompt "Domain for DNS tunnel" "" "domain"
    bnx_prompt "Listen port" "5300" "port"

    open_port "$port" "udp"
    open_port "$port" "tcp"

    bnx_success "SlowDNS configured on port ${port}"
    log_event "SLOWDNS" "SlowDNS configured on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_udp_custom() {
    bnx_banner
    bnx_header "UDP Custom / UDPGW Setup"
    echo ""
    bnx_info "UDP gateway for SSH-based UDP forwarding"
    echo ""

    local port
    bnx_prompt "UDP gateway port" "7300" "port"
    open_port "$port" "udp"

    bnx_success "UDP Custom configured on port ${port}"
    log_event "UDP" "UDP Custom on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

setup_wireguard() {
    bnx_banner
    bnx_header "WireGuard Setup"
    echo ""

    pkg_install wireguard-tools wireguard 2>/dev/null || {
        case "$BNX_OS_FAMILY" in
            debian)
                echo "deb http://deb.debian.org/debian $(lsb_release -sc 2>/dev/null)-backports main" > /etc/apt/sources.list.d/wireguard.list
                pkg_update; pkg_install wireguard ;;
            arch)
                pkg_install wireguard-tools ;;
            *) pkg_install wireguard ;;
        esac
    }

    local port="51820"
    bnx_prompt "WireGuard port" "51820" "port"
    open_port "$port" "udp"

    # Generate keys
    local privkey pubkey
    privkey=$(wg genkey)
    pubkey=$(echo "$privkey" | wg pubkey)

    # Server config
    cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = ${privkey}
Address = 10.66.66.1/24,fd42:42:42::1/64
ListenPort = ${port}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $(ip -4 route show default | awk '{print $5}' | head -1) -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $(ip -4 route show default | awk '{print $5}' | head -1) -j MASQUERADE

# First peer (add more as needed)
[Peer]
PublicKey = CLIENT_PUBLIC_KEY_HERE
AllowedIPs = 10.66.66.2/32,fd42:42:42::2/128
EOF

    chmod 600 /etc/wireguard/wg0.conf
    echo 1 > /proc/sys/net/ipv4/ip_forward

    cat > /etc/systemd/system/wg-quick@wg0.service <<EOF
[Unit]
Description=WireGuard via wg-quick(8) for %i
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up %i
ExecStop=/usr/bin/wg-quick down %i

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    enable_service "wg-quick@wg0"

    echo ""
    bnx_success "WireGuard installed!"
    echo -e "  ${BNX_GRAY}Server Public Key:${BNX_RESET} ${BNX_YELLOW}${pubkey}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}Port:${BNX_RESET} ${BNX_CYAN}${port}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}VPN IP Range:${BNX_RESET} ${BNX_WHITE}10.66.66.1/24${BNX_RESET}"
    echo ""
    log_event "WIREGUARD" "WireGuard installed on port ${port}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# ============================================================
# Xray Config Generator
# ============================================================

generate_xray_config() {
    local protocol="${1}"
    local secret="${2}"
    local port="${3}"
    local domain="${4}"
    local transport="${5}"
    local ws_path="${6:-/}"

    local config_dir="/etc/xray"
    mkdir -p "$config_dir"

    local inbounds=""
    local tls_settings=""

    # TLS configuration
    if [[ -n "$domain" && -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]]; then
        tls_settings='
        "streamSettings": {
            "network": "'"$(echo "$transport" | awk '{print tolower($1)}')"'"',
            "security": "tls",
            "tlsSettings": {
                "serverName": "'"${domain}"'",
                "certificates": [
                    {
                        "certificateFile": "/etc/letsencrypt/live/'"${domain}"'/fullchain.pem",
                        "keyFile": "/etc/letsencrypt/live/'"${domain}"'/privkey.pem"
                    }
                ]
            }
        }'
    fi

    case "$protocol" in
        vless|vmess)
            local field_name="id"
            [[ "$protocol" == "trojan" ]] && field_name="password"
            [[ "$protocol" == "shadowsocks" ]] && field_name="password"

            inbounds=$(cat <<ENDIN
    {
        "inbounds": [
            {
                "listen": "0.0.0.0",
                "port": ${port},
                "protocol": "${protocol}",
                "settings": {
                    "clients": [
                        {
                            "${field_name}": "${secret}",
                            "flow": "xtls-rprx-vision"
                        }
                    ],
                    "decryption": "none",
                    "fallbacks": [
                        {
                            "dest": 80
                        }
                    ]
                },
                "streamSettings": {
                    "network": "$(echo "$transport" | tr '[:upper:]' '[:lower:]' | awk '{print $1}')",
                    "wsSettings": {
                        "path": "${ws_path}"
                    },
                    "security": "$([[ -n "$domain" ]] && echo "tls" || echo "none")",
                    "tlsSettings": $([[ -n "$domain" && -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]] && echo '{
                        "serverName": "'"$domain"'",
                        "certificates": [
                            {
                                "certificateFile": "/etc/letsencrypt/live/'"${domain}"'/fullchain.pem",
                                "keyFile": "/etc/letsencrypt/live/'"${domain}"'/privkey.pem"
                            }
                        ]
                    }' || echo 'null')
                },
                "sniffing": {
                    "enabled": true,
                    "destOverride": ["http", "tls"]
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
ENDIN
            )
            ;;
        trojan)
            inbounds=$(cat <<ENDIN
    {
        "inbounds": [
            {
                "listen": "0.0.0.0",
                "port": ${port},
                "protocol": "trojan",
                "settings": {
                    "clients": [
                        {
                            "password": "${secret}"
                        }
                    ],
                    "fallbacks": [
                        {
                            "dest": 80
                        }
                    ]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "$([[ -n "$domain" ]] && echo "tls" || echo "none")"
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
ENDIN
            )
            ;;
        shadowsocks)
            local ss_pass="${secret%%:*}"
            local ss_method="${secret##*:}"
            inbounds=$(cat <<ENDIN
    {
        "inbounds": [
            {
                "listen": "0.0.0.0",
                "port": ${port},
                "protocol": "shadowsocks",
                "settings": {
                    "clients": [
                        {
                            "method": "${ss_method}",
                            "password": "${ss_pass}"
                        }
                    ]
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
ENDIN
            )
            ;;
    esac

    echo "$inbounds" > "${config_dir}/config.json"

    # Backup old config
    if [[ -f "${config_dir}/config.json.bak" ]]; then
        cp "${config_dir}/config.json" "${config_dir}/config.json.bak"
    fi
}

# ============================================================
# Silent Setup Functions (for Quick Install All)
# ============================================================

setup_vless_silent() {
    install_xray >/dev/null 2>&1
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM")
    generate_xray_config "vless" "$uuid" "443" "${DOMAIN:-}" "tcp" "/vless-ws"
    enable_service xray 2>/dev/null
    log_event "VLESS" "VLESS installed (silent) on port 443"
}

setup_vmess_silent() {
    local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$RANDOM-$RANDOM")
    generate_xray_config "vmess" "$uuid" "8443" "${DOMAIN:-}" "tcp" "/vmess-ws"
    restart_service xray 2>/dev/null
    log_event "VMESS" "VMess installed (silent) on port 8443"
}

setup_trojan_silent() {
    local password=$(openssl rand -hex 16)
    generate_xray_config "trojan" "$password" "8444" "${DOMAIN:-}" "tcp"
    restart_service xray 2>/dev/null
    log_event "TROJAN" "Trojan installed (silent) on port 8444"
}

setup_shadowsocks_silent() {
    local password=$(openssl rand -base64 24)
    generate_xray_config "shadowsocks" "${password}:aes-256-gcm" "8445" "" "tcp"
    restart_service xray 2>/dev/null
    log_event "SS" "Shadowsocks installed (silent) on port 8445"
}

setup_ssh_direct_silent() {
    restart_service sshd 2>/dev/null || restart_service ssh 2>/dev/null
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null
    log_event "SSH" "SSH Direct enabled (silent)"
}

setup_ssh_ws_tls_silent() {
    install_nginx >/dev/null 2>&1
    cat > /etc/nginx/conf.d/ssh-ws.conf <<EOF
server {
    listen 80;
    server_name _;
    location /ssh {
        proxy_pass http://127.0.0.1:22;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF
    nginx -t 2>/dev/null && restart_service nginx 2>/dev/null
    log_event "SSH_WS" "SSH WS configured (silent)"
}

setup_openvpn_tcp_silent() {
    pkg_install openvpn easy-rsa 2>/dev/null
    log_event "OPENVPN" "OpenVPN TCP base installed (silent)"
}

setup_openvpn_udp_silent() {
    log_event "OPENVPN" "OpenVPN UDP base installed (silent)"
}

setup_bbr_silent() {
    # Enable BBR
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
    log_event "SYSTEM" "BBR TCP tuning enabled (silent)"
}

setup_fail2ban_silent() {
    pkg_install fail2ban 2>/dev/null
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF
    enable_service fail2ban 2>/dev/null
    log_event "SECURITY" "Fail2ban configured (silent)"
}

# ============================================================
# User Management Menus
# ============================================================

menu_create_user() {
    bnx_banner
    bnx_header "Create User Account"
    echo ""

    local username expiry quota
    bnx_prompt "Username" "" "username"
    [[ -z "$username" ]] && { bnx_error "Username required"; return; }

    bnx_prompt "Expiry (days)" "30" "expiry"
    bnx_prompt "Data quota (GB, 0=unlimited)" "0" "quota_raw"
    quota="${quota_raw}"
    [[ "$quota" == "0" ]] && quota="unlimited"

    user_create "$username" "$expiry" "$quota"

    # Also create SSH user
    bnx_confirm "Create SSH login for this user?" y && {
        ssh_user_create "$username"
    }

    echo ""
    bnx_success "User '$username' is ready!"
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_list_users() {
    bnx_banner
    bnx_header "User Management"
    echo ""
    user_list_all

    if (( $(user_count) > 0 )); then
        echo ""
        bnx_info "Total users: $(user_count) | Active: $(user_count_active)"
    fi
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_delete_user() {
    bnx_banner
    bnx_header "Delete User"
    echo ""
    bnx_prompt "Username to delete" "" "username"
    [[ -n "$username" ]] && user_delete "$username"
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_extend_user() {
    bnx_banner
    bnx_header "Extend User Expiry"
    echo ""
    bnx_prompt "Username" "" "username"
    bnx_prompt "Extra days" "30" "extra_days"
    [[ -n "$username" ]] && user_extend "$username" "${extra_days:-30}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

# ============================================================
# System Tool Menus
# ============================================================

menu_dns_cloudflare() {
    bnx_banner
    bnx_header "DNS & Cloudflare CDN"
    echo ""
    bnx_info "Configure DNS records for Cloudflare CDN fronting"
    echo ""

    local domain
    bnx_prompt "Your domain" "" "domain"
    [[ -n "$domain" ]] && {
        bnx_info "Cloudflare DNS Records:"
        echo -e "  ${BNX_CYAN}A Record:${BNX_RESET}   ${BNX_WHITE}${domain} → ${BNX_IPv4}${BNX_RESET}"
        echo -e "  ${BNX_CYAN}AAAA Record:${BNX_RESET} ${BNX_WHITE}${domain} → ${BNX_IPv6:-N/A}${BNX_RESET}"
        echo -e "  ${BNX_CYAN}Proxy:${BNX_RESET}       ${BNX_YELLOW}Enabled (orange cloud)${BNX_RESET}"
        echo ""
        bnx_info "Make sure SSL/TLS is set to 'Full' or 'Full (Strict)' in Cloudflare"
    }
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_cert_manager() {
    bnx_banner
    bnx_header "SSL Certificate Manager"
    echo ""

    local domain email
    bnx_prompt "Domain name" "" "domain"
    bnx_prompt "Email (for Let's Encrypt)" "admin@${domain}" "email"

    if [[ -n "$domain" ]]; then
        issue_certificate "$domain" "$email"
        echo ""
        bnx_info "Certificate files:"
        echo -e "  ${BNX_GRAY}/etc/letsencrypt/live/${domain}/fullchain.pem${BNX_RESET}"
        echo -e "  ${BNX_GRAY}/etc/letsencrypt/live/${domain}/privkey.pem${BNX_RESET}"

        # Set up auto-renewal cron
        echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx xray'" | crontab - 2>/dev/null
        bnx_success "Auto-renewal cron job added (daily at 3 AM)"
    fi
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_nginx_config() {
    bnx_banner
    bnx_header "Nginx Configuration"
    echo ""

    install_nginx >/dev/null 2>&1

    bnx_select "Action:" "View current config" "Add reverse proxy" "Add WebSocket proxy" "Restart Nginx"
    local action="$REPLY"

    case "$action" in
        "View current config")
            echo -e "\n${BNX_GRAY}$(cat /etc/nginx/nginx.conf 2>/dev/null)${BNX_RESET}\n"
            ;;
        "Add reverse proxy")
            bnx_prompt "Domain" "" "domain"
            bnx_prompt "Backend port" "8080" "backend_port"
            [[ -n "$domain" ]] && {
                cat > "/etc/nginx/conf.d/${domain}.conf" <<EOF
server {
    listen 80;
    server_name ${domain};
    location / {
        proxy_pass http://127.0.0.1:${backend_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
                nginx -t 2>/dev/null && restart_service nginx
                bnx_success "Reverse proxy configured: ${domain} → 127.0.0.1:${backend_port}"
            }
            ;;
        "Add WebSocket proxy")
            bnx_prompt "Domain" "" "domain"
            bnx_prompt "Backend port" "8080" "backend_port"
            bnx_prompt "WS path" "/" "ws_path"
            [[ -n "$domain" ]] && {
                cat > "/etc/nginx/conf.d/${domain}-ws.conf" <<EOF
server {
    listen 80;
    server_name ${domain};
    location ${ws_path} {
        proxy_pass http://127.0.0.1:${backend_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }
}
EOF
                nginx -t 2>/dev/null && restart_service nginx
                bnx_success "WebSocket proxy configured"
            }
            ;;
        "Restart Nginx")
            nginx -t 2>/dev/null && restart_service nginx
            bnx_success "Nginx restarted"
            ;;
    esac
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_telegram_bot() {
    bnx_banner
    bnx_header "Telegram Bot Setup"
    echo ""
    bnx_info "Connect BraanX to a Telegram bot for remote management"
    echo ""

    bnx_select "Action:" "Setup new bot" "Configure existing bot" "View bot status" "Remove bot"
    local action="$REPLY"

    case "$action" in
        "Setup new bot")
            bnx_prompt "Telegram Bot Token (from @BotFather)" "" "bot_token"
            bnx_prompt "Admin Chat ID (your Telegram user ID)" "" "admin_id"

            if [[ -n "$bot_token" && -n "$admin_id" ]]; then
                # Save config
                cat > "${BRAANX_DIR}/bot.conf" <<EOF
BOT_TOKEN=${bot_token}
ADMIN_ID=${admin_id}
BOT_ENABLED=true
NOTIFY_NEW_USER=true
NOTIFY_EXPIRY=true
NOTIFY_BAN=true
AUTO_CLEANUP=true
EOF
                chmod 600 "${BRAANX_DIR}/bot.conf"

                bnx_success "Bot configuration saved!"
                bnx_info "Starting Telegram bot..."
                bash "${SCRIPT_DIR}/bot/telegram-bot.sh" &
                echo "$!" > "${BRAANX_DIR}/bot.pid"
                log_event "BOT" "Telegram bot started"
            else
                bnx_error "Bot token and admin ID are required"
            fi
            ;;
        "Configure existing bot")
            bnx_info "Bot configuration:"
            [[ -f "${BRAANX_DIR}/bot.conf" ]] && {
                cat "${BRAANX_DIR}/bot.conf" | while read line; do
                    echo -e "  ${BNX_GRAY}${line}${BNX_RESET}"
                done
            } || bnx_error "No bot configuration found"
            ;;
        "View bot status")
            if [[ -f "${BRAANX_DIR}/bot.pid" ]] && kill -0 "$(cat ${BRAANX_DIR}/bot.pid)" 2>/dev/null; then
                bnx_success "Telegram bot is running (PID: $(cat ${BRAANX_DIR}/bot.pid))"
            else
                bnx_error "Telegram bot is not running"
            fi
            ;;
        "Remove bot")
            if [[ -f "${BRAANX_DIR}/bot.pid" ]]; then
                kill "$(cat ${BRAANX_DIR}/bot.pid)" 2>/dev/null
                rm -f "${BRAANX_DIR}/bot.pid"
            fi
            rm -f "${BRAANX_DIR}/bot.conf"
            bnx_success "Telegram bot removed"
            log_event "BOT" "Telegram bot removed"
            ;;
    esac
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_backup() {
    bnx_banner
    bnx_header "Backup with Rclone"
    echo ""

    bnx_select "Action:" "Setup Rclone remote" "Create backup now" "Schedule automatic backups" "View backup logs"
    local action="$REPLY"

    case "$action" in
        "Setup Rclone remote")
            pkg_install rclone 2>/dev/null
            bnx_info "Run 'rclone config' to set up your remote storage"
            bnx_prompt "Press Enter to run rclone config" "" "DUMMY"
            rclone config
            ;;
        "Create backup now")
            if command -v rclone &>/dev/null; then
                local backup_dir="/tmp/braanx-backup-$(date +%Y%m%d)"
                mkdir -p "$backup_dir"
                cp -r /etc/braanx "$backup_dir/" 2>/dev/null
                cp -r /etc/xray "$backup_dir/" 2>/dev/null
                cp /etc/nginx/conf.d/*.conf "$backup_dir/nginx/" 2>/dev/null
                rclone copy "$backup_dir" "braanx-backup:backup-$(date +%Y%m%d)" 2>/dev/null
                rm -rf "$backup_dir"
                bnx_success "Backup completed"
                log_event "BACKUP" "Manual backup completed"
            else
                bnx_error "Rclone not configured. Set it up first."
            fi
            ;;
        "Schedule automatic backups")
            bnx_prompt "Backup frequency (days)" "7" "freq"
            bnx_prompt "Rclone remote name" "braanx-backup" "remote"
            local cron_cmd="0 2 */${freq} * * rclone copy /etc/braanx ${remote}:backup-\$(date +\%Y\%m\%d) >> ${BNX_LOG_FILE} 2>&1"
            (crontab -l 2>/dev/null | grep -v "rclone"; echo "$cron_cmd") | crontab -
            bnx_success "Automatic backup scheduled every ${freq} days at 2 AM"
            ;;
        "View backup logs")
            rg "BACKUP" "$BNX_LOG_FILE" 2>/dev/null || echo -e "  ${BNX_GRAY}No backup logs found${BNX_RESET}"
            ;;
    esac
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_fail2ban() {
    bnx_banner
    bnx_header "Fail2ban / Security"
    echo ""

    pkg_install fail2ban 2>/dev/null
    bnx_select "Action:" "Install/Configure Fail2ban" "View banned IPs" "Unban an IP" "View fail2ban status"
    local action="$REPLY"

    case "$action" in
        "Install/Configure Fail2ban")
            cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

[sshd]
enabled = true
port = 22,2222,443
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5

[nginx-botsearch]
enabled = true
port = http,https
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400
EOF
            enable_service fail2ban
            bnx_success "Fail2ban configured and running"
            ;;
        "View banned IPs")
            fail2ban-client status sshd 2>/dev/null || bnx_error "Fail2ban not running"
            ;;
        "Unban an IP")
            bnx_prompt "IP to unban" "" "ban_ip"
            [[ -n "$ban_ip" ]] && fail2ban-client set sshd unbanip "$ban_ip" 2>/dev/null
            ;;
        "View fail2ban status")
            fail2ban-client status 2>/dev/null
            ;;
    esac
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_bbr_tuning() {
    bnx_banner
    bnx_header "BBR TCP Congestion Control"
    echo ""

    local current_cc
    current_cc=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')

    echo -e "  ${BNX_GRAY}Current:${BNX_RESET} ${BNX_WHITE}${current_cc}${BNX_RESET}"
    echo ""

    bnx_select "Select congestion control:" "BBR (recommended)" "Cubic (default)" "BBR + FQ-CoDel"

    case "$REPLY" in
        "BBR (recommended)")
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
            ;;
        "Cubic (default)")
            sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
            echo "net.core.default_qdisc=pfifo_fast" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
            ;;
        "BBR + FQ-CoDel")
            echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
            ;;
    esac

    # Additional TCP tuning
    cat >> /etc/sysctl.conf <<EOF
# BraanX TCP Optimization
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
EOF
    sysctl -p >/dev/null 2>&1

    bnx_success "TCP tuning applied"
    log_event "SYSTEM" "TCP tuning configured"
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_speedtest() {
    bnx_banner
    bnx_header "Speed Test"
    echo ""
    bnx_info "Running network speed test..."
    echo ""

    if ! command -v speedtest-cli &>/dev/null; then
        bnx_info "Installing speedtest-cli..."
        pip3 install speedtest-cli >/dev/null 2>&1 || {
            curl -L https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py -o /usr/local/bin/speedtest-cli
            chmod +x /usr/local/bin/speedtest-cli
        }
    fi

    speedtest-cli --simple 2>/dev/null && echo "" || {
        bnx_warning "Speed test failed. Checking basic connectivity..."
        local dl_speed=$(curl -o /dev/null -w "%{speed_download}" http://speedtest.tele2.net/10MB.zip 2>/dev/null)
        echo -e "  ${BNX_GRAY}Download speed: ${BNX_CYAN}$(echo "scale=2; $dl_speed / 1048576" | bc) MB/s${BNX_RESET}"
    }
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_system_monitor() {
    bnx_banner
    bnx_header "System Monitor"
    echo ""

    # Top processes
    echo -e "  ${BNX_BOLD}${BNX_CYAN}Top 10 Processes by CPU${BNX_RESET}"
    bnx_table_set_widths 20 8 8 8 20
    bnx_table_row "PROCESS" "CPU%" "MEM%" "PID" "USER"
    ps aux --sort=-%cpu | head -11 | tail -10 | while read line; do
        local proc=$(echo "$line" | awk '{print $11}' | xargs basename 2>/dev/null)
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local pid=$(echo "$line" | awk '{print $2}')
        local user=$(echo "$line" | awk '{print $1}')
        bnx_table_row "$proc" "$cpu" "$mem" "$pid" "$user"
    done

    echo ""
    echo -e "  ${BNX_BOLD}${BNX_CYAN}Network Connections${BNX_RESET}"
    local established=$(ss -s 2>/dev/null | grep 'estab' | awk '{print $4}')
    local total_conn=$(ss -s 2>/dev/null | grep 'estab' | awk '{print $6}')
    echo -e "  ${BNX_GRAY}Established:${BNX_RESET} ${BNX_GREEN}${established:-0}${BNX_RESET} ${BNX_GRAY}│ Total:${BNX_RESET} ${BNX_WHITE}${total_conn:-0}${BNX_RESET}"

    echo ""
    echo -e "  ${BNX_BOLD}${BNX_CYAN}Listening Ports${BNX_RESET}"
    bnx_table_set_widths 6 6 15 20
    bnx_table_row "PROTO" "PORT" "PROCESS" "ADDRESS"
    ss -tlnp 2>/dev/null | tail -n +2 | while read line; do
        local proto=$(echo "$line" | awk '{print $1}')
        local addr_port=$(echo "$line" | awk '{print $4}')
        local port=$(echo "$addr_port" | rev | cut -d: -f1 | rev)
        local bind_addr=$(echo "$addr_port" | rev | cut -d: -f2- | rev)
        local proc=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' | head -1)
        [[ -z "$proc" ]] && proc=$(echo "$line" | awk '{print $NF}' | grep -oP '[^\d]+$')
        bnx_table_row "$proto" "$port" "${proc:-N/A}" "$bind_addr"
    done

    echo ""
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_view_logs() {
    bnx_banner
    bnx_header "System Logs"
    echo ""

    local entries
    entries=$(get_log_entries 30)

    if [[ -n "$entries" ]]; then
        echo -e "$entries" | while read line; do
            echo -e "  ${BNX_DIM}${line}${BNX_RESET}"
        done
    else
        bnx_info "No logs found"
    fi

    echo ""
    bnx_info "Log file: ${BNX_LOG_FILE}"
    bnx_prompt "Press Enter" "" "DUMMY"
}

menu_uninstall() {
    bnx_banner
    bnx_header "Uninstall BraanX"
    echo ""
    bnx_warning "This will remove ALL BraanX configurations, users, and services!"
    echo ""

    if ! bnx_confirm "Are you sure you want to uninstall?" n; then
        return
    fi

    if ! bnx_confirm "This is irreversible. Continue?" n; then
        return
    fi

    bnx_info "Stopping all BraanX services..."
    stop_service xray 2>/dev/null
    stop_service nginx 2>/dev/null
    stop_service dropbear 2>/dev/null
    stop_service fail2ban 2>/dev/null

    # Kill Telegram bot
    if [[ -f "${BRAANX_DIR}/bot.pid" ]]; then
        kill "$(cat ${BRAANX_DIR}/bot.pid)" 2>/dev/null
    fi

    bnx_info "Removing BraanX files..."
    rm -rf /etc/braanx
    rm -rf /etc/xray
    rm -rf /usr/local/xray

    # Remove Nginx configs
    rm -f /etc/nginx/conf.d/ssh-ws.conf
    rm -f /etc/nginx/conf.d/vless-ws.conf
    rm -f /etc/nginx/conf.d/braanx*.conf
    nginx -t 2>/dev/null && restart_service nginx 2>/dev/null

    bnx_success "BraanX has been uninstalled"
    bnx_prompt "Press Enter" "" "DUMMY"
    exit 0
}

# ============================================================
# Run
# ============================================================

main "$@"
