# OpenClaw + Telegram local dashboard

Single-page status/admin dashboard for your OpenClaw + Telegram setup. Runs on the same Pi (or any host running OpenClaw) as a `systemd --user` service. No npm dependencies — uses Node.js built-ins only.

## Login

The dashboard requires a login. On first boot it creates `~/.openclaw/dashboard/auth.json` with default credentials `admin`/`admin`. **Change them immediately** — anyone on your LAN can otherwise sign in. A red banner appears on every page until the default password is changed.

- Sessions are cookie-based (HttpOnly, SameSite=Lax), 24 h **idle timeout** — the TTL slides on every authenticated request, so an active session won't expire mid-use. Sessions are stored in memory (lost on dashboard restart) and capped at 1000 entries (oldest-evicted).
- The "Account" card on the main page lets you change the password (current + new + confirm; minimum 6 chars). Changing the password **invalidates every other session for your user** and rotates your cookie — useful if you think a cookie may have leaked.
- Use `Logout` in the page header (top right) to end your session.
- **Brute-force protection**: 5 failed login attempts from the same IP triggers a 60-second lockout (HTTP 429). The counter clears on a successful login or when the lockout expires.
- **Behind TLS?** Set `DASHBOARD_TRUST_PROXY=1` and the session cookie gets the `Secure` attribute. Leave it unset for plain-HTTP LAN deployments (the default) — setting `Secure` over HTTP would silently break login.

If you forget the password, delete `~/.openclaw/dashboard/auth.json` and restart the service — it'll recreate with `admin`/`admin`.

## What it shows

The page renders these cards, in this order:

- **OpenClaw** — version (`openclaw --version`), CLI reachability, config-file presence.
- **Model & API key** — current model (e.g. `anthropic/claude-opus-4-6`), which recognized provider keys are present in `~/.openclaw/.env` (only known provider env vars and anything ending `_API_KEY` are shown — unrelated entries like `PATH` overrides are filtered out), and a form to change the model and/or save a new API key. Optional "restart gateway after saving" applies the change immediately via `systemctl --user restart openclaw-gateway`.
- **Telegram** — enabled/configured/missing badge, redacted bot token, DM policy, group policy, allow-list size, configured groups, and the account list.
- **Update Telegram Pairing Code** — live output of `openclaw pairing list telegram`, with an approve form (paste a code, click Approve — runs `openclaw pairing approve telegram <CODE>`). Codes are validated against `^[A-Za-z0-9_-]{4,32}$` before being shelled out.
- **Update Telegram Bot Token** — form that writes `channels.telegram.botToken` into `~/.openclaw/openclaw.json` (with `chmod 600`), enables Telegram and sets `dmPolicy=pairing` if either is unset, and optionally restarts the gateway.
- **Remote Support** — shows whether `ssh.service` is running and enabled-on-boot, plus buttons to enable+start or disable+stop it. Disable is gated by a `confirm()` dialog to prevent accidental lockout. **Requires passwordless sudo for the toggle to work** — see the SSH section below.
- **Account** — current username, password status (default vs. set), and a form to rotate the password.

The page auto-refreshes every 5 seconds, **but pauses** while any input/select/textarea is focused or has typed content — so you won't lose a password mid-entry.

> Note: active session data is still gathered (best-effort) and exposed on the `GET /api/status` JSON endpoint for monitoring, but it's no longer rendered as a card on the main page.

## Install

```bash
./install-dashboard.sh
```

That:

1. Checks whether OpenClaw itself is installed; if not, runs the official non-interactive installer (`curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-prompt --no-onboard`) — which also brings Node.js if missing and skips the interactive onboarding wizard.
2. Copies `dashboard.js` to `~/.openclaw/dashboard/dashboard.js`.
3. Installs a `systemd --user` unit, enables it, starts it, and prints the URL.

**Default bind: `0.0.0.0:18790`** — the dashboard is reachable from anywhere on your LAN at `http://<pi-ip>:18790/`. To find the LAN IP: `hostname -I` on the Pi, or look for the device on your router. To bind locally only instead, see the security note below.

## Uninstall

```bash
./install-dashboard.sh --uninstall
```

## Manual run (without systemd)

```bash
node dashboard.js
# or to bind locally only:
DASHBOARD_HOST=127.0.0.1 node dashboard.js
# or change the port:
DASHBOARD_PORT=8080 node dashboard.js
# or behind a TLS-terminating reverse proxy (cookie is marked Secure):
DASHBOARD_TRUST_PROXY=1 node dashboard.js
```

Recognized environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `DASHBOARD_HOST` | `0.0.0.0` | Interface to bind. Set to `127.0.0.1` for local-only. |
| `DASHBOARD_PORT` | `18790` | TCP port to listen on. |
| `DASHBOARD_TRUST_PROXY` | unset | Set to `1` when behind HTTPS to add `Secure` to the session cookie. |

## Where it reads from, writes to, and what it shells out

**Files read:**

| Path | What it gives the dashboard |
|---|---|
| `~/.openclaw/openclaw.json` | Telegram config + current model (`agents.defaults.model.primary`) |
| `~/.openclaw/.env` | Which provider env vars are set (presence only — values are never read) |
| `~/.openclaw/agents/main/sessions/sessions.json` | Active sessions list (best-effort; schema-tolerant). Surfaced only on `/api/status`, not on the main page. |
| `~/.openclaw/dashboard/auth.json` | Username + scrypt-hashed password + salt (`chmod 600`). Auto-created on first boot with `admin`/`admin`. |

**Files written:**

| Path | When |
|---|---|
| `~/.openclaw/openclaw.json` (`chmod 600`) | Save a new model (writes `agents.defaults.model.primary`) or a new Telegram bot token (writes `channels.telegram.botToken`, sets `enabled` and `dmPolicy` if unset). |
| `~/.openclaw/.env` (`chmod 600`) | Save an API key in the Model & API key form — upserts `<PROVIDER>_API_KEY=...` (or your custom env-var name). |
| `~/.openclaw/dashboard/auth.json` (`chmod 600`) | Created on first boot; rewritten on password change. |

**Subprocesses (always `execFile`, never the shell):**

| Command | When |
|---|---|
| `openclaw --version` | Every page render (cheap; cached at status-gather time only). |
| `openclaw pairing list telegram` | Every page render. |
| `openclaw pairing approve telegram <CODE>` | Approve form submit. Code is regex-validated first. |
| `systemctl is-active ssh`, `systemctl is-enabled ssh` | Every page render — no sudo needed. |
| `sudo -n systemctl enable\|disable --now ssh` | Remote Support toggle. Requires passwordless sudo (see "SSH toggle"). |
| `systemctl --user restart openclaw-gateway` | When you save a model/key/token change with "restart gateway" checked. |

If any of the file sources aren't present, the dashboard degrades gracefully (shows `—` or an error badge) instead of crashing. Same for subprocess failures — the relevant card shows an error message and the rest of the page still works.

## SSH toggle (one-time setup)

The SSH card reads service status without elevation, but enabling/disabling SSH requires `sudo`. The dashboard runs as your normal user, so you need to grant passwordless sudo for the two specific systemctl invocations. On the Pi:

```bash
sudo visudo -f /etc/sudoers.d/openclaw-dashboard
```

Add the line (replace `ubuntu` with your actual username if different):

```
ubuntu ALL=(root) NOPASSWD: /bin/systemctl enable --now ssh, /bin/systemctl disable --now ssh
```

Save (Ctrl+X, then Y, then Enter). The buttons in the dashboard's SSH card will now succeed. If sudo isn't configured, the dashboard pops up an alert with this same instruction.

This rule is intentionally narrow — only those two exact commands are permitted, so it can't be abused to run arbitrary other root commands.

## Security notes

- **Default bind is `0.0.0.0`** — reachable from your whole LAN. The dashboard requires a login (default `admin`/`admin`) and rate-limits failed attempts (5 failures → 60s lockout per IP), but the default credentials are well known — **change them on first login**. Until you do, anyone on your LAN can sign in and rotate provider keys, change the model, and send Telegram messages as your bot. To bind locally only instead, run:

  ```bash
  systemctl --user edit openclaw-dashboard
  # add:
  #   [Service]
  #   Environment=DASHBOARD_HOST=127.0.0.1
  systemctl --user restart openclaw-dashboard
  ```
- **Behind a reverse proxy (HTTPS)?** Set `DASHBOARD_TRUST_PROXY=1` via the same `systemctl --user edit` mechanism so the session cookie picks up `Secure`. The dashboard itself only ever speaks HTTP — terminate TLS at the proxy.
- **Bot token is redacted** in the UI (`123456…wxyz`). The full token still lives in `~/.openclaw/openclaw.json` — keep that file `chmod 600`.
- The Model/API-key form **writes API keys to `~/.openclaw/.env` in plaintext** (chmod 600) and **restarts the OpenClaw gateway**. Anyone who can reach the dashboard can change the model and rotate provider keys. Same trust assumptions as above — local-only by default.

## Troubleshooting

The service won't start:

```bash
systemctl --user status openclaw-dashboard
journalctl --user -u openclaw-dashboard -n 50
```

Service stops when you log out:

```bash
sudo loginctl enable-linger $USER
```

Dashboard says "OpenClaw CLI unreachable" (e.g. `UNREACHABLE ENOENT`):

The unit ships with `Environment=PATH=%h/.npm-global/bin:%h/.local/bin:/usr/local/bin:/usr/bin:/bin`, which covers the standard install locations. If you still see `ENOENT`:

- Confirm OpenClaw is installed for this user: `which openclaw` — should print something like `/home/ubuntu/.npm-global/bin/openclaw`. If it prints nothing, install OpenClaw first.
- If `which openclaw` points to a directory **not** in the default PATH above (e.g. `/opt/openclaw/bin`), extend the unit's PATH with `systemctl --user edit openclaw-dashboard` and add:

  ```ini
  [Service]
  Environment=PATH=/opt/openclaw/bin:/home/ubuntu/.npm-global/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin
  ```

  (Drop-ins replace the inherited `Environment=PATH=` value, so include the defaults you still need.)

- After editing, reload + restart: `systemctl --user daemon-reload && systemctl --user restart openclaw-dashboard`.
