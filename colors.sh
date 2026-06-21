#!/bin/bash
# ============================================================
# BraanX VPN Autoscript - Colors & UI Theme
# Version: 1.0.0
# ============================================================

# --- True Color Support ---
if [[ -t 1 ]] && [[ $(tput colors 2>/dev/null || echo 0) -ge 256 ]]; then
    _BRAANX_256=1
else
    _BRAANX_256=0
fi

# --- Primary Color Palette ---
readonly BNX_BG='\033[48;2;13;17;23m'          # Dark navy background
readonly BNX_BG2='\033[48;2;22;27;34m'          # Slightly lighter bg
readonly BNX_BG3='\033[48;2;30;38;50m'          # Card background
readonly BNX_WHITE='\033[38;2;255;255;255m'      # Pure white text
readonly BNX_GRAY='\033[38;2;148;163;184m'       # Muted gray
readonly BNX_DIM='\033[38;2;88;101;125m'          # Dim text
readonly BNX_CYAN='\033[38;2;56;189;248m'         # Bright cyan accent
readonly BNX_BLUE='\033[38;2;96;165;250m'        # Blue accent
readonly BNX_GREEN='\033[38;2;74;222;128m'        # Success green
readonly BNX_RED='\033[38;2;248;113;113m'         # Error red
readonly BNX_YELLOW='\033[38;2;250;204;21m'       # Warning yellow
readonly BNX_ORANGE='\033[38;2;251;146;60m'       # Orange accent
readonly BNX_PURPLE='\033[38;2;192;132;252m'      # Purple accent
readonly BNX_PINK='\033[38;2;244;114;182m'        # Pink accent

# --- Formatting ---
readonly BNX_BOLD='\033[1m'
readonly BNX_DIM_F='\033[2m'
readonly BNX_RESET='\033[0m'
readonly BNX_CLR_LINE='\033[2K'
readonly BNX_MOVE_UP='\033[1A'

# --- Box Drawing Characters (Unicode) ---
readonly BNX_TL='┌' BNX_TR='┐' BNX_BL='└' BNX_BR='┘'
readonly BNX_HZ='─' BNX_VT='│'
readonly BNX_LT='├' BNX_RT='┤' BNX_MID='┬' BNX_BOT='┴' BNX_CROSS='┼'

# --- Spinner Characters ---
readonly BNX_SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ============================================================
# UI Helper Functions
# ============================================================

# Print a styled header bar
bnx_header() {
    local title="${1:-BraanX VPN Manager}"
    local width="${2:-60}"
    local padding=$(( (width - ${#title} - 2) / 2 ))
    local pad_left=$(( padding ))
    local pad_right=$(( width - ${#title} - 2 - padding ))

    echo ""
    echo -e "${BNX_CYAN}${BNX_TL}$(printf '%*s' "$((width-1))" '' | tr ' ' "${BNX_HZ}")${BNX_TR}${BNX_RESET}"
    echo -e "${BNX_CYAN}${BNX_VT}${BNX_RESET}$(printf '%*s' "$pad_left" '')${BNX_BOLD}${BNX_WHITE}${title}$(printf '%*s' "$pad_right" '')${BNX_RESET}${BNX_CYAN}${BNX_VT}${BNX_RESET}"
    echo -e "${BNX_CYAN}${BNX_BL}$(printf '%*s' "$((width-1))" '' | tr ' ' "${BNX_HZ}")${BNX_BR}${BNX_RESET}"
    echo ""
}

# Print a styled sub-header
bnx_subheader() {
    local title="${1}"
    echo -e "  ${BNX_BOLD}${BNX_CYAN}▸ ${title}${BNX_RESET}"
    echo -e "  ${BNX_DIM}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_HZ}${BNX_RESET}"
}

# Print a menu item with number
bnx_menu_item() {
    local num="${1}"
    local text="${2}"
    local color="${3:-$BNX_WHITE}"
    printf "  ${BNX_BOLD}${BNX_CYAN}%2s)${BNX_RESET} ${color}%s${BNX_RESET}\n" "$num" "$text"
}

# Print a sub-menu item (letter-based)
bnx_submenu_item() {
    local letter="${1}"
    local text="${2}"
    local color="${3:-$BNX_GRAY}"
    printf "     ${BNX_YELLOW}${letter})${BNX_RESET} ${color}%s${BNX_RESET}\n" "$text"
}

# Print an info line with icon
bnx_info() {
    local text="${1}"
    echo -e "  ${BNX_BLUE}ℹ ${BNX_RESET}${BNX_GRAY}${text}${BNX_RESET}"
}

# Print success message
bnx_success() {
    local text="${1}"
    echo -e "  ${BNX_GREEN}✔ ${BNX_RESET}${BNX_GREEN}${text}${BNX_RESET}"
}

# Print warning message
bnx_warning() {
    local text="${1}"
    echo -e "  ${BNX_YELLOW}⚠ ${BNX_RESET}${BNX_YELLOW}${text}${BNX_RESET}"
}

# Print error message
bnx_error() {
    local text="${1}"
    echo -e "  ${BNX_RED}✘ ${BNX_RESET}${BNX_RED}${text}${BNX_RESET}"
}

# Print a separator line
bnx_separator() {
    local width="${1:-60}"
    echo -e "  ${BNX_DIM}$(printf '%*s' "$width" '' | tr ' ' "${BNX_HZ}")${BNX_RESET}"
}

# Animated spinner for long operations
bnx_spinner() {
    local message="${1}"
    local pid="${2}"
    local spin_idx=0
    local spin_len=${#BNX_SPINNER[@]}

    # Hide cursor
    tput civis 2>/dev/null

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BNX_CYAN}${BNX_SPINNER[$spin_idx]}${BNX_RESET} ${BNX_GRAY}${message}...${BNX_RESET}" >&2
        spin_idx=$(( (spin_idx + 1) % spin_len ))
        sleep 0.08
    done

    # Show cursor
    tput cnorm 2>/dev/null
    printf "\r  ${BNX_GREEN}✔${BNX_RESET} ${BNX_WHITE}${message}${BNX_RESET}    \n" >&2
}

# Simple progress bar
bnx_progress() {
    local current="${1}"
    local total="${2}"
    local label="${3}"
    local width=40
    local pct=$(( (current * 100) / total ))
    local filled=$(( (current * width) / total ))
    local empty=$(( width - filled ))

    printf "\r  ${BNX_CYAN}${label}${BNX_RESET} ["
    printf "${BNX_GREEN}%*s${BNX_RESET}" "$filled" '' | tr ' ' '█'
    printf "${BNX_DIM}%*s${BNX_RESET}" "$empty" '' | tr ' ' '░'
    printf "] ${BNX_WHITE}%3d%%${BNX_RESET}" "$pct"
}

# Prompt for input with styled prompt
bnx_prompt() {
    local message="${1}"
    local default="${2:-}"
    local var_name="${3:-REPLY}"
    local prompt_str

    if [[ -n "$default" ]]; then
        prompt_str="  ${BNX_CYAN}→${BNX_RESET} ${BNX_WHITE}${message} ${BNX_DIM}[${default}]${BNX_RESET}: "
    else
        prompt_str="  ${BNX_CYAN}→${BNX_RESET} ${BNX_WHITE}${message}${BNX_RESET}: "
    fi

    printf "${prompt_str}" >&2
    read -r "$var_name"

    if [[ -z "${!var_name}" && -n "$default" ]]; then
        eval "$var_name=\"\$default\""
    fi
}

# Confirm dialog (y/n)
bnx_confirm() {
    local message="${1}"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        printf "  ${BNX_YELLOW}?${BNX_RESET} ${BNX_WHITE}${message} ${BNX_DIM}[Y/n]${BNX_RESET}: " >&2
    else
        printf "  ${BNX_YELLOW}?${BNX_RESET} ${BNX_WHITE}${message} ${BNX_DIM}[y/N]${BNX_RESET}: " >&2
    fi

    read -r REPLY
    REPLY="${REPLY:-$default}"
    [[ "$REPLY" =~ ^[Yy]$ ]]
}

# Select from list
bnx_select() {
    local message="${1}"
    shift
    local options=("$@")
    local choice

    echo -e "  ${BNX_YELLOW}?${BNX_RESET} ${BNX_WHITE}${message}${BNX_RESET}"
    local i=1
    for opt in "${options[@]}"; do
        echo -e "    ${BNX_DIM}${i})${BNX_RESET} ${BNX_GRAY}${opt}${BNX_RESET}"
        ((i++))
    done

    while true; do
        printf "  ${BNX_CYAN}→${BNX_RESET} ${BNX_WHITE}Choice [1-${#options[@]}]${BNX_RESET}: " >&2
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            REPLY="${options[$((choice-1))]}"
            return 0
        fi
        bnx_error "Invalid selection. Try again."
    done
}

# Print a table row
bnx_table_row() {
    local cols=("$@")
    local widths=("${BNX_TABLE_WIDTHS[@]}")
    local row="  "

    for i in "${!cols[@]}"; do
        local cell="${cols[$i]}"
        local w="${widths[$i]:-20}"
        if (( i == 0 )); then
            row+="${BNX_BOLD}${BNX_CYAN}$(printf "%-${w}s" "$cell")${BNX_RESET} "
        else
            row+="${BNX_GRAY}$(printf "%-${w}s" "$cell")${BNX_RESET} "
        fi
    done
    echo -e "$row"
}

# Set table column widths (call before bnx_table_row)
bnx_table_set_widths() {
    BNX_TABLE_WIDTHS=("$@")
}

# Print banner/branding
bnx_banner() {
    clear
    local ver="${BRAANX_VERSION:-1.0.0}"
    echo -e "${BNX_BG2}"
    echo -e "${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN} ██████╗ ███████╗████████╗██████╗  ██████╗ ████████╗███╗   ██╗${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN}██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗╚══██╔══╝████╗  ██║${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN}██║   ██║███████╗   ██║   ██████╔╝██║   ██║   ██║   ██╔██╗ ██║${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN}██║   ██║╚════██║   ██║   ██╔══██╗██║   ██║   ██║   ██║╚██╗██║${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN}╚██████╔╝███████║   ██║   ██║  ██║╚██████╔╝   ██║   ██║ ╚████║${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_BOLD}${BNX_CYAN} ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚═╝  ╚═══╝${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_WHITE}    Advanced VPN Auto-Installer & Manager${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}  ${BNX_DIM}    Version ${ver}  │  Multi-Protocol  │  Telegram Bot${BNX_RESET}${BNX_BG2}"
    echo -e "${BNX_BG2}"
    echo -e "${BNX_RESET}"
}

# Footer with branding
bnx_footer() {
    echo ""
    echo -e "  ${BNX_DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${BNX_RESET}"
    echo -e "  ${BNX_DIM}BraanX v${BRAANX_VERSION:-1.0.0} │ github.com/braanx │ Powered by Xray Core${BNX_RESET}"
    echo -e "  ${BNX_DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${BNX_RESET}"
    echo ""
}
