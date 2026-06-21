#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - OS & Architecture Detection
# Version: 1.0.0
# ============================================================

# Prevent source from running twice
[[ -n "$_BNX_OS_LOADED" ]] && return 0
_BNX_OS_LOADED=1

# ============================================================
# OS Detection
# ============================================================

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        BNX_OS_ID="${ID}"
        BNX_OS_NAME="${PRETTY_NAME:-$NAME}"
        BNX_OS_VERSION="${VERSION_ID}"
        BNX_OS_LIKE="${ID_LIKE:-}"

        # Normalize OS families
        case "$BNX_OS_ID" in
            debian|ubuntu|linuxmint|pop)
                BNX_OS_FAMILY="debian"
                BNX_PKG_MANAGER="apt"
                BNX_PKG_UPDATE="apt-get update -y"
                BNX_PKG_INSTALL="apt-get install -y"
                BNX_PKG_REMOVE="apt-get remove -y"
                ;;
            centos|rhel|rocky|almalinux|ol)
                BNX_OS_FAMILY="rhel"
                BNX_PKG_MANAGER="dnf"
                BNX_PKG_UPDATE="dnf update -y"
                BNX_PKG_INSTALL="dnf install -y"
                BNX_PKG_REMOVE="dnf remove -y"
                ;;
            fedora)
                BNX_OS_FAMILY="fedora"
                BNX_PKG_MANAGER="dnf"
                BNX_PKG_UPDATE="dnf update -y"
                BNX_PKG_INSTALL="dnf install -y"
                BNX_PKG_REMOVE="dnf remove -y"
                ;;
            arch|manjaro|endeavouros)
                BNX_OS_FAMILY="arch"
                BNX_PKG_MANAGER="pacman"
                BNX_PKG_UPDATE="pacman -Sy --noconfirm"
                BNX_PKG_INSTALL="pacman -S --noconfirm"
                BNX_PKG_REMOVE="pacman -R --noconfirm"
                ;;
            opensuse*|sles)
                BNX_OS_FAMILY="suse"
                BNX_PKG_MANAGER="zypper"
                BNX_PKG_UPDATE="zypper refresh"
                BNX_PKG_INSTALL="zypper install -y"
                BNX_PKG_REMOVE="zypper remove -y"
                ;;
            alpine)
                BNX_OS_FAMILY="alpine"
                BNX_PKG_MANAGER="apk"
                BNX_PKG_UPDATE="apk update"
                BNX_PKG_INSTALL="apk add"
                BNX_PKG_REMOVE="apk del"
                ;;
            *)
                bnx_error "Unsupported OS: $BNX_OS_NAME"
                exit 1
                ;;
        esac
    else
        bnx_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    export BNX_OS_ID BNX_OS_NAME BNX_OS_VERSION BNX_OS_LIKE
    export BNX_OS_FAMILY BNX_PKG_MANAGER BNX_PKG_UPDATE BNX_PKG_INSTALL BNX_PKG_REMOVE
}

# ============================================================
# Architecture Detection
# ============================================================

detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            BNX_ARCH="amd64"
            BNX_ARCH_ALT="x86_64"
            BNX_ARCH_NAME="64-bit Intel/AMD"
            ;;
        aarch64|arm64)
            BNX_ARCH="arm64"
            BNX_ARCH_ALT="aarch64"
            BNX_ARCH_NAME="64-bit ARM"
            ;;
        armv7l|armv7)
            BNX_ARCH="armv7"
            BNX_ARCH_ALT="armv7"
            BNX_ARCH_NAME="32-bit ARM"
            ;;
        i686|i386)
            BNX_ARCH="386"
            BNX_ARCH_ALT="i686"
            BNX_ARCH_NAME="32-bit Intel"
            ;;
        riscv64)
            BNX_ARCH="riscv64"
            BNX_ARCH_ALT="riscv64"
            BNX_ARCH_NAME="RISC-V 64"
            ;;
        *)
            bnx_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    export BNX_ARCH BNX_ARCH_ALT BNX_ARCH_NAME
}

# ============================================================
# Virtualization Detection
# ============================================================

detect_virt() {
    if command -v systemd-detect-virt &>/dev/null; then
        BNX_VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || echo "none")
    elif [[ -f /proc/1/cgroup ]] && grep -qE 'docker|lxc|containerd' /proc/1/cgroup 2>/dev/null; then
        BNX_VIRT_TYPE="container"
    elif [[ -f /.dockerenv ]]; then
        BNX_VIRT_TYPE="docker"
    else
        BNX_VIRT_TYPE="dedicated"
    fi

    case "$BNX_VIRT_TYPE" in
        kvm|vmware|qemu|xen|oracle|virtualbox)
            BNX_VIRT_DISPLAY="Virtual Machine (KVM/QEMU/XEN)"
            ;;
        docker|lxc|containerd|openvz)
            BNX_VIRT_DISPLAY="Container (${BNX_VIRT_TYPE})"
            ;;
        none|dedicated)
            BNX_VIRT_DISPLAY="Dedicated / Bare Metal"
            ;;
        *)
            BNX_VIRT_DISPLAY="${BNX_VIRT_TYPE}"
            ;;
    esac

    export BNX_VIRT_TYPE BNX_VIRT_DISPLAY
}

# ============================================================
# System Info Gathering
# ============================================================

get_system_info() {
    BNX_IPv4=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 ip.sb 2>/dev/null || \
                curl -4 -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                echo "N/A")

    BNX_IPv6=$(curl -6 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -6 -s --max-time 5 ip.sb 2>/dev/null || \
                echo "N/A")

    BNX_PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                    curl -s --max-time 5 ip.sb 2>/dev/null || \
                    echo "N/A")

    if command -v free &>/dev/null; then
        BNX_TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
        BNX_USED_RAM=$(free -m | awk '/Mem:/ {print $3}')
        BNX_RAM_DISPLAY="${BNX_USED_RAM}MB / ${BNX_TOTAL_RAM}MB"
    else
        BNX_TOTAL_RAM="N/A"
        BNX_USED_RAM="N/A"
        BNX_RAM_DISPLAY="N/A"
    fi

    if [[ -f /proc/cpuinfo ]]; then
        BNX_CPU_CORES=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo "N/A")
        BNX_CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "N/A")
    else
        BNX_CPU_CORES="N/A"
        BNX_CPU_MODEL="N/A"
    fi

    BNX_UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/' || echo "N/A")
    BNX_HOSTNAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "N/A")

    # Disk usage
    BNX_DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
    BNX_DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
    BNX_DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
    BNX_DISK_PCT=$(df -h / | awk 'NR==2 {print $5}')

    export BNX_IPv4 BNX_IPv6 BNX_PUBLIC_IP BNX_TOTAL_RAM BNX_USED_RAM BNX_RAM_DISPLAY
    export BNX_CPU_CORES BNX_CPU_MODEL BNX_UPTIME BNX_HOSTNAME
    export BNX_DISK_TOTAL BNX_DISK_USED BNX_DISK_AVAIL BNX_DISK_PCT
}

# ============================================================
# System Requirements Check
# ============================================================

check_requirements() {
    local errors=0

    # Check root
    if [[ $EUID -ne 0 ]]; then
        bnx_error "This script must be run as root!"
        exit 1
    fi

    # Check minimum RAM (256MB)
    if [[ "$BNX_TOTAL_RAM" != "N/A" ]] && (( BNX_TOTAL_RAM < 256 )); then
        bnx_warning "Low memory detected (${BNX_TOTAL_RAM}MB). Some features may not work."
    fi

    # Check disk space (minimum 2GB free)
    if [[ "$BNX_DISK_AVAIL" != "N/A" ]]; then
        local avail_kb
        avail_kb=$(df -k / | awk 'NR==2 {print $4}')
        if (( avail_kb < 2097152 )); then
            bnx_error "Insufficient disk space. At least 2GB free required."
            ((errors++))
        fi
    fi

    # Check internet connectivity
    if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        if ! curl -s --max-time 5 https://www.google.com &>/dev/null; then
            bnx_error "No internet connectivity detected!"
            ((errors++))
        fi
    fi

    # Check required tools
    local required_tools=("curl" "wget" "unzip" "tar" "systemctl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            bnx_warning "Required tool missing: $tool (will be installed)"
        fi
    done

    return $errors
}

# ============================================================
# Print System Summary
# ============================================================

print_system_info() {
    bnx_subheader "System Information"
    echo -e "  ${BNX_GRAY}  OS${BNX_RESET}          ${BNX_WHITE}${BNX_OS_NAME} (${BNX_OS_VERSION})${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Kernel${BNX_RESET}       ${BNX_WHITE}$(uname -r)${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Arch${BNX_RESET}         ${BNX_WHITE}${BNX_ARCH_NAME} [${BNX_ARCH_ALT}]${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Virt${BNX_RESET}         ${BNX_WHITE}${BNX_VIRT_DISPLAY}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  IPv4${BNX_RESET}         ${BNX_CYAN}${BNX_IPv4}${BNX_RESET}"
    [[ "$BNX_IPv6" != "N/A" ]] && echo -e "  ${BNX_GRAY}  IPv6${BNX_RESET}         ${BNX_CYAN}${BNX_IPv6}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Hostname${BNX_RESET}     ${BNX_WHITE}${BNX_HOSTNAME}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  CPU${BNX_RESET}          ${BNX_WHITE}${BNX_CPU_CORES} cores — ${BNX_CPU_MODEL}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  RAM${BNX_RESET}          ${BNX_WHITE}${BNX_RAM_DISPLAY}${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Disk${BNX_RESET}         ${BNX_WHITE}${BNX_DISK_USED} / ${BNX_DISK_TOTAL} (${BNX_DISK_PCT})${BNX_RESET}"
    echo -e "  ${BNX_GRAY}  Uptime${BNX_RESET}        ${BNX_WHITE}${BNX_UPTIME}${BNX_RESET}"
    echo ""
}

# ============================================================
# Init: detect everything on source
# ============================================================

init_system_detection() {
    detect_os
    detect_arch
    detect_virt
    get_system_info
}
