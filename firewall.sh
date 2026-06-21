#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - IPTables / NFT Firewall Manager
# Version: 1.0.0
# ============================================================

readonly BNX_FW_RULES="/etc/braanx/firewall.rules"

apply_firewall_base() {
    bnx_info "Applying base firewall rules..."

    # Flush existing rules
    iptables -F INPUT 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    iptables -F OUTPUT 2>/dev/null

    # Default policies
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow SSH
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT

    # Allow HTTP/HTTPS
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8444 -j ACCEPT
    iptables -A INPUT -p tcp --dport 8445 -j ACCEPT

    # Allow ICMP (ping)
    iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT

    # Allow DNS
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT

    # Allow VPN ports
    iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    iptables -A INPUT -p tcp --dport 1194 -j ACCEPT
    iptables -A INPUT -p udp --dport 51820 -j ACCEPT
    iptables -A INPUT -p udp --dport 7300 -j ACCEPT

    # NAT for VPN
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -j ACCEPT

    # Log dropped packets
    iptables -A INPUT -j LOG --log-prefix "BNX-DROP: " --log-level 4

    # Save rules
    if command -v iptables-save &>/dev/null; then
        iptables-save > "$BNX_FW_RULES"
    fi

    bnx_success "Firewall rules applied and saved"
}
