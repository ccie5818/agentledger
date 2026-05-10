#!/usr/bin/env bash
# Install the OpenClaw + Telegram local status dashboard.
#
#   - If OpenClaw isn't installed, installs it first (non-interactive)
#   - Copies dashboard.js to ~/.openclaw/dashboard/dashboard.js
#   - Installs a systemd --user unit that runs it on boot
#   - Enables + starts the unit
#   - Prints the URL
#
# Usage:
#   ./install-dashboard.sh                 # install + start
#   ./install-dashboard.sh --uninstall     # stop + remove

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DASHBOARD_SRC="${SCRIPT_DIR}/dashboard.js"
UNIT_SRC="${SCRIPT_DIR}/openclaw-dashboard.service"

DEST_DIR="${HOME}/.openclaw/dashboard"
DEST_SCRIPT="${DEST_DIR}/dashboard.js"
USER_SYSTEMD_DIR="${HOME}/.config/systemd/user"
UNIT_NAME="openclaw-dashboard.service"
UNIT_DEST="${USER_SYSTEMD_DIR}/${UNIT_NAME}"

# --- output helpers --------------------------------------------------------

if [[ -t 1 ]]; then
    c_cyan="$(printf '\033[36m')"; c_green="$(printf '\033[32m')"
    c_yellow="$(printf '\033[33m')"; c_red="$(printf '\033[31m')"
    c_reset="$(printf '\033[0m')"
else c_cyan=""; c_green=""; c_yellow=""; c_red=""; c_reset=""; fi
step() { printf '%s==> %s%s\n' "$c_cyan"   "$*" "$c_reset"; }
ok()   { printf '%s    %s%s\n' "$c_green"  "$*" "$c_reset"; }
warn() { printf '%s    %s%s\n' "$c_yellow" "$*" "$c_reset"; }
err()  { printf '%s!!  %s%s\n' "$c_red"    "$*" "$c_reset" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

uninstall() {
    step "Stopping and removing dashboard service"
    systemctl --user stop "$UNIT_NAME" 2>/dev/null || true
    systemctl --user disable "$UNIT_NAME" 2>/dev/null || true
    rm -f "$UNIT_DEST"
    systemctl --user daemon-reload 2>/dev/null || true
    rm -f "$DEST_SCRIPT"
    rmdir "$DEST_DIR" 2>/dev/null || true
    ok "Dashboard removed."
}

# --- arg parse -------------------------------------------------------------

case "${1:-}" in
    --uninstall|-u) uninstall; exit 0 ;;
    --help|-h)
        sed -n '2,12p' "$0"
        exit 0
        ;;
    '') ;;
    *) err "unknown argument: $1"; exit 1 ;;
esac

# --- preflight -------------------------------------------------------------

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    err "Do not run as root. Run as your normal user (the same one that owns ~/.openclaw)."
    exit 1
fi

if ! has systemctl; then
    err "systemctl not found; this installer assumes systemd --user. To run manually:"
    err "  node ${DASHBOARD_SRC}"
    exit 1
fi

# --- bootstrap OpenClaw if missing -----------------------------------------

bootstrap_openclaw() {
    if has openclaw; then
        ok "OpenClaw already installed: $(openclaw --version 2>/dev/null || echo 'present')"
        return
    fi
    step "OpenClaw not found on PATH — installing via official one-liner (non-interactive)"
    if ! has curl; then
        err "curl is required to install OpenClaw. Install with: sudo apt install -y curl"
        exit 1
    fi
    if ! has bash; then
        err "bash is required to install OpenClaw."
        exit 1
    fi
    # OpenClaw's installer also installs Node.js if missing.
    #   --no-prompt   picks default answers for every interactive question
    #   --no-onboard  skips the interactive onboarding wizard at the end
    # Pipe the script through bash with -s -- so flags reach the install
    # script itself, not bash.
    if ! curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard; then
        err "OpenClaw installation failed."
        err "Try running it directly to see the full output:"
        err "  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard"
        exit 1
    fi
    # OpenClaw typically installs into ~/.npm-global/bin or /usr/local/bin —
    # refresh PATH so the rest of this script can find it without reopening
    # the shell.
    export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:/usr/local/bin:${PATH}"
    if ! has openclaw; then
        err "OpenClaw install reported success but 'openclaw' still isn't on PATH."
        err "Open a new terminal (so PATH refreshes) and re-run: $0"
        exit 1
    fi
    ok "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'present')"
}

bootstrap_openclaw

if ! has node; then
    err "node is not on PATH (OpenClaw should have installed it). Open a new terminal and re-run."
    exit 1
fi

if [[ ! -f "$DASHBOARD_SRC" ]]; then
    err "Source not found: $DASHBOARD_SRC"
    exit 1
fi
if [[ ! -f "$UNIT_SRC" ]]; then
    err "Source not found: $UNIT_SRC"
    exit 1
fi

# --- install ---------------------------------------------------------------

step "Copying dashboard to $DEST_DIR"
mkdir -p "$DEST_DIR"
cp "$DASHBOARD_SRC" "$DEST_SCRIPT"
chmod 755 "$DEST_SCRIPT"
ok "dashboard.js -> $DEST_SCRIPT"

step "Installing systemd --user unit"
mkdir -p "$USER_SYSTEMD_DIR"
# Substitute %h with $HOME so the unit doesn't depend on systemd's expansion semantics
# being identical across distros, then replace ExecStart path explicitly.
sed -e "s|%h/.openclaw/dashboard/dashboard.js|${DEST_SCRIPT}|" "$UNIT_SRC" > "$UNIT_DEST"
chmod 644 "$UNIT_DEST"
ok "$UNIT_NAME -> $UNIT_DEST"

step "Reloading systemd and starting service"
systemctl --user daemon-reload
systemctl --user enable "$UNIT_NAME"
systemctl --user restart "$UNIT_NAME"

# Linger lets the service keep running after you log out (typical Pi setup).
if has loginctl; then
    if ! loginctl show-user "$USER" 2>/dev/null | grep -q '^Linger=yes'; then
        warn "User linger is OFF — service will stop when you log out."
        warn "Enable it with:  sudo loginctl enable-linger $USER"
    fi
fi

# Wait a moment, then check status.
sleep 1
if systemctl --user is-active --quiet "$UNIT_NAME"; then
    ok "Dashboard is running."
    # `systemctl show --property=Environment` prints a single line of the form
    # `Environment=DASHBOARD_HOST=0.0.0.0 DASHBOARD_PORT=18790`, so grep -oP
    # against the merged output is safe across drop-ins.
    ENV_LINE="$(systemctl --user show "$UNIT_NAME" --property=Environment 2>/dev/null || true)"
    PORT="$(printf '%s' "$ENV_LINE" | grep -oP 'DASHBOARD_PORT=\K\d+' | head -n1 || true)"
    HOST="$(printf '%s' "$ENV_LINE" | grep -oP 'DASHBOARD_HOST=\K\S+' | head -n1 || true)"
    [[ -z "$PORT" ]] && PORT="18790"
    [[ -z "$HOST" ]] && HOST="0.0.0.0"
    # When bound to 0.0.0.0 the literal address isn't useful in a browser —
    # surface the first LAN IP (or a hostname.local fallback) so the user can
    # actually click through.
    if [[ "$HOST" == "0.0.0.0" || "$HOST" == "::" ]]; then
        LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
        if [[ -n "$LAN_IP" ]]; then
            ok "Open in your browser:  http://${LAN_IP}:${PORT}/  (LAN-reachable)"
        else
            ok "Open in your browser:  http://<this-host>:${PORT}/  (bound to 0.0.0.0; couldn't detect LAN IP)"
        fi
        ok "Also reachable at:    http://localhost:${PORT}/  (from this machine)"
    else
        ok "Open in your browser:  http://${HOST}:${PORT}/"
    fi
else
    err "Dashboard failed to start. Logs:"
    journalctl --user -u "$UNIT_NAME" --no-pager -n 30 || true
    exit 1
fi

cat <<EOF

Useful follow-ups:
  systemctl --user status  ${UNIT_NAME}
  journalctl --user -u ${UNIT_NAME} -f
  systemctl --user restart ${UNIT_NAME}
  ${SCRIPT_DIR}/install-dashboard.sh --uninstall

Default bind is 0.0.0.0 (LAN-reachable). Auth is required (cookie session) but
the first-boot credentials are admin/admin — change the password on first login.
To bind locally only (127.0.0.1) instead:
  systemctl --user edit ${UNIT_NAME}
  # add:
  #   [Service]
  #   Environment=DASHBOARD_HOST=127.0.0.1
  systemctl --user restart ${UNIT_NAME}
EOF
