#!/usr/bin/env python3
"""
BraanX VPN Manager - Telegram Bot
A comprehensive Telegram bot for managing VPN server remotely.
"""

import os
import sys
import sqlite3
import subprocess
import json
import time
import signal
import logging
import uuid as uuid_lib
import base64
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application, CommandHandler, CallbackQueryHandler,
    MessageHandler, filters, ContextTypes
)

# --------------- Configuration ---------------

CONF_PATH = "/etc/braanx/braanx.conf"
DB_PATH = "/etc/braanx/db/braanx.db"
BOT_DIR = "/etc/braanx/bot"
ADMIN_FILE = "/etc/braanx/bot/admins.txt"
LOG_FILE = "/etc/braanx/log/bot.log"
XRAY_CONFIG = "/usr/local/etc/xray/config.json"
USER_MGMT_SCRIPT = "/home/z/my-project/braanx/lib/user-mgmt.sh"
PAGESIZE = 10

# --------------- Logging Setup ---------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("braanx_bot")

# --------------- Globals ---------------

config = {}
admin_ids = []
user_states = {}
application = None


# --------------- Config & DB Helpers ---------------

def load_config():
    """Load configuration from braanx.conf (KEY=VALUE format)."""
    global config
    config = {}
    if not os.path.isfile(CONF_PATH):
        logger.warning("Config file not found: %s", CONF_PATH)
        return
    try:
        with open(CONF_PATH, "r") as fh:
            for line in fh:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, val = line.split("=", 1)
                    config[key.strip()] = val.strip()
        logger.info("Configuration loaded successfully.")
    except Exception as exc:
        logger.error("Failed to load config: %s", exc)


def load_admins():
    """Load admin Telegram IDs from admins.txt."""
    global admin_ids
    admin_ids = []
    if not os.path.isfile(ADMIN_FILE):
        logger.warning("Admin file not found: %s", ADMIN_FILE)
        return
    try:
        with open(ADMIN_FILE, "r") as fh:
            for line in fh:
                line = line.strip()
                if line and line.isdigit():
                    admin_ids.append(int(line))
        logger.info("Loaded %d admin(s).", len(admin_ids))
    except Exception as exc:
        logger.error("Failed to load admins: %s", exc)


def get_db():
    """Return a database connection with row factory."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db():
    """Create tables if they do not exist."""
    conn = get_db()
    try:
        conn.executescript("""
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
        """)
        conn.commit()
        logger.info("Database initialised.")
    finally:
        conn.close()


# --------------- Auth Helpers ---------------

def is_admin(user_id):
    """Check whether a Telegram user ID is in the admin list."""
    return user_id in admin_ids


def require_admin(func):
    """Decorator: only allow admin users to execute the handler."""
    async def wrapper(update: Update, context: ContextTypes.DEFAULT_TYPE):
        user_id = update.effective_user.id
        if not is_admin(user_id):
            await update.message.reply_text(
                "<b>Access Denied</b>\n\nYou are not authorized to use this command.",
                parse_mode="HTML"
            )
            logger.warning("Unauthorized access from Telegram ID %s", user_id)
            return
        return await func(update, context)
    return wrapper


def get_user_state(user_id):
    """Return the per-user state dict, creating if needed."""
    if user_id not in user_states:
        user_states[user_id] = {}
    return user_states[user_id]


def clear_user_state(user_id):
    """Clear the per-user workflow state."""
    user_states.pop(user_id, None)


# --------------- System Helpers ---------------

def run_cmd(cmd, timeout=30):
    """Run a shell command and return (returncode, stdout, stderr)."""
    try:
        proc = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as exc:
        return -1, "", str(exc)


def get_server_ip():
    """Return the server's public IP address."""
    rc, out, _ = run_cmd("curl -s4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'")
    return out if rc == 0 else "N/A"


def get_domain():
    """Return configured domain or public IP."""
    return config.get("DOMAIN", "") or get_server_ip()


def format_bytes(num_bytes):
    """Human-readable byte count."""
    num_bytes = int(num_bytes or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(num_bytes) < 1024.0:
            return "{:.1f} {}".format(num_bytes, unit)
        num_bytes /= 1024.0
    return "{:.1f} PB".format(num_bytes)


def format_uptime(seconds):
    """Convert seconds to Xd Xh Xm format."""
    seconds = int(seconds)
    days, remainder = divmod(seconds, 86400)
    hours, remainder = divmod(remainder, 3600)
    minutes, _ = divmod(remainder, 60)
    return "{}d {}h {}m".format(days, hours, minutes)


# --------------- Server Info ---------------

def collect_server_info():
    """Gather server statistics into a dict."""
    import psutil
    info = {}

    # OS
    rc, out, _ = run_cmd("cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'\"' -f2")
    info["os"] = out if rc == 0 else "Unknown"

    # Hostname
    info["hostname"] = os.uname().nodename
    info["ip"] = get_server_ip()
    info["domain"] = get_domain()

    # Uptime
    info["uptime"] = format_uptime(time.time() - psutil.boot_time())

    # CPU
    info["cpu_percent"] = psutil.cpu_percent(interval=1)
    info["cpu_count"] = psutil.cpu_count()

    # RAM
    mem = psutil.virtual_memory()
    info["ram_used"] = format_bytes(mem.used)
    info["ram_total"] = format_bytes(mem.total)
    info["ram_percent"] = mem.percent

    # Disk
    disk = psutil.disk_usage("/")
    info["disk_used"] = format_bytes(disk.used)
    info["disk_total"] = format_bytes(disk.total)
    info["disk_percent"] = disk.percent

    # Accounts
    conn = get_db()
    try:
        total = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        active = conn.execute("SELECT COUNT(*) FROM accounts WHERE is_active=1").fetchone()[0]
        expired = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE expiry < datetime('now') AND is_active=1"
        ).fetchone()[0]
        info["total_accounts"] = total
        info["active_accounts"] = active
        info["expired_accounts"] = expired
    finally:
        conn.close()

    return info


# --------------- Account Helpers ---------------

def generate_uuid():
    """Return a random UUID string."""
    return str(uuid_lib.uuid4())


def random_string(length=8):
    """Generate a random alphanumeric string."""
    import random
    import string
    chars = string.ascii_lowercase + string.digits
    return "".join(random.choice(chars) for _ in range(length))


def calc_expiry_date(days):
    """Return an ISO-style date string for N days from now."""
    return (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")


def db_create_account(username, password, acc_uuid, protocol, expiry, data_limit=0):
    """Insert a new account into the database."""
    conn = get_db()
    try:
        conn.execute(
            "INSERT OR IGNORE INTO accounts "
            "(username, password, uuid, protocol, expiry, data_limit, is_active) "
            "VALUES (?, ?, ?, ?, ?, ?, 1)",
            (username, password, acc_uuid, protocol, expiry, data_limit)
        )
        conn.commit()
    finally:
        conn.close()


def db_delete_account(username):
    """Remove an account from the database."""
    conn = get_db()
    try:
        conn.execute("DELETE FROM accounts WHERE username=?", (username,))
        conn.commit()
    finally:
        conn.close()


def db_get_account(username):
    """Fetch a single account by username."""
    conn = get_db()
    try:
        row = conn.execute(
            "SELECT * FROM accounts WHERE username=?", (username,)
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def db_list_accounts(offset=0, limit=PAGESIZE):
    """Return a list of account dicts."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM accounts ORDER BY id DESC LIMIT ? OFFSET ?",
            (limit, offset)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def db_account_count():
    """Return total number of accounts."""
    conn = get_db()
    try:
        return conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
    finally:
        conn.close()


def db_renew_account(username, days):
    """Extend an account's expiry by N days from now."""
    new_expiry = calc_expiry_date(days)
    conn = get_db()
    try:
        conn.execute(
            "UPDATE accounts SET expiry=?, is_active=1 WHERE username=?",
            (new_expiry, username)
        )
        conn.commit()
    finally:
        conn.close()


def db_toggle_active(username, active):
    """Set is_active for an account."""
    conn = get_db()
    try:
        conn.execute(
            "UPDATE accounts SET is_active=? WHERE username=?", (active, username)
        )
        conn.commit()
    finally:
        conn.close()


# --------------- System-Level Account Creation ---------------

def create_ssh_account(username, password, days):
    """Create a Linux system user for SSH tunneling."""
    expiry = calc_expiry_date(days)
    expiry_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

    # Create user
    rc, out, err = run_cmd(
        "useradd -M -s /bin/bash {user} 2>/dev/null".format(user=username)
    )
    if rc != 0 and "already exists" not in err:
        return False, "Failed to create user: {}".format(err)

    # Set password
    rc, out, err = run_cmd(
        'echo \'{user}:{pwd}\' | chpasswd'.format(user=username, pwd=password)
    )
    if rc != 0:
        return False, "Failed to set password: {}".format(err)

    # Set expiry
    run_cmd("chage -E {exp} {user}".format(exp=expiry_date, user=username))

    # Add to database
    db_create_account(username, password, "", "SSH", expiry)

    return True, "SSH account '{}' created successfully.".format(username)


def create_xray_account(username, protocol, days):
    """Create an XRay protocol account (VLESS, VMess, Trojan)."""
    acc_uuid = generate_uuid()
    expiry = calc_expiry_date(days)
    domain = get_domain()
    port = config.get("XRAY_PORT", "443")
    path = config.get("XRAY_WS_PATH", "/")
    security = config.get("XRAY_SECURITY", "tls")

    if protocol == "Trojan":
        password = random_string(16)
    else:
        password = acc_uuid

    # Attempt to add inbound user to XRay config via python3 one-liner
    config_path = XRAY_CONFIG
    if os.path.isfile(config_path):
        try:
            with open(config_path, "r") as fh:
                xray_cfg = json.load(fh)

            # Add to the first matching inbound
            added = False
            for inbound in xray_cfg.get("inbounds", []):
                proto_name = inbound.get("protocol", "")
                if proto_name.lower() == protocol.lower():
                    if "settings" not in inbound:
                        inbound["settings"] = {}
                    if "clients" not in inbound["settings"]:
                        inbound["settings"]["clients"] = []
                    client = {"id": acc_uuid}
                    if protocol == "Trojan":
                        client["password"] = password
                    if username:
                        client["email"] = username
                    inbound["settings"]["clients"].append(client)
                    added = True
                    break

            if added:
                with open(config_path, "w") as fh:
                    json.dump(xray_cfg, fh, indent=2)
                # Restart xray
                run_cmd("systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null")
        except Exception as exc:
            logger.error("Failed to update XRay config: %s", exc)

    # Add to database
    db_create_account(username, password, acc_uuid, protocol, expiry)

    # Build connection link
    link = ""
    if protocol == "VLESS":
        link = "vless://{uuid}@{domain}:{port}?encryption=none&security={sec}&type=ws&path={path}#{user}".format(
            uuid=acc_uuid, domain=domain, port=port, sec=security, path=path, user=username
        )
    elif protocol == "VMess":
        vmess_obj = {
            "v": "2", "ps": username, "add": domain, "port": str(port),
            "id": acc_uuid, "aid": "0", "net": "ws", "type": "none",
            "host": domain, "path": path, "tls": security
        }
        link = "vmess://" + base64.b64encode(json.dumps(vmess_obj).encode()).decode()
    elif protocol == "Trojan":
        link = "trojan://{pwd}@{domain}:{port}?type=ws&path={path}#{user}".format(
            pwd=password, domain=domain, port=port, path=path, user=username
        )

    return True, link


def create_openvpn_account(username, days):
    """Create an OpenVPN user using easy-rsa (stub placeholder)."""
    expiry = calc_expiry_date(days)
    password = random_string(12)

    # Try to generate OpenVPN client config
    ovpn_path = "/etc/openvpn/client/{}.ovpn".format(username)
    rc, out, err = run_cmd(
        "cd /etc/openvpn/easy-rsa && "
        "./easyrsa build-client-full {user} nopass 2>&1".format(user=username),
        timeout=60
    )

    db_create_account(username, password, "", "OpenVPN", expiry)

    ovpn_content = ""
    if os.path.isfile(ovpn_path):
        with open(ovpn_path, "r") as fh:
            ovpn_content = fh.read()
    elif os.path.isfile("/etc/openvpn/server/client-template.ovpn"):
        with open("/etc/openvpn/server/client-template.ovpn", "r") as fh:
            ovpn_content = fh.read()

    return True, ovpn_content or "OpenVPN config generation initiated for '{}'.".format(username)


def delete_ssh_account(username):
    """Remove a Linux system user."""
    run_cmd("userdel -r {user} 2>/dev/null".format(user=username))
    db_delete_account(username)


def delete_xray_account(username):
    """Remove a user from the XRay config by email/username."""
    acc = db_get_account(username)
    if not acc:
        return

    config_path = XRAY_CONFIG
    if os.path.isfile(config_path) and acc.get("uuid"):
        try:
            with open(config_path, "r") as fh:
                xray_cfg = json.load(fh)
            modified = False
            for inbound in xray_cfg.get("inbounds", []):
                clients = inbound.get("settings", {}).get("clients", [])
                original_len = len(clients)
                inbound["settings"]["clients"] = [
                    c for c in clients if c.get("id") != acc["uuid"]
                ]
                if len(inbound["settings"]["clients"]) < original_len:
                    modified = True
            if modified:
                with open(config_path, "w") as fh:
                    json.dump(xray_cfg, fh, indent=2)
                run_cmd("systemctl restart xray 2>/dev/null || systemctl restart xray.service 2>/dev/null")
        except Exception as exc:
            logger.error("Failed to remove XRay user: %s", exc)

    db_delete_account(username)


# --------------- Notification Helper ---------------

def notify_admins(bot, text, parse_mode="HTML"):
    """Send a message to all admin chat IDs."""
    if not bot:
        return
    for admin_id in admin_ids:
        try:
            bot.bot.send_message(
                chat_id=admin_id, text=text, parse_mode=parse_mode
            )
        except Exception as exc:
            logger.error("Failed to notify admin %s: %s", admin_id, exc)


# --------------- Background Tasks ---------------

async def background_checker(app):
    """Periodic task: check for expired accounts and send alerts."""
    logger.info("Running background account check...")
    conn = get_db()
    try:
        # Deactivate expired accounts
        expired = conn.execute(
            "SELECT * FROM accounts WHERE is_active=1 AND expiry < datetime('now')"
        ).fetchall()

        for row in expired:
            acc = dict(row)
            conn.execute(
                "UPDATE accounts SET is_active=0 WHERE id=?", (acc["id"],)
            )
            # Deactivate SSH user if applicable
            if acc["protocol"] == "SSH":
                run_cmd("usermod -L {user} 2>/dev/null".format(user=acc["username"]))
            logger.info("Account expired and deactivated: %s (%s)", acc["username"], acc["protocol"])

        # Alert for accounts expiring within 24 hours
        warning = conn.execute(
            "SELECT * FROM accounts WHERE is_active=1 "
            "AND expiry BETWEEN datetime('now') AND datetime('now', '+1 day') "
            "AND expiry > datetime('now')"
        ).fetchall()

        for row in warning:
            acc = dict(row)
            text = (
                "<b>Account Expiring Soon</b>\n\n"
                "<b>User:</b> <code>{user}</code>\n"
                "<b>Protocol:</b> {proto}\n"
                "<b>Expires:</b> {exp}\n\n"
                "Use /renew to extend this account."
            ).format(user=acc["username"], proto=acc["protocol"], exp=acc["expiry"])
            notify_admins(app, text)

        conn.commit()
    except Exception as exc:
        logger.error("Background check error: %s", exc)
    finally:
        conn.close()


# --------------- Command Handlers ---------------

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /start command."""
    user = update.effective_user
    user_id = user.id
    tg_name = user.username or ""

    # Register bot user in DB
    conn = get_db()
    try:
        conn.execute(
            "INSERT OR IGNORE INTO bot_users (telegram_id, username, is_admin) VALUES (?, ?, ?)",
            (user_id, tg_name, 1 if is_admin(user_id) else 0)
        )
        conn.commit()
    finally:
        conn.close()

    if is_admin(user_id):
        text = (
            "<b>BraanX VPN Manager</b>\n\n"
            "Welcome, <b>{name}</b>!\n\n"
            "You have administrator access.\n"
            "Use /menu to access the management panel\n"
            "or /help for available commands."
        ).format(name=tg_name or str(user_id))
        keyboard = InlineKeyboardMarkup([
            [
                InlineKeyboardButton("VPN Management", callback_data="menu_mgmt"),
                InlineKeyboardButton("Server Info", callback_data="menu_info"),
            ],
            [
                InlineKeyboardButton("Account Actions", callback_data="menu_accounts"),
                InlineKeyboardButton("System Tools", callback_data="menu_tools"),
            ],
            [
                InlineKeyboardButton("Help", callback_data="menu_help"),
                InlineKeyboardButton("Settings", callback_data="menu_settings"),
            ],
        ])
    else:
        text = (
            "<b>BraanX VPN</b>\n\n"
            "Welcome, <b>{name}</b>!\n\n"
            "This bot is for authorized administrators only.\n"
            "Use /help for available commands."
        ).format(name=tg_name or str(user_id))
        keyboard = None

    await update.message.reply_text(text, parse_mode="HTML", reply_markup=keyboard)


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /help command."""
    commands = (
        "/start - Welcome message\n"
        "/menu - Main management menu\n"
        "/info - Server information\n"
        "/accounts - List all VPN accounts\n"
        "/create - Create a new account\n"
        "/delete - Delete an account\n"
        "/renew - Renew an account\n"
        "/trial - Create 1-day trial account\n"
        "/monitor - Bandwidth monitoring\n"
        "/restart - Restart services\n"
        "/backup - Create configuration backup\n"
        "/cancel - Cancel current operation\n"
        "/help - Show this help message"
    )

    if is_admin(update.effective_user.id):
        text = (
            "<b>BraanX VPN Manager - Commands</b>\n\n"
            "<code>{}</code>"
        ).format(commands)
    else:
        text = (
            "<b>BraanX VPN - Available Commands</b>\n\n"
            "<code>/start - Welcome message\n"
            "/help - Show this help message\n"
            "/info - Basic server info</code>"
        )

    await update.message.reply_text(text, parse_mode="HTML")


@require_admin
async def cmd_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /menu command - show inline keyboard."""
    keyboard = InlineKeyboardMarkup([
        [
            InlineKeyboardButton("VPN Management", callback_data="menu_mgmt"),
            InlineKeyboardButton("Server Info", callback_data="menu_info"),
        ],
        [
            InlineKeyboardButton("Account Actions", callback_data="menu_accounts"),
            InlineKeyboardButton("System Tools", callback_data="menu_tools"),
        ],
        [
            InlineKeyboardButton("Help", callback_data="menu_help"),
            InlineKeyboardButton("Settings", callback_data="menu_settings"),
        ],
    ])
    text = (
        "<b>BraanX VPN Manager</b>\n\n"
        "Select an option below:"
    )
    await update.message.reply_text(text, parse_mode="HTML", reply_markup=keyboard)


@require_admin
async def cmd_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /info command - show server info."""
    try:
        import psutil
        info = collect_server_info()
        text = (
            "<b>Server Information</b>\n\n"
            "<b>OS:</b> {os}\n"
            "<b>Hostname:</b> <code>{host}</code>\n"
            "<b>IP:</b> <code>{ip}</code>\n"
            "<b>Domain:</b> <code>{domain}</code>\n"
            "<b>Uptime:</b> {uptime}\n\n"
            "<b>CPU:</b> {cpu}% ({cores} cores)\n"
            "<b>RAM:</b> {ram_used} / {ram_total} ({ram_p}%)\n"
            "<b>Disk:</b> {disk_used} / {disk_total} ({disk_p}%)\n\n"
            "<b>Total Accounts:</b> {total}\n"
            "<b>Active:</b> {active}\n"
            "<b>Expired:</b> {expired}"
        ).format(
            os=info.get("os", "N/A"),
            host=info.get("hostname", "N/A"),
            ip=info.get("ip", "N/A"),
            domain=info.get("domain", "N/A"),
            uptime=info.get("uptime", "N/A"),
            cpu=info.get("cpu_percent", "N/A"),
            cores=info.get("cpu_count", "N/A"),
            ram_used=info.get("ram_used", "N/A"),
            ram_total=info.get("ram_total", "N/A"),
            ram_p=info.get("ram_percent", "N/A"),
            disk_used=info.get("disk_used", "N/A"),
            disk_total=info.get("disk_total", "N/A"),
            disk_p=info.get("disk_percent", "N/A"),
            total=info.get("total_accounts", 0),
            active=info.get("active_accounts", 0),
            expired=info.get("expired_accounts", 0),
        )
        await update.message.reply_text(text, parse_mode="HTML")
    except ImportError:
        await update.message.reply_text(
            "Error: psutil is not installed. Run: pip install psutil",
            parse_mode="HTML"
        )
    except Exception as exc:
        logger.error("cmd_info error: %s", exc)
        await update.message.reply_text("Error gathering server info: {}".format(exc), parse_mode="HTML")


@require_admin
async def cmd_accounts(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /accounts - list accounts page 1."""
    context.user_data["accounts_page"] = 0
    await show_accounts_page(update, context, 0)


async def show_accounts_page(update, context, page):
    """Display a page of accounts with pagination buttons."""
    total = db_account_count()
    if total == 0:
        await (update.message or update.callback_query.message).reply_text(
            "<b>Accounts</b>\n\nNo accounts found.", parse_mode="HTML"
        )
        return

    offset = page * PAGESIZE
    accounts = db_list_accounts(offset, PAGESIZE)
    text_parts = ["<b>Accounts ({}/{})</b>\n".format(total, page + 1)]

    for acc in accounts:
        status = "Active"
        if acc["is_active"] != 1:
            status = "Inactive"
        elif acc["expiry"] < datetime.now().strftime("%Y-%m-%d %H:%M:%S"):
            status = "Expired"

        data_str = "{}/{}".format(
            format_bytes(acc["data_used"]),
            format_bytes(acc["data_limit"]) if acc["data_limit"] > 0 else "Unlimited"
        )
        text_parts.append(
            "<b>{}</b> | <code>{}</code> | {} | Exp: {} | {}\n  Data: {}".format(
                acc["protocol"], acc["username"], status,
                acc["expiry"], acc.get("last_active") or "Never", data_str
            )
        )

    # Pagination buttons
    buttons = []
    nav_row = []
    if page > 0:
        nav_row.append(InlineKeyboardButton("<< Prev", callback_data="acc_page_{}".format(page - 1)))
    if (page + 1) * PAGESIZE < total:
        nav_row.append(InlineKeyboardButton("Next >>", callback_data="acc_page_{}".format(page + 1)))
    if nav_row:
        buttons.append(nav_row)

    keyboard = InlineKeyboardMarkup(buttons) if buttons else None
    target = update.callback_query.message if update.callback_query else update.message

    if update.callback_query:
        await update.callback_query.edit_message_text(
            "\n".join(text_parts), parse_mode="HTML", reply_markup=keyboard
        )
    else:
        await target.reply_text("\n".join(text_parts), parse_mode="HTML", reply_markup=keyboard)


# --------------- Create Account Workflow ---------------

@require_admin
async def cmd_create(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /create - start account creation workflow."""
    state = get_user_state(update.effective_user.id)
    state.clear()
    state["step"] = "choose_protocol"

    keyboard = InlineKeyboardMarkup([
        [
            InlineKeyboardButton("SSH", callback_data="proto_ssh"),
            InlineKeyboardButton("VLESS", callback_data="proto_vless"),
            InlineKeyboardButton("VMess", callback_data="proto_vmess"),
        ],
        [
            InlineKeyboardButton("Trojan", callback_data="proto_trojan"),
            InlineKeyboardButton("OpenVPN", callback_data="proto_openvpn"),
        ],
        [
            InlineKeyboardButton("Cancel", callback_data="cancel"),
        ],
    ])
    await update.message.reply_text(
        "<b>Create Account</b>\n\nStep 1/5: Select protocol",
        parse_mode="HTML", reply_markup=keyboard
    )


@require_admin
async def cmd_trial(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /trial - quick 1-day trial account."""
    username = "trial-{}".format(random_string(4))
    password = random_string(10)

    try:
        success, result = create_ssh_account(username, password, 1)
        if success:
            # Set data limit to 500MB
            conn = get_db()
            try:
                conn.execute(
                    "UPDATE accounts SET data_limit=? WHERE username=?",
                    (524288000, username)
                )
                conn.commit()
            finally:
                conn.close()

            ip = get_server_ip()
            text = (
                "<b>Trial Account Created</b>\n\n"
                "<b>Username:</b> <code>{user}</code>\n"
                "<b>Password:</b> <code>{pwd}</code>\n"
                "<b>Protocol:</b> SSH\n"
                "<b>Expiry:</b> 1 day\n"
                "<b>Data Limit:</b> 500 MB\n\n"
                "<b>Connection:</b>\n"
                "<code>ssh -o ProxyCommand='nc -X 5 -x proxy:1080 %h %p' {user}@{ip}</code>"
            ).format(user=username, pwd=password, ip=ip)
            await update.message.reply_text(text, parse_mode="HTML")
            logger.info("Trial account created: %s", username)
        else:
            await update.message.reply_text(
                "<b>Error</b>\n{}".format(result), parse_mode="HTML"
            )
    except Exception as exc:
        logger.error("Trial creation error: %s", exc)
        await update.message.reply_text("Error creating trial: {}".format(exc), parse_mode="HTML")


# --------------- Delete Account Workflow ---------------

@require_admin
async def cmd_delete(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /delete - start delete workflow."""
    accounts = db_list_accounts(0, 20)
    if not accounts:
        await update.message.reply_text("No accounts found to delete.", parse_mode="HTML")
        return

    state = get_user_state(update.effective_user.id)
    state["step"] = "delete_select"

    buttons = []
    for acc in accounts:
        label = "{} - {} ({})".format(acc["protocol"], acc["username"], acc["expiry"])
        buttons.append([InlineKeyboardButton(label, callback_data="del_{}".format(acc["username"]))])
    buttons.append([InlineKeyboardButton("Cancel", callback_data="cancel")])

    await update.message.reply_text(
        "<b>Delete Account</b>\n\nSelect an account to delete:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(buttons)
    )


# --------------- Renew Account Workflow ---------------

@require_admin
async def cmd_renew(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /renew - start renew workflow."""
    conn = get_db()
    try:
        rows = conn.execute(
            "SELECT * FROM accounts WHERE is_active=1 "
            "AND expiry < datetime('now', '+7 days') "
            "ORDER BY expiry ASC LIMIT 20"
        ).fetchall()
    finally:
        conn.close()

    accounts = [dict(r) for r in rows]
    if not accounts:
        await update.message.reply_text(
            "No accounts need renewal (all expire in 7+ days).", parse_mode="HTML"
        )
        return

    state = get_user_state(update.effective_user.id)
    state["step"] = "renew_select"

    buttons = []
    for acc in accounts:
        label = "{} - {} (exp: {})".format(acc["protocol"], acc["username"], acc["expiry"])
        buttons.append([InlineKeyboardButton(label, callback_data="renew_{}".format(acc["username"]))])
    buttons.append([InlineKeyboardButton("Cancel", callback_data="cancel")])

    await update.message.reply_text(
        "<b>Renew Account</b>\n\nSelect an account to renew:",
        parse_mode="HTML", reply_markup=InlineKeyboardMarkup(buttons)
    )


# --------------- Monitor ---------------

@require_admin
async def cmd_monitor(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /monitor - bandwidth monitoring."""
    try:
        import psutil
        net = psutil.net_io_counters()

        conn = get_db()
        try:
            total_accounts = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
            top_users = conn.execute(
                "SELECT username, data_used, data_limit FROM accounts "
                "WHERE is_active=1 ORDER BY data_used DESC LIMIT 10"
            ).fetchall()
        finally:
            conn.close()

        text_parts = [
            "<b>Bandwidth Monitor</b>\n\n",
            "<b>Server Network I/O:</b>\n",
            "  Upload: {}\n".format(format_bytes(net.bytes_sent)),
            "  Download: {}\n".format(format_bytes(net.bytes_recv)),
            "  Total: {}\n\n".format(format_bytes(net.bytes_sent + net.bytes_recv)),
            "<b>Active Accounts:</b> {}\n".format(total_accounts),
            "<b>Top 10 Users by Data:</b>\n",
        ]

        if top_users:
            for i, row in enumerate(top_users, 1):
                acc = dict(row)
                limit_str = format_bytes(acc["data_limit"]) if acc["data_limit"] > 0 else "Unlimited"
                text_parts.append(
                    "  {}. <code>{}</code> - {}/{}".format(
                        i, acc["username"], format_bytes(acc["data_used"]), limit_str
                    )
                )
        else:
            text_parts.append("  No data available.")

        await update.message.reply_text("".join(text_parts), parse_mode="HTML")

    except ImportError:
        await update.message.reply_text(
            "Error: psutil is not installed.", parse_mode="HTML"
        )
    except Exception as exc:
        logger.error("Monitor error: %s", exc)
        await update.message.reply_text("Error: {}".format(exc), parse_mode="HTML")


# --------------- Restart Services ---------------

@require_admin
async def cmd_restart(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /restart - show service restart menu."""
    keyboard = InlineKeyboardMarkup([
        [
            InlineKeyboardButton("All Services", callback_data="restart_all"),
            InlineKeyboardButton("XRay", callback_data="restart_xray"),
        ],
        [
            InlineKeyboardButton("SSH", callback_data="restart_ssh"),
            InlineKeyboardButton("OpenVPN", callback_data="restart_openvpn"),
            InlineKeyboardButton("Nginx", callback_data="restart_nginx"),
        ],
        [
            InlineKeyboardButton("Cancel", callback_data="cancel"),
        ],
    ])
    await update.message.reply_text(
        "<b>Restart Services</b>\n\nSelect a service to restart:",
        parse_mode="HTML", reply_markup=keyboard
    )


# --------------- Backup ---------------

@require_admin
async def cmd_backup(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /backup - create a configuration backup."""
    await update.message.reply_text("Creating backup, please wait...", parse_mode="HTML")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = "/etc/braanx/backups"
    os.makedirs(backup_dir, exist_ok=True)
    backup_file = os.path.join(backup_dir, "braanx_backup_{}.tar.gz".format(timestamp))

    rc, out, err = run_cmd(
        "tar -czf {backup} -C /etc/braanx . 2>/dev/null".format(backup=backup_file),
        timeout=120
    )

    if rc == 0 and os.path.isfile(backup_file):
        size = format_bytes(os.path.getsize(backup_file))
        await update.message.reply_text(
            "<b>Backup Complete</b>\n\n"
            "File: <code>{}</code>\n"
            "Size: {}".format(backup_file, size),
            parse_mode="HTML"
        )
        logger.info("Backup created: %s (%s)", backup_file, size)
    else:
        await update.message.reply_text(
            "<b>Backup Failed</b>\n{}".format(err or "Unknown error"),
            parse_mode="HTML"
        )


# --------------- Cancel ---------------

async def cmd_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle /cancel - cancel current operation."""
    clear_user_state(update.effective_user.id)
    await update.message.reply_text("Operation cancelled.", parse_mode="HTML")


# --------------- Callback Query Handler ---------------

async def callback_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle all inline keyboard button presses."""
    query = update.callback_query
    await query.answer()
    user_id = query.from_user.id
    data = query.data

    try:
        # --- Cancel ---
        if data == "cancel":
            clear_user_state(user_id)
            await query.edit_message_text("Operation cancelled.", parse_mode="HTML")
            return

        # --- Main Menu Buttons ---
        if data == "menu_mgmt":
            await query.edit_message_text(
                "<b>VPN Management</b>\n\n"
                "/create - Create new account\n"
                "/delete - Delete account\n"
                "/renew - Renew account\n"
                "/trial - Create trial account\n"
                "/accounts - List accounts",
                parse_mode="HTML"
            )
            return

        if data == "menu_info":
            info = collect_server_info()
            text = (
                "<b>Server Information</b>\n\n"
                "<b>IP:</b> <code>{ip}</code>\n"
                "<b>Domain:</b> <code>{domain}</code>\n"
                "<b>Uptime:</b> {uptime}\n"
                "<b>CPU:</b> {cpu}%\n"
                "<b>RAM:</b> {ram_used} / {ram_total} ({ram_p}%)\n"
                "<b>Disk:</b> {disk_used} / {disk_total} ({disk_p}%)\n"
                "<b>Accounts:</b> {total} total, {active} active"
            ).format(
                ip=info.get("ip", "N/A"), domain=info.get("domain", "N/A"),
                uptime=info.get("uptime", "N/A"), cpu=info.get("cpu_percent", "N/A"),
                ram_used=info.get("ram_used", "N/A"), ram_total=info.get("ram_total", "N/A"),
                ram_p=info.get("ram_percent", "N/A"),
                disk_used=info.get("disk_used", "N/A"), disk_total=info.get("disk_total", "N/A"),
                disk_p=info.get("disk_percent", "N/A"),
                total=info.get("total_accounts", 0), active=info.get("active_accounts", 0),
            )
            await query.edit_message_text(text, parse_mode="HTML")
            return

        if data == "menu_accounts":
            await query.edit_message_text(
                "<b>Account Actions</b>\n\n"
                "/accounts - List all accounts\n"
                "/create - Create new account\n"
                "/delete - Delete account\n"
                "/renew - Renew expiring accounts",
                parse_mode="HTML"
            )
            return

        if data == "menu_tools":
            await query.edit_message_text(
                "<b>System Tools</b>\n\n"
                "/restart - Restart services\n"
                "/backup - Create backup\n"
                "/monitor - Bandwidth monitor",
                parse_mode="HTML"
            )
            return

        if data == "menu_help":
            await query.edit_message_text(
                "<b>Help</b>\n\n"
                "Use command buttons or type:\n"
                "/start, /menu, /info, /accounts,\n"
                "/create, /delete, /renew, /trial,\n"
                "/monitor, /restart, /backup, /cancel",
                parse_mode="HTML"
            )
            return

        if data == "menu_settings":
            await query.edit_message_text(
                "<b>Settings</b>\n\n"
                "Bot configuration is managed via:\n"
                "<code>/etc/braanx/braanx.conf</code>\n\n"
                "Admin IDs: <code>/etc/braanx/bot/admins.txt</code>\n\n"
                "Edit these files on the server to update settings.",
                parse_mode="HTML"
            )
            return

        # --- Account Pagination ---
        if data.startswith("acc_page_"):
            page = int(data.split("_")[-1])
            context.user_data["accounts_page"] = page
            await show_accounts_page(update, context, page)
            return

        # --- Protocol Selection (Create Workflow Step 1) ---
        if data.startswith("proto_"):
            protocol = data.split("_", 1)[1].capitalize()
            state = get_user_state(user_id)
            state["protocol"] = protocol
            state["step"] = "enter_username"

            await query.edit_message_text(
                "<b>Create Account</b>\n\n"
                "Step 2/5: Enter username\n\n"
                "Protocol: <b>{}</b>\n\n"
                "Send the desired username:".format(protocol),
                parse_mode="HTML"
            )
            return

        # --- Duration Selection (Create Workflow Step 4) ---
        if data.startswith("dur_"):
            days = int(data.split("_")[1])
            state = get_user_state(user_id)
            state["days"] = days
            state["step"] = "confirm_create"

            proto = state.get("protocol", "?")
            uname = state.get("username", "?")
            keyboard = InlineKeyboardMarkup([
                [InlineKeyboardButton("Confirm", callback_data="create_confirm")],
                [InlineKeyboardButton("Cancel", callback_data="cancel")],
            ])
            await query.edit_message_text(
                "<b>Create Account</b>\n\n"
                "Step 5/5: Confirm\n\n"
                "<b>Username:</b> <code>{}</code>\n"
                "<b>Protocol:</b> {}\n"
                "<b>Duration:</b> {} days\n\n"
                "Confirm creation?".format(uname, proto, days),
                parse_mode="HTML", reply_markup=keyboard
            )
            return

        # --- Confirm Creation ---
        if data == "create_confirm":
            state = get_user_state(user_id)
            proto = state.get("protocol", "")
            uname = state.get("username", "")
            pwd = state.get("password", "")
            days = state.get("days", 1)

            try:
                if proto == "SSH":
                    success, result = create_ssh_account(uname, pwd, days)
                    if success:
                        ip = get_server_ip()
                        text = (
                            "<b>Account Created</b>\n\n"
                            "<b>Username:</b> <code>{user}</code>\n"
                            "<b>Password:</b> <code>{pwd}</code>\n"
                            "<b>Protocol:</b> SSH\n"
                            "<b>Expiry:</b> {days} days\n\n"
                            "<b>Connection:</b>\n"
                            "<code>ssh {user}@{ip}</code>"
                        ).format(user=uname, pwd=pwd, days=days, ip=ip)
                    else:
                        text = "<b>Error</b>\n{}".format(result)

                elif proto in ("VLESS", "VMess", "Trojan"):
                    success, link = create_xray_account(uname, proto, days)
                    if success:
                        text = (
                            "<b>Account Created</b>\n\n"
                            "<b>Username:</b> <code>{user}</code>\n"
                            "<b>Protocol:</b> {proto}\n"
                            "<b>Expiry:</b> {days} days\n\n"
                            "<b>Connection Link:</b>\n"
                            "<code>{link}</code>"
                        ).format(user=uname, proto=proto, days=days, link=link)
                    else:
                        text = "<b>Error</b>\n{}".format(link)

                elif proto == "OpenVPN":
                    success, ovpn = create_openvpn_account(uname, days)
                    if success:
                        text = (
                            "<b>Account Created</b>\n\n"
                            "<b>Username:</b> <code>{user}</code>\n"
                            "<b>Protocol:</b> OpenVPN\n"
                            "<b>Expiry:</b> {days} days\n\n"
                            "<b>Config:</b>\n"
                            "<pre>{ovpn}</pre>"
                        ).format(user=uname, days=days, ovpn=ovpn[:1000])
                    else:
                        text = "<b>Error</b>\n{}".format(ovpn)
                else:
                    text = "Unknown protocol: {}".format(proto)

                clear_user_state(user_id)
                await query.edit_message_text(text, parse_mode="HTML")
                logger.info("Account created: %s (%s) by admin %s", uname, proto, user_id)

            except Exception as exc:
                logger.error("Account creation error: %s", exc)
                clear_user_state(user_id)
                await query.edit_message_text(
                    "<b>Error</b>\nFailed to create account: {}".format(exc),
                    parse_mode="HTML"
                )
            return

        # --- Delete Account ---
        if data.startswith("del_"):
            username = data[4:]
            state = get_user_state(user_id)
            state["delete_target"] = username
            state["step"] = "delete_confirm"

            keyboard = InlineKeyboardMarkup([
                [InlineKeyboardButton("Yes, Delete", callback_data="del_confirm")],
                [InlineKeyboardButton("Cancel", callback_data="cancel")],
            ])
            await query.edit_message_text(
                "<b>Confirm Deletion</b>\n\n"
                "Delete account <code>{}</code>?\n\n"
                "This action cannot be undone.".format(username),
                parse_mode="HTML", reply_markup=keyboard
            )
            return

        if data == "del_confirm":
            state = get_user_state(user_id)
            username = state.get("delete_target", "")
            if not username:
                await query.edit_message_text("No account selected.", parse_mode="HTML")
                return

            acc = db_get_account(username)
            proto = acc["protocol"] if acc else "Unknown"

            try:
                if proto == "SSH":
                    delete_ssh_account(username)
                elif proto in ("VLESS", "VMess", "Trojan"):
                    delete_xray_account(username)
                else:
                    db_delete_account(username)

                clear_user_state(user_id)
                await query.edit_message_text(
                    "<b>Account Deleted</b>\n\n"
                    "<code>{}</code> ({}) has been removed.".format(username, proto),
                    parse_mode="HTML"
                )
                logger.info("Account deleted: %s (%s) by admin %s", username, proto, user_id)

            except Exception as exc:
                logger.error("Delete error: %s", exc)
                await query.edit_message_text(
                    "<b>Error</b>\nFailed to delete: {}".format(exc),
                    parse_mode="HTML"
                )
            return

        # --- Renew Account Duration Selection ---
        if data.startswith("renew_"):
            username = data[6:]
            state = get_user_state(user_id)
            state["renew_target"] = username
            state["step"] = "renew_duration"

            keyboard = InlineKeyboardMarkup([
                [
                    InlineKeyboardButton("1d", callback_data="rndays_1"),
                    InlineKeyboardButton("3d", callback_data="rndays_3"),
                    InlineKeyboardButton("7d", callback_data="rndays_7"),
                    InlineKeyboardButton("14d", callback_data="rndays_14"),
                ],
                [
                    InlineKeyboardButton("30d", callback_data="rndays_30"),
                    InlineKeyboardButton("60d", callback_data="rndays_60"),
                    InlineKeyboardButton("90d", callback_data="rndays_90"),
                ],
                [InlineKeyboardButton("Cancel", callback_data="cancel")],
            ])
            await query.edit_message_text(
                "<b>Renew Account</b>\n\n"
                "Account: <code>{}</code>\n\n"
                "Select new duration:".format(username),
                parse_mode="HTML", reply_markup=keyboard
            )
            return

        if data.startswith("rndays_"):
            days = int(data.split("_")[1])
            state = get_user_state(user_id)
            username = state.get("renew_target", "")

            try:
                db_renew_account(username, days)
                # Update SSH expiry if applicable
                acc = db_get_account(username)
                if acc and acc["protocol"] == "SSH":
                    expiry_date = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
                    run_cmd("chage -E {exp} {user}".format(exp=expiry_date, user=username))

                clear_user_state(user_id)
                new_acc = db_get_account(username)
                new_exp = new_acc["expiry"] if new_acc else "Unknown"
                await query.edit_message_text(
                    "<b>Account Renewed</b>\n\n"
                    "<code>{}</code>\n"
                    "New expiry: {}".format(username, new_exp),
                    parse_mode="HTML"
                )
                logger.info("Account renewed: %s +%d days by admin %s", username, days, user_id)

            except Exception as exc:
                logger.error("Renew error: %s", exc)
                await query.edit_message_text(
                    "<b>Error</b>\nFailed to renew: {}".format(exc),
                    parse_mode="HTML"
                )
            return

        # --- Restart Service ---
        if data.startswith("restart_"):
            svc = data[8:]
            service_map = {
                "all": "xray nginx sshd openvpn",
                "xray": "xray",
                "ssh": "sshd",
                "openvpn": "openvpn",
                "nginx": "nginx",
            }
            svc_list = service_map.get(svc, svc)
            await query.edit_message_text(
                "Restarting {}...".format(svc), parse_mode="HTML"
            )
            rc, out, err = run_cmd(
                "systemctl restart {}".format(svc_list), timeout=30
            )
            status = "OK" if rc == 0 else "FAILED: {}".format(err)
            await query.edit_message_text(
                "<b>Service Restart</b>\n\n"
                "Service(s): {}\n"
                "Status: <b>{}</b>".format(svc, status),
                parse_mode="HTML"
            )
            logger.info("Service restart: %s -> %s", svc, status)
            return

        # Unknown callback
        await query.edit_message_text("Unknown action.", parse_mode="HTML")

    except Exception as exc:
        logger.error("Callback handler error: %s", exc)
        try:
            await query.edit_message_text(
                "<b>Error</b>\n{}".format(exc), parse_mode="HTML"
            )
        except Exception:
            pass


# --------------- Message Handler (text input for workflows) ---------------

async def message_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handle text messages for multi-step workflows."""
    user_id = update.effective_user.id
    text = update.message.text.strip()

    if not is_admin(user_id):
        await update.message.reply_text(
            "You are not authorized. Type /help for available commands.",
            parse_mode="HTML"
        )
        return

    state = get_user_state(user_id)
    step = state.get("step", "")

    try:
        # Step: enter username
        if step == "enter_username":
            if not text or " " in text:
                await update.message.reply_text(
                    "Invalid username. Use alphanumeric characters only (no spaces). Try again:",
                    parse_mode="HTML"
                )
                return

            # Check if username already exists
            existing = db_get_account(text)
            if existing:
                await update.message.reply_text(
                    "Username '{}' already exists. Choose a different username:".format(text),
                    parse_mode="HTML"
                )
                return

            state["username"] = text

            # If SSH, ask for password; otherwise skip to duration
            if state.get("protocol") == "SSH":
                state["step"] = "enter_password"
                await update.message.reply_text(
                    "<b>Create Account</b>\n\n"
                    "Step 3/5: Enter password\n\n"
                    "Username: <code>{}</code>\n\n"
                    "Send the desired password:".format(text),
                    parse_mode="HTML"
                )
            else:
                # Skip to duration for XRay/OpenVPN (auto-generate UUID)
                state["step"] = "enter_duration"
                keyboard = InlineKeyboardMarkup([
                    [
                        InlineKeyboardButton("1d", callback_data="dur_1"),
                        InlineKeyboardButton("3d", callback_data="dur_3"),
                        InlineKeyboardButton("7d", callback_data="dur_7"),
                        InlineKeyboardButton("14d", callback_data="dur_14"),
                    ],
                    [
                        InlineKeyboardButton("30d", callback_data="dur_30"),
                        InlineKeyboardButton("60d", callback_data="dur_60"),
                        InlineKeyboardButton("90d", callback_data="dur_90"),
                    ],
                    [InlineKeyboardButton("Cancel", callback_data="cancel")],
                ])
                await update.message.reply_text(
                    "<b>Create Account</b>\n\n"
                    "Step 4/5: Select duration\n\n"
                    "Username: <code>{}</code>\n"
                    "Protocol: <b>{}</b>\n\n"
                    "Choose duration:".format(text, state.get("protocol", "")),
                    parse_mode="HTML", reply_markup=keyboard
                )
            return

        # Step: enter password
        if step == "enter_password":
            if not text or len(text) < 4:
                await update.message.reply_text(
                    "Password too short (minimum 4 characters). Try again:",
                    parse_mode="HTML"
                )
                return
            state["password"] = text
            state["step"] = "enter_duration"

            keyboard = InlineKeyboardMarkup([
                [
                    InlineKeyboardButton("1d", callback_data="dur_1"),
                    InlineKeyboardButton("3d", callback_data="dur_3"),
                    InlineKeyboardButton("7d", callback_data="dur_7"),
                    InlineKeyboardButton("14d", callback_data="dur_14"),
                ],
                [
                    InlineKeyboardButton("30d", callback_data="dur_30"),
                    InlineKeyboardButton("60d", callback_data="dur_60"),
                    InlineKeyboardButton("90d", callback_data="dur_90"),
                ],
                [InlineKeyboardButton("Cancel", callback_data="cancel")],
            ])
            await update.message.reply_text(
                "<b>Create Account</b>\n\n"
                "Step 4/5: Select duration\n\n"
                "Username: <code>{}</code>\n"
                "Protocol: <b>{}</b>\n\n"
                "Choose duration:".format(state.get("username", ""), state.get("protocol", "")),
                parse_mode="HTML", reply_markup=keyboard
            )
            return

        # Unrecognised text in a workflow
        if step:
            await update.message.reply_text(
                "Unexpected input. Use /cancel to abort or select a button.",
                parse_mode="HTML"
            )
            return

    except Exception as exc:
        logger.error("Message handler error: %s", exc)
        await update.message.reply_text("Error: {}".format(exc), parse_mode="HTML")


# --------------- Signal Handling ---------------

def signal_handler(sig, frame):
    """Graceful shutdown on SIGINT/SIGTERM."""
    logger.info("Received signal %s, shutting down...", sig)
    if application:
        application.stop()
    sys.exit(0)


# --------------- Main Entry Point ---------------

def main():
    """Initialise and run the BraanX Telegram bot."""
    global application

    # Ensure required directories
    for d in (os.path.dirname(DB_PATH), BOT_DIR, os.path.dirname(LOG_FILE)):
        os.makedirs(d, exist_ok=True)

    # Load configuration
    load_config()
    load_admins()

    # Initialise database
    init_db()

    # Get bot token
    token = config.get("TELEGRAM_BOT_TOKEN", "")
    if not token:
        logger.error("TELEGRAM_BOT_TOKEN not set in %s", CONF_PATH)
        sys.exit(1)

    # Signal handling
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Build application
    application = Application.builder().token(token).build()

    # Register command handlers
    application.add_handler(CommandHandler("start", cmd_start))
    application.add_handler(CommandHandler("help", cmd_help))
    application.add_handler(CommandHandler("menu", cmd_menu))
    application.add_handler(CommandHandler("info", cmd_info))
    application.add_handler(CommandHandler("accounts", cmd_accounts))
    application.add_handler(CommandHandler("create", cmd_create))
    application.add_handler(CommandHandler("delete", cmd_delete))
    application.add_handler(CommandHandler("renew", cmd_renew))
    application.add_handler(CommandHandler("trial", cmd_trial))
    application.add_handler(CommandHandler("monitor", cmd_monitor))
    application.add_handler(CommandHandler("restart", cmd_restart))
    application.add_handler(CommandHandler("backup", cmd_backup))
    application.add_handler(CommandHandler("cancel", cmd_cancel))

    # Register callback query handler (inline keyboards)
    application.add_handler(CallbackQueryHandler(callback_handler))

    # Register message handler (text input for workflows)
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND, message_handler
    ))

    # Schedule background task (every 6 hours)
    application.job_queue.run_repeating(
        background_checker, interval=6 * 3600, first=60
    )

    logger.info("BraanX Telegram Bot starting...")
    application.run_polling(allowed_updates=Update.ALL_TYPES)
    logger.info("BraanX Telegram Bot stopped.")


if __name__ == "__main__":
    main()