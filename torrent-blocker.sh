#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - Torrent/Abuse Blocker
# IP/domain/hash-based traffic blocker
# Version: 1.0.0
# ============================================================

readonly BNX_BLOCK_DIR="/etc/braanx/blocker"
readonly BNX_BLOCK_LIST_IP="${BNX_BLOCK_DIR}/ip-block.list"
readonly BNX_BLOCK_LIST_DOMAIN="${BNX_BLOCK_DIR}/domain-block.list"

init_torrent_blocker() {
    mkdir -p "$BNX_BLOCK_DIR"
    touch "$BNX_BLOCK_LIST_IP" "$BNX_BLOCK_LIST_DOMAIN"

    bnx_info "Torrent blocker initialized at ${BNX_BLOCK_DIR}"
}

block_torrent() {
    init_torrent_blocker

    local ip_list_url="https://raw.githubusercontent.com/ngosang/trackerslist/master/trackers_all.txt"
    local blocklist_urls=(
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
        "https://www.i2p2.de/torrent-blocklist"
    )

    bnx_info "Downloading IP blocklists..."

    # Download and merge IP blocklists
    for url in "${blocklist_urls[@]}"; do
        curl -s -L "$url" >> "$BNX_BLOCK_LIST_IP" 2>/dev/null
    done

    # Apply to iptables
    if [[ -s "$BNX_BLOCK_LIST_IP" ]]; then
        iptables -N TORRENT_BLOCK 2>/dev/null
        iptables -F TORRENT_BLOCK 2>/dev/null

        while read -r ip; do
            [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]] && {
                iptables -A TORRENT_BLOCK -s "$ip" -j DROP
                iptables -A TORRENT_BLOCK -d "$ip" -j DROP
            }
        done < "$BNX_BLOCK_LIST_IP"

        iptables -I FORWARD -j TORRENT_BLOCK
        bnx_success "Torrent IP blocklist applied ($(wc -l < "$BNX_BLOCK_LIST_IP") IPs blocked)"
    fi
}

unblock_torrent() {
    iptables -D FORWARD -j TORRENT_BLOCK 2>/dev/null
    iptables -F TORRENT_BLOCK 2>/dev/null
    iptables -X TORRENT_BLOCK 2>/dev/null
    bnx_success "Torrent blocker removed"
}
