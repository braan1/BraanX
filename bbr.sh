#!/bin/bash
# ============================================================================
# BraanX - TCP BBR Congestion Control Tuning
# ============================================================================
# Enables TCP BBR congestion control algorithm and optimizes kernel
# networking parameters for improved throughput and latency.
# ============================================================================
# Source: /etc/braanx/lib/functions.sh
# Config: /etc/braanx/braanx.conf
# ============================================================================
source /etc/braanx/lib/functions.sh

SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_D_DIR="/etc/sysctl.d"

# ----------------------------------------------------------------------------
# install_bbr() - Enable TCP BBR and apply kernel network optimizations
# ----------------------------------------------------------------------------
install_bbr() {
    msg_info "Installing TCP BBR congestion control..."

    # --- Check kernel version ---
    local kernel_version
    kernel_version=$(uname -r | cut -d. -f1-2)
    local kernel_major
    local kernel_minor
    kernel_major=$(echo "${kernel_version}" | cut -d. -f1)
    kernel_minor=$(echo "${kernel_version}" | cut -d. -f2)

    if [[ ${kernel_major} -lt 4 ]] || [[ ${kernel_major} -eq 4 && ${kernel_minor} -lt 9 ]]; then
        msg_err "Kernel version ${kernel_version} is too old. BBR requires kernel >= 4.9"
        return 1
    fi
    msg_info "Kernel version: $(uname -r) (compatible)"

    # Backup sysctl.conf
    cp -f "${SYSCTL_CONF}" "${SYSCTL_CONF}.bak" 2>/dev/null

    # --- Remove old BBR settings to avoid duplicates ---
    sed -i '/net.core.default_qdisc=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.tcp_congestion_control=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.tcp_slow_start_after_idle=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.tcp_mtu_probing=/d' "${SYSCTL_CONF}"
    sed -i '/net.core.rmem_max=/d' "${SYSCTL_CONF}"
    sed -i '/net.core.wmem_max=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.tcp_rmem=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.tcp_wmem=/d' "${SYSCTL_CONF}"
    sed -i '/net.ipv4.ip_local_port_range=/d' "${SYSCTL_CONF}"

    # --- Write BBR and network optimizations ---
    cat >> "${SYSCTL_CONF}" << EOF

# BraanX - TCP BBR Congestion Control
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr

# TCP optimizations
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1

# Buffer sizes (16 MB)
net.core.rmem_max=16777216
net.core.wmem_max=16777216

# TCP buffer sizes: min default max
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Local port range
net.ipv4.ip_local_port_range=1024 65535

# Connection tracking
net.netfilter.nf_conntrack_max=1048576
EOF

    # --- Apply settings ---
    msg_info "Applying sysctl settings..."
    sysctl -p "${SYSCTL_CONF}" 2>/dev/null

    # --- Save iptables rules ---
    _save_iptables

    # Verify BBR is active
    verify_bbr

    msg_ok "TCP BBR installed and configured"
}

# ----------------------------------------------------------------------------
# verify_bbr() - Check if BBR is active and report status
# ----------------------------------------------------------------------------
verify_bbr() {
    draw_header "TCP BBR STATUS"

    # Check if BBR module is loaded
    local bbr_loaded
    bbr_loaded=$(lsmod 2>/dev/null | rg -c "^tcp_bbr")
    if [[ ${bbr_loaded} -eq 0 ]]; then
        # Try to load the module
        modprobe tcp_bbr 2>/dev/null
        bbr_loaded=$(lsmod 2>/dev/null | rg -c "^tcp_bbr")
    fi

    if [[ ${bbr_loaded} -gt 0 ]]; then
        msg_ok "tcp_bbr kernel module loaded"
    else
        msg_warn "tcp_bbr module not loaded (may be built-in)"
    fi

    # Check available congestion algorithms
    local available
    available=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null)
    msg_info "Available algorithms: ${available}"

    if echo "${available}" | rg -q "bbr"; then
        msg_ok "BBR is available"
    else
        msg_err "BBR is NOT available in this kernel"
        return 1
    fi

    # Check current active algorithm
    local active
    active=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null)
    if [[ "${active}" == "bbr" ]]; then
        msg_ok "BBR is the ACTIVE congestion control algorithm"
    else
        msg_warn "Active algorithm: ${active} (expected bbr)"
    fi

    # Check default qdisc
    local qdisc
    qdisc=$(cat /proc/sys/net/core/default_qdisc 2>/dev/null)
    if [[ "${qdisc}" == "fq" ]]; then
        msg_ok "Default qdisc: fq (optimal for BBR)"
    else
        msg_warn "Default qdisc: ${qdisc} (recommended: fq)"
    fi

    # Show current values
    echo ""
    local tcp_rmem
    local tcp_wmem
    local rmem_max
    local wmem_max
    local port_range

    tcp_rmem=$(cat /proc/sys/net/ipv4/tcp_rmem 2>/dev/null)
    tcp_wmem=$(cat /proc/sys/net/ipv4/tcp_wmem 2>/dev/null)
    rmem_max=$(cat /proc/sys/net/core/rmem_max 2>/dev/null)
    wmem_max=$(cat /proc/sys/net/core/wmem_max 2>/dev/null)
    port_range=$(cat /proc/sys/net/ipv4/ip_local_port_range 2>/dev/null)

    draw_table \
        "tcp_congestion_control" "${active}" \
        "default_qdisc" "${qdisc}" \
        "tcp_rmem" "${tcp_rmem}" \
        "tcp_wmem" "${tcp_wmem}" \
        "rmem_max" "${rmem_max}" \
        "wmem_max" "${wmem_max}" \
        "port_range" "${port_range}"
    echo ""
}

# ----------------------------------------------------------------------------
# _save_iptables() - Persist iptables rules
# ----------------------------------------------------------------------------
_save_iptables() {
    # Ensure netfilter-persistent is available
    if command -v netfilter-persistent &>/dev/null; then
        msg_info "Saving iptables rules..."
        netfilter-persistent save 2>/dev/null
    else
        # Fallback: save manually
        mkdir -p /etc/iptables
        pkg_install iptables-persistent 2>/dev/null
        if [[ -f /usr/sbin/netfilter-persistent ]]; then
            netfilter-persistent save 2>/dev/null
        else
            # Last resort: direct save
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
        fi
    fi
}

# ============================================================================
# Export all functions
# ============================================================================
export -f install_bbr
export -f verify_bbr
export -f _save_iptables
