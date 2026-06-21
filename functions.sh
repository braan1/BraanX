#!/bin/bash
# ============================================================================
#  BraanX Core Library - functions.sh
#  Shared utility functions used across all BraanX modules.
# ============================================================================

# Prevent double-sourcing
[[ -n "$_BRAANX_FUNCTIONS_LOADED" ]] && return 0
_BRAANX_FUNCTIONS_LOADED=1

# ============================================================================
# Color and Output Constants
# ============================================================================

# Standard ANSI colors
R='\033[0;31m'       # Red
G='\033[0;32m'       # Green
Y='\033[0;33m'       # Yellow
B='\033[0;34m'       # Blue
M='\033[0;35m'       # Magenta
C='\033[0;36m'       # Cyan
W='\033[0;37m'       # White
RD='\033[0;91m'      # Bright Red
GR='\033[0;92m'      # Bright Green
YL='\033[0;93m'      # Bright Yellow
BL='\033[0;94m'      # Bright Blue
MG='\033[0;95m'      # Bright Magenta
CL='\033[0;96m'      # Bright Cyan
WH='\033[0;97m'      # Bright White

# True-color RGB
CYAN_RGB='\033[38;2;0;255;200m'
GOLD_RGB='\033[38;2;255;200;0m'
GREEN_RGB='\033[38;2;0;255;136m'
RED_RGB='\033[38;2;255;80;80m'
BLUE_RGB='\033[38;2;80;160;255m'
MAGENTA_RGB='\033[38;2;200;120;255m'
WHITE_RGB='\033[38;2;240;240;240m'
DIM_GRAY='\033[38;2;100;100;100m'

# Style modifiers
BOLD='\033[1m'
DIM='\033[2m'
UND='\033[4m'
RST='\033[0m'

# Global paths (must match main script)
BRAANX_CONF_DIR="/etc/braanx"
BRAANX_CONF_FILE="${BRAANX_CONF_DIR}/braanx.conf"
BRAANX_LIB_DIR="${BRAANX_CONF_DIR}/lib"
BRAANX_LOG_DIR="${BRAANX_CONF_DIR}/log"
BRAANX_DB_DIR="${BRAANX_CONF_DIR}/db"
BRAANX_DB_FILE="${BRAANX_DB_DIR}/braanx.db"
BRAANX_LOG_FILE="${BRAANX_LOG_DIR}/braanx.log"

# ============================================================================
# Message Functions
# ============================================================================

# Print an info message with blue [i] prefix
# Usage: msg_info "message text"
msg_info() {
    echo -e "  ${B}[i]${RST} $*"
}

# Print a success message with green checkmark
# Usage: msg_ok "message text"
msg_ok() {
    echo -e "  ${G}[OK]${RST} $*"
}

# Print an error message with red X
# Usage: msg_err "message text"
msg_err() {
    echo -e "  ${R}[FAIL]${RST} $*"
}

# Print a warning message with yellow exclamation
# Usage: msg_warn "message text"
msg_warn() {
    echo -e "  ${Y}[!]${RST} $*"
}

# Print a highlighted step message
# Usage: msg_step "Step 1" "Doing something"
msg_step() {
    local step_num="$1"
    shift
    echo -e "  ${CL}${BOLD}[${step_num}]${RST} ${WH}$*${RST}"
}

# Center text in the terminal
# Usage: print_center "Some text"
print_center() {
    local text="$*"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 70)
    local text_len=${#text}
    local padding=$(( (term_width - text_len) / 2 ))
    if [[ $padding -lt 0 ]]; then
        padding=0
    fi
    local spaces=""
    for ((i = 0; i < padding; i++)); do
        spaces+=" "
    done
    echo -e "${spaces}${text}"
}

# Print a horizontal separator line
# Usage: print_line [char] [width] [color]
print_line() {
    local char="${1:--}"
    local width="${2:-60}"
    local color="${3:-$DIM_GRAY}"
    local line=""
    for ((i = 0; i < width; i++)); do
        line+="$char"
    done
    echo -e "${color}${line}${RST}"
}

# Print a thin separator with rounded ends
# Usage: print_thin_sep [width]
print_thin_sep() {
    local width="${1:-60}"
    echo -e "${DIM_GRAY}$(printf '%.0s-' $(seq 1 $width))${RST}"
}

# ============================================================================
# Progress Bar
# ============================================================================

# Display an animated progress bar
# Usage: progress_bar "label" <percent_or_count> [total]
#   progress_bar "Installing XRay" 75          -> 75%
#   progress_bar "Downloading" 35 50           -> 70%
progress_bar() {
    local label="$1"
    local current="$2"
    local total="${3:-100}"
    local percent

    # Validate inputs
    if ! [[ "$current" =~ ^[0-9]+$ ]] || ! [[ "$total" =~ ^[0-9]+$ ]]; then
        echo -e "  ${DIM}[progress]${RST} ${label}"
        return 1
    fi

    # Calculate percentage, cap at 100
    if [[ "$total" -gt 0 ]]; then
        percent=$(( (current * 100) / total ))
    else
        percent="$current"
    fi

    if [[ $percent -gt 100 ]]; then
        percent=100
    fi

    local bar_width=40
    local filled=$(( (percent * bar_width) / 100 ))
    local empty=$(( bar_width - filled ))

    # Build the bar string
    local bar=""
    for ((i = 0; i < filled; i++)); do
        bar+="${GR}"
    done
    for ((i = 0; i < empty; i++)); do
        bar+="${DIM}"
    done

    # Build full/empty blocks
    local filled_bar=""
    local empty_bar=""
    for ((i = 0; i < filled; i++)); do
        filled_bar+="#"
    done
    for ((i = 0; i < empty; i++)); do
        empty_bar+="."
    done

    # Print the progress bar
    printf "  \r${CL}[${GR}${filled_bar}${DIM}${empty_bar}${CL}] ${WH}%3d%%${RST} ${DIM}${label}" "$percent"

    # Print newline if complete
    if [[ $percent -ge 100 ]]; then
        echo ""
    fi
}

# Show a simple determinate progress from 0 to 100
# Usage: progress_simple "Installing packages" 30
progress_simple() {
    local label="$1"
    local percent="$2"

    [[ -z "$percent" ]] && percent=0
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    local bar_width=40
    local filled=$(( (percent * bar_width) / 100 ))
    local empty=$(( bar_width - filled ))

    local filled_bar=""
    local empty_bar=""
    for ((i = 0; i < filled; i++)); do filled_bar+="#"; done
    for ((i = 0; i < empty; i++)); do empty_bar+="."; done

    printf "  \r${CL}[${GR}${filled_bar}${DIM}${empty_bar}${CL}] ${WH}%3d%%${RST} ${DIM}${label}    " "$percent"

    if [[ $percent -ge 100 ]]; then
        echo ""
    fi
}

# ============================================================================
# Spinner
# ============================================================================

# Internal: run a spinner in the background
# Usage (internal): _spinner_start "label"
_spinner_pid=""
_spinner_label=""

_spinner_draw() {
    local chars=('\' '|' '/' '-' '\' '|' '/' '-')
    local idx=0
    while kill -0 "$_spinner_pid" 2>/dev/null; do
        local char="${chars[idx]}"
        printf "\r  ${CL}[${char}]${RST} ${DIM}%s" "$_spinner_label"
        idx=$(( (idx + 1) % 7 ))
        sleep 0.12
    done
    # Clear the spinner line
    printf "\r%*s\r" 80 ""
}

# Run a command with a spinning animation
# Usage: spinner "label" command [args...]
spinner() {
    local label="$1"
    shift
    _spinner_label="$label"

    # Run the command in the background
    "$@" &
    _spinner_pid=$!

    # Start the spinner drawing
    _spinner_draw

    # Wait for the command to finish
    wait "$_spinner_pid"
    local exit_code=$?

    # Clear spinner line
    printf "\r%*s\r" 80 ""

    if [[ $exit_code -eq 0 ]]; then
        msg_ok "$label"
    else
        msg_err "$label (exit code: $exit_code)"
    fi

    return $exit_code
}

# ============================================================================
# Box Drawing Functions
# ============================================================================

# Draw a box around multiple lines of text
# Usage: draw_box "title" "line1" "line2" "line3"
draw_box() {
    local title="$1"
    shift
    local lines=("$@")
    local width=62
    local inner_width=$((width - 4))

    # Find the longest line for auto-width (optional)
    local max_line_len=0
    for line in "${lines[@]}"; do
        if [[ ${#line} -gt $max_line_len ]]; then
            max_line_len=${#line}
        fi
    done
    if [[ $max_line_len -gt $((inner_width - 2)) ]]; then
        inner_width=$((max_line_len + 4))
        width=$((inner_width + 4))
    fi

    # Top border
    echo -e "${CL}${BOLD}  /$(printf '%.0s-' $(seq 1 $width))\\${RST}"

    # Title line
    if [[ -n "$title" ]]; then
        local title_pad=$(( (inner_width - ${#title}) / 2 ))
        local title_left=""
        local title_right=""
        for ((i = 0; i < title_pad; i++)); do title_left+=" "; done
        for ((i = 0; i < $((inner_width - ${#title} - title_pad)); i++)); do title_right+=" "; done
        echo -e "${CL}${BOLD} |${RST}${BOLD} ${GOLD_RGB}${title}${RST}${BOLD} ${CL}${BOLD}|${RST}"
        echo -e "${CL}${BOLD} |$(printf '%.0s-' $(seq 1 $width))|${RST}"
    fi

    # Content lines
    for line in "${lines[@]}"; do
        local padded
        padded=$(printf "%-${inner_width}s" "$line")
        echo -e "${CL}${BOLD} |${RST} ${WH}${padded} ${CL}${BOLD}|${RST}"
    done

    # Bottom border
    echo -e "${CL}${BOLD}  \\$(printf '%.0s-' $(seq 1 $width))/${RST}"
}

# Draw a section header with decorative lines
# Usage: draw_header "Section Title"
draw_header() {
    local title="$1"
    local width=62
    local title_len=${#title}
    local side_len=$(( (width - title_len - 4) / 2 ))

    local left=""
    local right=""
    for ((i = 0; i < side_len; i++)); do left+="="; done
    for ((i = 0; i < $((width - title_len - 4 - side_len)); i++)); do right+="="; done

    echo ""
    echo -e "  ${CL}${BOLD}${left} ${GOLD_RGB}${BOLD}[ ${title} ]${RST}${CL}${BOLD} ${right}${RST}"
    echo ""
}

# Draw a simple table from column data
# Usage: draw_table "col1" "col2" "col3" -- "val1" "val2" "val3" -- "val4" "val5" "val6"
draw_table() {
    local headers=()
    local rows=()
    local current_row=()
    local in_header=1

    for arg in "$@"; do
        if [[ "$arg" == "--" ]]; then
            if [[ $in_header -eq 1 ]]; then
                in_header=0
                headers=("${current_row[@]}")
            else
                rows+=("${current_row[*]}")
            fi
            current_row=()
        else
            current_row+=("$arg")
        fi
    done
    # Don't forget the last row
    if [[ ${#current_row[@]} -gt 0 ]]; then
        rows+=("${current_row[*]}")
    fi

    local num_cols=${#headers[@]}
    if [[ $num_cols -eq 0 ]]; then
        return 1
    fi

    # Calculate column widths
    local col_widths=()
    for ((c = 0; c < num_cols; c++)); do
        local max_w=${#headers[$c]}
        for row in "${rows[@]}"; do
            # Parse the row back into fields
            local fields=($row)
            if [[ $c -lt ${#fields[@]} ]]; then
                if [[ ${#fields[$c]} -gt $max_w ]]; then
                    max_w=${#fields[$c]}
                fi
            fi
        done
        col_widths+=($((max_w + 2)))
    done

    # Print header
    local header_line=""
    for ((c = 0; c < num_cols; c++)); do
        local padded
        padded=$(printf "%-${col_widths[$c]}s" "${headers[$c]}")
        header_line+="${GOLD_RGB}${BOLD}  ${padded}${RST}"
    done
    echo -e "$header_line"

    # Print separator
    local sep_line=""
    for ((c = 0; c < num_cols; c++)); do
        local sep=""
        for ((s = 0; s < col_widths[$c] + 2; s++)); do sep+="-"; done
        sep_line+="${DIM_GRAY}${sep}${RST}"
    done
    echo -e "  $sep_line"

    # Print rows
    for row in "${rows[@]}"; do
        local fields=($row)
        local row_line=""
        for ((c = 0; c < num_cols; c++)); do
            local val="${fields[$c]:-}"
            local padded
            padded=$(printf "%-${col_widths[$c]}s" "$val")
            row_line+="  ${WH}${padded}${RST}"
        done
        echo -e " $row_line"
    done
}

# ============================================================================
# System Detection Functions
# ============================================================================

# Detect the operating system
# Returns: "os:version:codename" e.g. "debian:12:bookworm"
detect_os() {
    local os_id="" os_ver="" os_codename=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        os_id="${ID}"
        os_ver="${VERSION_ID}"
        os_codename="${VERSION_CODENAME:-unknown}"
    elif [[ -f /etc/debian_version ]]; then
        os_id="debian"
        os_ver=$(cut -d. -f1-2 < /etc/debian_version)
        os_codename="unknown"
    else
        os_id="unknown"
        os_ver="0"
        os_codename="unknown"
    fi

    echo "${os_id}:${os_ver}:${os_codename}"
}

# Detect the system architecture
# Returns: x86_64, aarch64, armv7, armv6
detect_arch() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "aarch64" ;;
        armv7l)  echo "armv7" ;;
        armv6l)  echo "armv6" ;;
        *)       echo "$arch" ;;
    esac
}

# Check if running as root
# Returns: 0 if root, 1 if not
is_root() {
    [[ $(id -u) -eq 0 ]]
}

# Get the server's public IPv4 address
# Returns: IP address string or "0.0.0.0" on failure
get_public_ip() {
    local ip

    ip=$(curl -s --max-time 5 -4 ifconfig.me 2>/dev/null) \
        || ip=$(curl -s --max-time 5 -4 ip.sb 2>/dev/null) \
        || ip=$(curl -s --max-time 5 -4 icanhazip.com 2>/dev/null) \
        || ip=$(curl -s --max-time 5 -4 api.ipify.org 2>/dev/null)

    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
    else
        echo "0.0.0.0"
    fi
}

# Check if a specific TCP port is in use
# Usage: check_port <port>
# Returns: 0 if port is in use, 1 if free
check_port() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port} "
}

# Check if a domain resolves to the server's public IP
# Usage: check_domain "example.com" [expected_ip]
# Returns: 0 if domain resolves to expected IP, 1 otherwise
check_domain() {
    local domain="$1"
    local expected_ip="${2:-}"

    if [[ -z "$domain" ]]; then
        return 1
    fi

    local resolved_ip
    resolved_ip=$(dig +short "$domain" A 2>/dev/null | tail -1)

    if [[ -z "$resolved_ip" ]]; then
        return 1
    fi

    if [[ -n "$expected_ip" ]]; then
        [[ "$resolved_ip" == "$expected_ip" ]]
    else
        return 0
    fi
}

# ============================================================================
# Package Management Functions
# ============================================================================

# Update the apt package list
pkg_update() {
    apt-get update -qq -y 2>/dev/null
}

# Install one or more packages via apt
# Usage: pkg_install "pkg1" "pkg2" "pkg3"
# Returns: 0 on success, 1 on failure
pkg_install() {
    local pkgs=("$@")
    local failed=0

    for pkg in "${pkgs[@]}"; do
        if dpkg -l "$pkg" &>/dev/null; then
            msg_ok "$pkg already installed"
        else
            if apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
                msg_ok "$pkg installed"
            else
                msg_err "Failed to install $pkg"
                failed=1
            fi
        fi
    done

    return $failed
}

# Remove one or more packages via apt
# Usage: pkg_remove "pkg1" "pkg2"
pkg_remove() {
    local pkgs=("$@")
    for pkg in "${pkgs[@]}"; do
        if dpkg -l "$pkg" &>/dev/null; then
            apt-get remove -y -qq "$pkg" >/dev/null 2>&1
            apt-get autoremove -y -qq >/dev/null 2>&1
            msg_ok "$pkg removed"
        else
            msg_info "$pkg is not installed"
        fi
    done
}

# Check if a package is installed
# Usage: is_installed "package_name"
# Returns: 0 if installed, 1 if not
is_installed() {
    dpkg -l "$1" &>/dev/null
}

# ============================================================================
# Config Management Functions
# ============================================================================

# Load all config values from braanx.conf into the current shell
config_load() {
    if [[ -f "$BRAANX_CONF_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$BRAANX_CONF_FILE"
    fi
}

# Set a single configuration value
# Usage: config_set "key" "value"
config_set() {
    local key="$1"
    local value="$2"

    if [[ ! -f "$BRAANX_CONF_FILE" ]]; then
        mkdir -p "$BRAANX_CONF_DIR"
        touch "$BRAANX_CONF_FILE"
        chmod 600 "$BRAANX_CONF_FILE"
    fi

    if grep -q "^${key}=" "$BRAANX_CONF_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$BRAANX_CONF_FILE"
    else
        echo "${key}=${value}" >> "$BRAANX_CONF_FILE"
    fi
}

# Get a single configuration value
# Usage: config_get "key" [default_value]
# Prints the value to stdout
config_get() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$BRAANX_CONF_FILE" ]]; then
        local val
        val=$(grep "^${key}=" "$BRAANX_CONF_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
        if [[ -n "$val" ]]; then
            echo "$val"
            return 0
        fi
    fi
    echo "$default"
    return 1
}

# Initialize config file with default values (only if not present)
config_init() {
    if [[ -f "$BRAANX_CONF_FILE" ]]; then
        return 0
    fi

    mkdir -p "$BRAANX_CONF_DIR" 2>/dev/null

    cat > "$BRAANX_CONF_FILE" << 'CONFEOF'
# BraanX Configuration File
# Generated by BraanX v1.0.0

# Server
domain=
server_ip=
server_port=443

# XRay Settings
xray_enabled=0
xray_protocol=vless
xray_port=443
xray_uuid=

# SSH Settings
ssh_enabled=0
ssh_port=22
ssh_ws_port=443

# OpenVPN Settings
openvpn_enabled=0
openvpn_port=1194
openvpn_proto=udp

# Nginx
nginx_enabled=0
nginx_port=80

# SSL
ssl_enabled=0
ssl_cert_path=
ssl_key_path=

# Telegram Bot
tg_bot_enabled=0
tg_bot_token=
tg_bot_chat_id=

# Security
fail2ban_enabled=0
bbr_enabled=0

# Backup
backup_dir=/etc/braanx/backup
CONFEOF

    chmod 600 "$BRAANX_CONF_FILE"
}

# ============================================================================
# Database Functions
# ============================================================================

# Initialize the SQLite database with schema
db_init() {
    mkdir -p "$BRAANX_DB_DIR" 2>/dev/null

    sqlite3 "$BRAANX_DB_FILE" << 'DBEOF'
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

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT DEFAULT (datetime('now')),
    level TEXT,
    message TEXT
);
DBEOF

    chmod 600 "$BRAANX_DB_FILE"
}

# Run a raw SQL query
# Usage: db_query <sql> [quiet]
# quiet="yes" suppresses headers/column mode (for inserts/updates)
db_query() {
    local sql="$1"
    local quiet="${2:-no}"

    if [[ ! -f "$BRAANX_DB_FILE" ]]; then
        msg_err "Database not found. Run installation first."
        return 1
    fi

    if [[ "$quiet" == "yes" ]]; then
        sqlite3 "$BRAANX_DB_FILE" "$sql" 2>/dev/null
    else
        sqlite3 -header -column "$BRAANX_DB_FILE" "$sql" 2>/dev/null
    fi
}

# Insert a new account into the database
# Usage: db_insert_account "username" "password" "protocol" "expiry_days" ["uuid"] ["data_limit_mb"]
# Returns: 0 on success
db_insert_account() {
    local username="$1"
    local password="$2"
    local protocol="$3"
    local expiry_days="$4"
    local uuid="${5:-}"
    local data_limit="${6:-0}"

    # Validate required fields
    if [[ -z "$username" || -z "$protocol" || -z "$expiry_days" ]]; then
        msg_err "Missing required fields for account creation."
        return 1
    fi

    # Check if username already exists
    local existing
    existing=$(db_query "SELECT username FROM accounts WHERE username='${username}';" yes)
    if [[ -n "$existing" ]]; then
        msg_err "Username '${username}' already exists."
        return 1
    fi

    # Calculate expiry date
    local expiry_date
    expiry_date=$(date -d "+${expiry_days} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    if [[ -z "$expiry_date" ]]; then
        # Fallback for systems without GNU date
        expiry_date=$(date -v+${expiry_days}d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    fi

    if [[ -z "$expiry_date" ]]; then
        msg_err "Could not calculate expiry date."
        return 1
    fi

    # Convert data_limit from MB to bytes
    local data_limit_bytes=$((data_limit * 1024 * 1024))

    # Insert the account
    local sql="INSERT INTO accounts (username, password, uuid, protocol, expiry, data_limit, is_active)
               VALUES ('${username}', '${password}', '${uuid}', '${protocol}', '${expiry_date}', ${data_limit_bytes}, 1);"

    if db_query "$sql" yes; then
        msg_ok "Account '${username}' created (${protocol}, expires: ${expiry_date})"
        return 0
    else
        msg_err "Failed to create account '${username}'."
        return 1
    fi
}

# Delete an account by username
# Usage: db_delete_account "username"
# Returns: 0 on success
db_delete_account() {
    local username="$1"

    if [[ -z "$username" ]]; then
        msg_err "No username specified for deletion."
        return 1
    fi

    local exists
    exists=$(db_query "SELECT username FROM accounts WHERE username='${username}';" yes)

    if [[ -z "$exists" ]]; then
        msg_err "Account '${username}' not found."
        return 1
    fi

    if db_query "DELETE FROM accounts WHERE username='${username}';" yes; then
        msg_ok "Account '${username}' deleted."
        return 0
    else
        msg_err "Failed to delete account '${username}'."
        return 1
    fi
}

# List all accounts in a formatted table
# Usage: db_list_accounts [active_only]
# active_only="yes" to show only active accounts
db_list_accounts() {
    local active_only="${1:-no}"
    local where_clause=""

    if [[ "$active_only" == "yes" ]]; then
        where_clause="WHERE is_active=1"
    fi

    local count
    count=$(db_query "SELECT COUNT(*) FROM accounts ${where_clause};" yes)

    if [[ -z "$count" || "$count" -eq 0 ]]; then
        msg_info "No accounts found."
        return 0
    fi

    echo ""
    db_query "SELECT id, username, protocol, expiry, is_active,
              CASE WHEN data_limit > 0 THEN printf('%.1f MB', data_limit/1048576.0) ELSE 'Unlimited' END as 'Limit',
              CASE WHEN data_used > 0 THEN printf('%.1f MB', data_used/1048576.0) ELSE '0 MB' END as 'Used'
              FROM accounts ${where_clause} ORDER BY id;"
    echo ""
}

# Check for expired accounts and deactivate them
# Usage: db_check_expired
# Returns: number of accounts deactivated
db_check_expired() {
    local now
    now=$(date -u '+%Y-%m-%d %H:%M:%S')

    local expired_count
    expired_count=$(db_query "SELECT COUNT(*) FROM accounts WHERE is_active=1 AND expiry <= '${now}';" yes)

    if [[ -n "$expired_count" && "$expired_count" -gt 0 ]]; then
        db_query "UPDATE accounts SET is_active=0 WHERE is_active=1 AND expiry <= '${now}';" yes
        msg_warn "Deactivated ${expired_count} expired account(s)."
        return 0
    else
        msg_info "No expired accounts found."
        return 0
    fi
}

# Renew an account by extending its expiry
# Usage: db_renew_account "username" "extra_days"
db_renew_account() {
    local username="$1"
    local extra_days="$2"

    if [[ -z "$username" || -z "$extra_days" ]]; then
        msg_err "Username and days are required."
        return 1
    fi

    local exists
    exists=$(db_query "SELECT username FROM accounts WHERE username='${username}';" yes)

    if [[ -z "$exists" ]]; then
        msg_err "Account '${username}' not found."
        return 1
    fi

    local new_expiry
    new_expiry=$(date -d "+${extra_days} days" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    if [[ -z "$new_expiry" ]]; then
        new_expiry=$(date -v+${extra_days}d '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    fi

    if db_query "UPDATE accounts SET expiry='${new_expiry}', is_active=1 WHERE username='${username}';" yes; then
        msg_ok "Account '${username}' renewed. New expiry: ${new_expiry}"
        return 0
    else
        msg_err "Failed to renew account '${username}'."
        return 1
    fi
}

# ============================================================================
# Misc Helper Functions
# ============================================================================

# Generate a random password of given length
# Usage: gen_password [length]
gen_password() {
    local len="${1:-10}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len"
}

# Generate a UUID v4
# Usage: gen_uuid
gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null \
        || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null
}

# Prompt user for input with a default value
# Usage: prompt_default "prompt text" "default_value"
prompt_default() {
    local prompt_text="$1"
    local default_val="$2"
    local user_input

    echo -en "  ${CL}[?]${RST} ${prompt_text} "
    if [[ -n "$default_val" ]]; then
        echo -en "${DIM}[${default_val}]${RST} "
    fi
    read -r user_input

    if [[ -z "$user_input" && -n "$default_val" ]]; then
        echo "$default_val"
    else
        echo "$user_input"
    fi
}

# Pause and wait for user to press Enter
# Usage: press_enter
press_enter() {
    echo ""
    echo -en "  ${DIM}Press [Enter] to continue...${RST}"
    read -r
}

# Confirm yes/no with the user
# Usage: confirm "Are you sure?" [default_yes]
# Returns: 0 for yes, 1 for no
confirm() {
    local prompt_text="$1"
    local default_yes="${2:-no}"
    local hint="[y/N]"

    if [[ "$default_yes" == "yes" ]]; then
        hint="[Y/n]"
    fi

    echo -en "  ${YL}[?]${RST} ${prompt_text} ${hint} "
    read -r answer

    if [[ "$default_yes" == "yes" ]]; then
        [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
    else
        [[ "$answer" =~ ^[Yy] ]]
    fi
}

# ============================================================================
# Export all functions
# ============================================================================

export -f msg_info 2>/dev/null
export -f msg_ok 2>/dev/null
export -f msg_err 2>/dev/null
export -f msg_warn 2>/dev/null
export -f msg_step 2>/dev/null
export -f print_center 2>/dev/null
export -f print_line 2>/dev/null
export -f print_thin_sep 2>/dev/null
export -f progress_bar 2>/dev/null
export -f progress_simple 2>/dev/null
export -f spinner 2>/dev/null
export -f draw_box 2>/dev/null
export -f draw_header 2>/dev/null
export -f draw_table 2>/dev/null
export -f detect_os 2>/dev/null
export -f detect_arch 2>/dev/null
export -f is_root 2>/dev/null
export -f get_public_ip 2>/dev/null
export -f check_port 2>/dev/null
export -f check_domain 2>/dev/null
export -f pkg_update 2>/dev/null
export -f pkg_install 2>/dev/null
export -f pkg_remove 2>/dev/null
export -f is_installed 2>/dev/null
export -f config_load 2>/dev/null
export -f config_set 2>/dev/null
export -f config_get 2>/dev/null
export -f config_init 2>/dev/null
export -f db_init 2>/dev/null
export -f db_query 2>/dev/null
export -f db_insert_account 2>/dev/null
export -f db_delete_account 2>/dev/null
export -f db_list_accounts 2>/dev/null
export -f db_check_expired 2>/dev/null
export -f db_renew_account 2>/dev/null
export -f gen_password 2>/dev/null
export -f gen_uuid 2>/dev/null
export -f prompt_default 2>/dev/null
export -f press_enter 2>/dev/null
export -f confirm 2>/dev/null