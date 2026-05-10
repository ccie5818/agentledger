#!/usr/bin/env bash
# Automated installer for OpenClaw (https://openclaw.ai)
# Works on macOS, Linux, and WSL / Git Bash on Windows.
#
# Configuration is read from a key=value config file (default:
# openclaw-install.config alongside this script). CLI flags override config.
#
# Usage:
#   ./install-openclaw.sh                       # use openclaw-install.config
#   ./install-openclaw.sh --config my.cfg       # custom config file
#   ./install-openclaw.sh --method npm          # override method
#   ./install-openclaw.sh --method git --force
#   ./install-openclaw.sh --skip-onboard
#   ./install-openclaw.sh --channel dev
#
# Refuses to run as root; uses sudo only when needed.

set -euo pipefail

# --- defaults (overridable by config file, then by CLI) -------------------

METHOD="oneline"
INSTALL_DIR="${HOME}/openclaw"
SKIP_ONBOARD=0
FORCE=0
MIN_NODE_MAJOR=20
AUTO_INSTALL_NODE=1
CHANNEL=""
ONBOARD_ARGS=""
CONFIG_FILE=""

# Secrets read from config file. Empty by default; existing env vars win.
ANTHROPIC_API_KEY_CFG=""
OPENAI_API_KEY_CFG=""
TELEGRAM_BOT_TOKEN_CFG=""

# Track which fields were explicitly set on the CLI so they win over config.
declare -A CLI_SET=()

# --- output helpers --------------------------------------------------------

if [[ -t 1 ]]; then
    c_cyan="$(printf '\033[36m')";    c_green="$(printf '\033[32m')"
    c_yellow="$(printf '\033[33m')";  c_red="$(printf '\033[31m')"
    c_magenta="$(printf '\033[35m')"; c_dim="$(printf '\033[2m')"
    c_reset="$(printf '\033[0m')"
else
    c_cyan=""; c_green=""; c_yellow=""; c_red=""; c_magenta=""; c_dim=""; c_reset=""
fi

step()  { printf '%s==> %s%s\n' "$c_cyan"   "$*" "$c_reset"; }
ok()    { printf '%s    %s%s\n' "$c_green"  "$*" "$c_reset"; }
warn()  { printf '%s    %s%s\n' "$c_yellow" "$*" "$c_reset"; }
err()   { printf '%s!!  %s%s\n' "$c_red"    "$*" "$c_reset" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

# --- helpers --------------------------------------------------------------

to_bool() {
    local v default
    v="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | xargs)"
    default="${2:-0}"
    case "$v" in
        1|true|yes|y|on)   echo 1 ;;
        0|false|no|n|off)  echo 0 ;;
        '')                echo "$default" ;;
        *)                 echo "$default" ;;
    esac
}

expand_path() {
    local p="${1:-}"
    [[ -z "$p" ]] && { echo ""; return; }
    if [[ "$p" == "~" ]]; then echo "$HOME"; return; fi
    if [[ "$p" == "~/"* ]]; then echo "${HOME}/${p:2}"; return; fi
    eval "echo \"$p\""
}

usage() {
    sed -n '2,18p' "$0"
    exit "${1:-0}"
}

# --- arg parsing ----------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)        CONFIG_FILE="${2:-}";  shift 2 ;;
        --config=*)      CONFIG_FILE="${1#*=}"; shift ;;
        --method)        METHOD="${2:-}";       CLI_SET[method]=1; shift 2 ;;
        --method=*)      METHOD="${1#*=}";      CLI_SET[method]=1; shift ;;
        --install-dir)   INSTALL_DIR="${2:-}";  CLI_SET[install_dir]=1; shift 2 ;;
        --install-dir=*) INSTALL_DIR="${1#*=}"; CLI_SET[install_dir]=1; shift ;;
        --channel)       CHANNEL="${2:-}";      CLI_SET[channel]=1; shift 2 ;;
        --channel=*)     CHANNEL="${1#*=}";     CLI_SET[channel]=1; shift ;;
        --skip-onboard)  SKIP_ONBOARD=1;        CLI_SET[skip_onboard]=1; shift ;;
        --force)         FORCE=1;               CLI_SET[force]=1; shift ;;
        -h|--help)       usage 0 ;;
        *)               err "unknown argument: $1"; usage 1 ;;
    esac
done

# --- config loading -------------------------------------------------------

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ -z "$CONFIG_FILE" ]]; then
    CONFIG_FILE="${script_dir}/openclaw-install.config"
fi

read_config() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        [[ "$line" != *"="* ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        if [[ "${val:0:1}" == '"' && "${val: -1}" == '"' ]] ||
           [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
            val="${val:1:${#val}-2}"
        fi
        key="$(echo "$key" | xargs)"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"

        case "$key" in
            method)            [[ -z "${CLI_SET[method]:-}"      ]] && METHOD="$val" ;;
            install_dir)       [[ -z "${CLI_SET[install_dir]:-}" ]] && INSTALL_DIR="$(expand_path "$val")" ;;
            skip_onboard)      [[ -z "${CLI_SET[skip_onboard]:-}" ]] && SKIP_ONBOARD="$(to_bool "$val" 0)" ;;
            force)             [[ -z "${CLI_SET[force]:-}"        ]] && FORCE="$(to_bool "$val" 0)" ;;
            min_node_major)    MIN_NODE_MAJOR="$val" ;;
            auto_install_node) AUTO_INSTALL_NODE="$(to_bool "$val" 1)" ;;
            channel)           [[ -z "${CLI_SET[channel]:-}"      ]] && CHANNEL="$val" ;;
            onboard_args)      ONBOARD_ARGS="$val" ;;
            anthropic_api_key)  ANTHROPIC_API_KEY_CFG="$val" ;;
            openai_api_key)     OPENAI_API_KEY_CFG="$val" ;;
            telegram_bot_token) TELEGRAM_BOT_TOKEN_CFG="$val" ;;
            *) warn "unknown config key '$key' (ignored)" ;;
        esac
    done < "$file"
    return 0
}

read_config "$CONFIG_FILE"

case "$METHOD" in
    oneline|npm|git) ;;
    *) err "invalid method '$METHOD' (use: oneline | npm | git)"; exit 1 ;;
esac

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    err "Do not run this script as root. Re-run as your normal user."
    exit 1
fi

# --- pre-flight -----------------------------------------------------------

ensure_curl() {
    if ! has curl; then
        err "curl is required. Install it (e.g. 'sudo apt install curl' or 'brew install curl')."
        exit 1
    fi
}

node_major() {
    has node || { echo 0; return; }
    node --version 2>/dev/null | sed -E 's/^v//' | cut -d. -f1
}

ensure_node() {
    step "Checking Node.js"
    local major
    major="$(node_major)"
    if [[ "$major" -ge "$MIN_NODE_MAJOR" ]]; then
        ok "Node.js v$major detected (>= $MIN_NODE_MAJOR)."
        return
    fi
    if [[ "$major" -gt 0 ]]; then
        warn "Node.js v$major is too old (need >= $MIN_NODE_MAJOR)."
    else
        warn "Node.js not found."
    fi
    if [[ "$AUTO_INSTALL_NODE" -ne 1 ]]; then
        err "auto_install_node=false in config. Install Node.js >= v$MIN_NODE_MAJOR and re-run."
        exit 1
    fi

    if has brew; then
        brew install node
    elif has apt-get; then
        ensure_curl
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif has dnf; then
        ensure_curl
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo -E bash -
        sudo dnf install -y nodejs
    elif has pacman; then
        sudo pacman -Sy --noconfirm nodejs npm
    else
        err "Could not detect a package manager. Install Node.js (>= $MIN_NODE_MAJOR) manually and re-run."
        exit 1
    fi

    major="$(node_major)"
    if [[ "$major" -lt "$MIN_NODE_MAJOR" ]]; then
        err "Node.js install did not produce >= v$MIN_NODE_MAJOR (got v$major)."
        exit 1
    fi
    ok "Node.js v$major ready."
}

ensure_npm() {
    has npm || { err "npm not found after Node install"; exit 1; }
}

# --- install methods ------------------------------------------------------

install_oneline() {
    step "Running official OpenClaw installer"
    ensure_curl
    curl -fsSL https://openclaw.ai/install.sh | bash
}

install_npm() {
    ensure_node
    ensure_npm
    step "Installing OpenClaw via npm (global)"
    if npm ls -g --depth=0 openclaw >/dev/null 2>&1 && [[ "$FORCE" -eq 0 ]]; then
        ok "openclaw already installed globally; updating."
        if ! npm update -g openclaw 2>/dev/null; then
            warn "Global update without sudo failed; retrying with sudo."
            sudo npm update -g openclaw
        fi
    else
        if ! npm install -g openclaw 2>/dev/null; then
            warn "Global install without sudo failed; retrying with sudo."
            sudo npm install -g openclaw
        fi
    fi
    ok "openclaw npm package installed."
}

install_git() {
    ensure_node
    ensure_npm
    has git || { err "git is required for method=git"; exit 1; }

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        if [[ "$FORCE" -eq 1 ]]; then
            warn "Removing existing $INSTALL_DIR (force=true)"
            rm -rf "$INSTALL_DIR"
        else
            ok "Existing checkout at $INSTALL_DIR; pulling latest."
            git -C "$INSTALL_DIR" pull --ff-only
        fi
    fi
    if [[ ! -d "$INSTALL_DIR/.git" ]]; then
        step "Cloning OpenClaw into $INSTALL_DIR"
        git clone https://github.com/openclaw/openclaw.git "$INSTALL_DIR"
    fi

    step "Enabling corepack and installing workspace deps"
    corepack enable >/dev/null 2>&1 || sudo corepack enable
    ( cd "$INSTALL_DIR" && pnpm install )
    ok "Source install ready at $INSTALL_DIR"
}

# --- secrets --------------------------------------------------------------

warn_config_perms() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    local mode
    mode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null || echo '')"
    [[ -z "$mode" ]] && return 0
    if [[ "${mode: -2}" != "00" ]]; then
        warn "Config file '$f' has mode $mode and may contain secrets."
        warn "Tighten with: chmod 600 \"$f\""
    fi
    return 0
}

apply_secrets() {
    local printed=0 set_any=0
    set_one() {
        local env_name="$1" cfg_val="$2" label="$3"
        if [[ -n "${!env_name:-}" ]]; then return 0; fi
        [[ -z "$cfg_val" ]] && return 0
        export "$env_name=$cfg_val"
        ok "  $label -> environment"
        set_any=1
    }
    if [[ -n "$ANTHROPIC_API_KEY_CFG" || -n "$OPENAI_API_KEY_CFG" || -n "$TELEGRAM_BOT_TOKEN_CFG" ]]; then
        if [[ ( -z "${ANTHROPIC_API_KEY:-}"  && -n "$ANTHROPIC_API_KEY_CFG"  ) ]] ||
           [[ ( -z "${OPENAI_API_KEY:-}"     && -n "$OPENAI_API_KEY_CFG"     ) ]] ||
           [[ ( -z "${TELEGRAM_BOT_TOKEN:-}" && -n "$TELEGRAM_BOT_TOKEN_CFG" ) ]]; then
            step "Exporting credentials from config"
            printed=1
        fi
    fi
    set_one ANTHROPIC_API_KEY  "$ANTHROPIC_API_KEY_CFG"  "Anthropic API key"
    set_one OPENAI_API_KEY     "$OPENAI_API_KEY_CFG"     "OpenAI API key"
    set_one TELEGRAM_BOT_TOKEN "$TELEGRAM_BOT_TOKEN_CFG" "Telegram bot token"
    if [[ "$printed" -eq 1 && "$set_any" -eq 0 ]]; then
        ok "  (all already set in environment)"
    fi
    return 0
}

# --- post-install steps ---------------------------------------------------

switch_channel() {
    [[ -z "$CHANNEL" ]] && return 0
    step "Switching OpenClaw to '$CHANNEL' channel"
    if [[ "$METHOD" == "git" ]]; then
        ( cd "$INSTALL_DIR" && pnpm openclaw update --channel "$CHANNEL" )
    else
        if has openclaw; then
            openclaw update --channel "$CHANNEL"
        else
            warn "openclaw not on PATH yet; run later: openclaw update --channel $CHANNEL"
        fi
    fi
}

run_onboard() {
    if [[ "$SKIP_ONBOARD" -eq 1 ]]; then
        ok "Skipping onboarding (skip_onboard=true). Run 'openclaw onboard' when ready."
        return
    fi
    step "Starting OpenClaw onboarding"
    ok "This is interactive; answer the prompts to meet your lobster."
    # shellcheck disable=SC2206
    local extra=( $ONBOARD_ARGS )
    if [[ "$METHOD" == "git" ]]; then
        ( cd "$INSTALL_DIR" && pnpm openclaw onboard "${extra[@]}" )
    else
        if ! has openclaw; then
            warn "openclaw not on PATH yet; open a fresh terminal and run: openclaw onboard"
            return
        fi
        openclaw onboard "${extra[@]}"
    fi
}

# --- main -----------------------------------------------------------------

printf '\n%s+--------------------------------------------+%s\n' "$c_magenta" "$c_reset"
printf '%s|        OpenClaw Automated Installer        |%s\n'   "$c_magenta" "$c_reset"
printf '%s+--------------------------------------------+%s\n'   "$c_magenta" "$c_reset"
if [[ -f "$CONFIG_FILE" ]]; then
    printf '%s    config:  %s%s\n' "$c_dim" "$CONFIG_FILE" "$c_reset"
else
    printf '%s    config:  (not found; using built-in defaults)%s\n' "$c_dim" "$c_reset"
fi
printf '%s    method:  %s%s\n' "$c_dim" "$METHOD" "$c_reset"
[[ "$METHOD" == "git" ]] && printf '%s    dir:     %s%s\n' "$c_dim" "$INSTALL_DIR" "$c_reset"
[[ -n "$CHANNEL"      ]] && printf '%s    channel: %s%s\n' "$c_dim" "$CHANNEL"     "$c_reset"
echo

case "$METHOD" in
    oneline) install_oneline ;;
    npm)     install_npm     ;;
    git)     install_git     ;;
esac

switch_channel
warn_config_perms "$CONFIG_FILE"
apply_secrets
run_onboard

ok "Done. Docs: https://docs.openclaw.ai/getting-started"
