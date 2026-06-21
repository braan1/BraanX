#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - One-Line Installer
#
# INSTALLATION:
#   bash <(curl -sL https://raw.githubusercontent.com/braanx/braanx/main/install.sh)
#
# Or download manually:
#   wget https://raw.githubusercontent.com/braanx/braanx/main/install.sh
#   bash install.sh
#
# ============================================================

set -euo pipefail

# Colors for installer
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

BRAANX_VERSION="1.0.0"
BRAANX_REPO="https://github.com/braanx/braanx"
BRAANX_RAW="${BRAANX_REPO}/raw/main"
BRAANX_DIR="/etc/braanx"

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Pre-flight checks
# ============================================================

if [[ $EUID -ne 0 ]]; then
    err "Must run as root!"
    echo -e "${WHITE}Run: sudo bash install.sh${NC}"
    exit 1
fi

if ! curl -s --max-time 5 https://www.google.com &>/dev/null; then
    err "No internet connectivity detected!"
    exit 1
fi

info "Starting BraanX v${BRAANX_VERSION} installation..."

# Detect OS
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_FAMILY="${ID_LIKE:-$ID}"
    case "$ID" in
        debian|ubuntu|linuxmint|pop) PKG_MGR="apt" ;;
        centos|rhel|rocky|almalinux) PKG_MGR="dnf" ;;
        fedora) PKG_MGR="dnf" ;;
        arch|manjaro) PKG_MGR="pacman" ;;
        opensuse*|sles) PKG_MGR="zypper" ;;
        alpine) PKG_MGR="apk" ;;
        *) err "Unsupported OS: $PRETTY_NAME"; exit 1 ;;
    esac
else
    err "Cannot detect operating system"
    exit 1
fi

ok "OS detected: $PRETTY_NAME ($PKG_MGR)"
ok "Architecture: $(uname -m)"

# ============================================================
# Install base dependencies
# ============================================================

info "Installing base dependencies..."
case "$PKG_MGR" in
    apt)
        apt-get update -y -qq
        apt-get install -y -qq curl wget unzip tar jq socat cron >/dev/null 2>&1
        ;;
    dnf)
        dnf update -y -q >/dev/null 2>&1
        dnf install -y -q curl wget unzip tar jq socat cronie >/dev/null 2>&1
        ;;
    pacman)
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed curl wget unzip tar jq socat cronie >/dev/null 2>&1
        ;;
    zypper)
        zypper refresh >/dev/null 2>&1
        zypper --non-interactive install curl wget unzip tar jq socat cron >/dev/null 2>&1
        ;;
esac
ok "Dependencies installed"

# ============================================================
# Download BraanX
# ============================================================

mkdir -p "$BRAANX_DIR"
info "Downloading BraanX v${BRAANX_VERSION}..."

# Download main script
curl -L -o "/usr/local/bin/braanx" "${BRAANX_RAW}/braanx.sh" --progress-bar 2>&1 || {
    # Fallback: if GitHub is not available, look for local files
    if [[ -f "./braanx.sh" ]]; then
        cp ./braanx.sh /usr/local/bin/braanx
    else
        err "Failed to download BraanX. Check your internet connection."
        exit 1
    fi
}
chmod +x /usr/local/bin/braanx
ok "Main script installed"

# Download library files
mkdir -p "${BRAANX_DIR}/lib"
mkdir -p "${BRAANX_DIR}/bot"
mkdir -p "${BRAANX_DIR}/utils"
mkdir -p "${BRAANX_DIR}/modules"

for lib_file in colors.sh os-detect.sh package.sh user-db.sh; do
    curl -L -o "${BRAANX_DIR}/lib/${lib_file}" "${BRAANX_RAW}/lib/${lib_file}" --progress-bar 2>&1 || {
        if [[ -f "./lib/${lib_file}" ]]; then
            cp "./lib/${lib_file}" "${BRAANX_DIR}/lib/${lib_file}"
        fi
    }
done

# Download Telegram bot
curl -L -o "${BRAANX_DIR}/bot/telegram-bot.sh" "${BRAANX_RAW}/bot/telegram-bot.sh" --progress-bar 2>&1 || {
    [[ -f "./bot/telegram-bot.sh" ]] && cp ./bot/telegram-bot.sh "${BRAANX_DIR}/bot/telegram-bot.sh"
}
chmod +x "${BRAANX_DIR}/bot/telegram-bot.sh" 2>/dev/null

# Download utilities
for util in torrent-blocker.sh firewall.sh cron-maintenance.sh; do
    curl -L -o "${BRAANX_DIR}/utils/${util}" "${BRAANX_RAW}/utils/${util}" --progress-bar 2>&1 || {
        [[ -f "./utils/${util}" ]] && cp "./utils/${util}" "${BRAANX_DIR}/utils/${util}"
    }
done
chmod +x "${BRAANX_DIR}/utils/"*.sh 2>/dev/null

ok "All BraanX components downloaded"

# ============================================================
# Setup cron jobs
# ============================================================

info "Setting up scheduled tasks..."

# Every 6 hours: check expired users + notify
(crontab -l 2>/dev/null | grep -v "braanx"; echo "0 */6 * * * bash ${BRAANX_DIR}/utils/cron-maintenance.sh") | crontab -

ok "Cron jobs configured"

# ============================================================
# Create init marker
# ============================================================

date -Iseconds > "${BRAANX_DIR}/.installed"
echo "$BRAANX_VERSION" > "${BRAANX_DIR}/.version"
touch "${BRAANX_DIR}/braanx.db"
mkdir -p "${BRAANX_DIR}/users"

ok "BraanX v${BRAANX_VERSION} installed successfully!"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ██████╗ ███████╗  BraanX v${BRAANX_VERSION} installed!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${WHITE}  Launch BraanX:${NC}       ${CYAN}braanx${NC}"
echo -e "${WHITE}  Or:${NC}                  ${CYAN}bash /usr/local/bin/braanx${NC}"
echo ""
echo -e "${WHITE}  Quick Start:${NC}"
echo -e "    1. Run ${CYAN}braanx${NC}"
echo -e "    2. Choose ${CYAN}1${NC} to install all services"
echo -e "    3. Choose ${CYAN}18${NC} to create VPN users"
echo -e "    4. Choose ${CYAN}25${NC} to connect Telegram bot"
echo ""
echo -e "${WHITE}  Telegram Bot:${NC}        ${CYAN}Get token from @BotFather${NC}"
echo -e "${WHITE}  GitHub:${NC}              ${CYAN}${BRAANX_REPO}${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Launch BraanX
if [[ "${1:-}" != "--no-launch" ]]; then
    exec /usr/local/bin/braanx
fi
