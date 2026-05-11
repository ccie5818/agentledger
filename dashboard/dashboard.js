#!/usr/bin/env node
/*
 * OpenClaw + Telegram local status dashboard.
 *
 * Single-file Node.js server using built-ins only (http, fs, path, child_process).
 * No npm install required.
 *
 * Reads:
 *   ~/.openclaw/openclaw.json                         (channel + agent config)
 *   ~/.openclaw/.env                                  (API-key env var presence; values never read)
 *   ~/.openclaw/agents/main/sessions/sessions.json    (active sessions, best-effort)
 *   ~/.openclaw/dashboard/auth.json                   (username + scrypt password hash + salt)
 * Writes:
 *   ~/.openclaw/openclaw.json                         (model + telegram updates incl. botToken)
 *   ~/.openclaw/.env                                  (API key updates, chmod 600)
 *   ~/.openclaw/dashboard/auth.json                   (created with admin/admin on first boot, chmod 600)
 * Shells out to:
 *   openclaw --version
 *   openclaw pairing list telegram
 *   openclaw pairing approve telegram <CODE>
 *   systemctl --user restart openclaw-gateway         (when "restart gateway" is checked)
 *   systemctl is-active|is-enabled ssh                (read-only SSH status)
 *   sudo -n systemctl enable|disable --now ssh        (SSH toggle; needs passwordless sudo)
 *
 * Auth: cookie-based session (HttpOnly, SameSite=Lax). Default credentials on
 * first boot are admin/admin — a banner urges the user to change them. Sessions
 * are stored in-memory (24h TTL) and are lost on restart.
 *
 * Listens on 0.0.0.0:18790 by default (LAN-reachable). Override via env
 * DASHBOARD_PORT and DASHBOARD_HOST. Auth is required (cookie session), but
 * the default credentials are admin/admin and the model/key form is
 * destructive — change the password immediately or set DASHBOARD_HOST=127.0.0.1
 * to bind locally only.
 */

'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const os = require('os');
const crypto = require('crypto');

const PORT = parseInt(process.env.DASHBOARD_PORT || '18790', 10);
// Defaults to 0.0.0.0 (LAN-reachable). Auth is enforced via cookie session,
// but the default credentials are admin/admin and the model/key form is
// destructive — change the password immediately, or set
// DASHBOARD_HOST=127.0.0.1 to bind locally only.
const HOST = process.env.DASHBOARD_HOST || '0.0.0.0';
// Set DASHBOARD_TRUST_PROXY=1 when running behind a TLS-terminating reverse
// proxy so the session cookie is marked Secure.
const TRUST_PROXY = process.env.DASHBOARD_TRUST_PROXY === '1';

const OPENCLAW_HOME = path.join(os.homedir(), '.openclaw');
const CONFIG_PATH = path.join(OPENCLAW_HOME, 'openclaw.json');
const ENV_PATH = path.join(OPENCLAW_HOME, '.env');
const SESSIONS_PATH = path.join(OPENCLAW_HOME, 'agents', 'main', 'sessions', 'sessions.json');
const AUTH_PATH = path.join(OPENCLAW_HOME, 'dashboard', 'auth.json');

// Auth defaults — only used when AUTH_PATH does not yet exist. After first
// boot, the password lives in AUTH_PATH (scrypt-hashed). The dashboard shows
// a banner urging the user to change it until the default password is rotated.
const DEFAULT_USERNAME = 'admin';
const DEFAULT_PASSWORD = 'admin';

// In-memory session store: sessionId -> { username, expiresAt }.
const SESSIONS = new Map();
const SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const SESSION_COOKIE = 'oc_dash_sid';
// Hard cap so a misbehaving client can't grow the map without bound. When the
// cap is hit, we evict the oldest entries before inserting a new one.
const SESSION_MAX_ENTRIES = 1000;

// Per-IP login rate limit: ip -> { count, lockedUntil }. After 5 failed
// attempts the IP is locked out for 60s; the window resets on a successful
// login or after the lockout expires. Stored in memory (lost on restart) —
// fine for a single-host LAN dashboard.
const LOGIN_ATTEMPTS = new Map();
const LOGIN_MAX_FAILURES = 5;
const LOGIN_LOCKOUT_MS = 60 * 1000;

// Provider -> env var name. Used when saving an API key from the dashboard.
// Add more here if you need them; "custom" lets the user type the env var
// name directly in the form.
const PROVIDER_ENV = {
    anthropic:  'ANTHROPIC_API_KEY',
    openai:     'OPENAI_API_KEY',
    google:     'GOOGLE_API_KEY',
    xai:        'XAI_API_KEY',
    deepseek:   'DEEPSEEK_API_KEY',
    groq:       'GROQ_API_KEY',
    mistral:    'MISTRAL_API_KEY',
    openrouter: 'OPENROUTER_API_KEY',
};

// Suggested model strings per provider (placeholder when free-typing).
const PROVIDER_MODEL_HINT = {
    anthropic:  'claude-opus-4-6',
    openai:     'gpt-4o',
    google:     'gemini-1.5-pro',
    xai:        'grok-2',
    deepseek:   'deepseek-chat',
    groq:       'llama-3.3-70b-versatile',
    mistral:    'mistral-large-latest',
    openrouter: 'anthropic/claude-opus-4-6',
};

// Common models per provider for the dropdown. Not exhaustive — pick "Other…"
// in the UI to type any other model id (the provider must support it).
// Update these lists when new models ship.
const PROVIDER_MODELS = {
    anthropic: [
        'claude-opus-4-7',
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-haiku-4-5',
    ],
    openai: [
        'gpt-5',
        'gpt-5-mini',
        'gpt-4o',
        'gpt-4o-mini',
        'o1',
        'o1-mini',
    ],
    google: [
        'gemini-2.0-flash',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
    ],
    xai: [
        'grok-2',
        'grok-2-vision',
        'grok-beta',
    ],
    deepseek: [
        'deepseek-chat',
        'deepseek-reasoner',
    ],
    groq: [
        'llama-3.3-70b-versatile',
        'llama-3.1-70b-versatile',
        'llama-3.1-8b-instant',
        'mixtral-8x7b-32768',
    ],
    mistral: [
        'mistral-large-latest',
        'mistral-small-latest',
        'codestral-latest',
    ],
    openrouter: [
        'anthropic/claude-opus-4-6',
        'anthropic/claude-sonnet-4-6',
        'openai/gpt-4o',
        'openai/gpt-5',
        'google/gemini-pro-1.5',
        'meta-llama/llama-3.3-70b-instruct',
    ],
};

// ---------------------------------------------------------------------------
// helpers

function readJsonSafe(p) {
    try {
        const raw = fs.readFileSync(p, 'utf8');
        return JSON.parse(raw);
    } catch (e) {
        return null;
    }
}

function runOpenClaw(args, timeoutMs = 5000) {
    return new Promise((resolve) => {
        execFile('openclaw', args, { timeout: timeoutMs }, (err, stdout, stderr) => {
            resolve({
                ok: !err,
                code: err && err.code,
                stdout: (stdout || '').trim(),
                stderr: (stderr || '').trim(),
            });
        });
    });
}

function redactToken(token) {
    if (!token || typeof token !== 'string') return null;
    if (token.length < 12) return '***';
    return token.slice(0, 6) + '…' + token.slice(-4);
}

function fmtAgo(iso) {
    if (!iso) return '?';
    const t = new Date(iso).getTime();
    if (!isFinite(t)) return iso;
    const s = Math.max(0, Math.floor((Date.now() - t) / 1000));
    if (s < 60) return s + 's ago';
    if (s < 3600) return Math.floor(s / 60) + 'm ago';
    if (s < 86400) return Math.floor(s / 3600) + 'h ago';
    return Math.floor(s / 86400) + 'd ago';
}

function htmlEscape(s) {
    return String(s == null ? '' : s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------
// auth: scrypt password hashing + cookie session store

function hashPassword(password, salt) {
    salt = salt || crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(String(password), salt, 64).toString('hex');
    return { hash, salt };
}

function verifyPassword(password, storedHash, storedSalt) {
    try {
        const computed = crypto.scryptSync(String(password), storedSalt, 64);
        const stored = Buffer.from(storedHash, 'hex');
        if (computed.length !== stored.length) return false;
        return crypto.timingSafeEqual(computed, stored);
    } catch (_) {
        return false;
    }
}

function loadAuth() {
    let data = readJsonSafe(AUTH_PATH);
    if (!data || !data.passwordHash || !data.salt) {
        // First-boot init: write admin/admin (hashed) and set the warning flag.
        const seed = hashPassword(DEFAULT_PASSWORD);
        data = {
            username: DEFAULT_USERNAME,
            passwordHash: seed.hash,
            salt: seed.salt,
            isDefaultPassword: true,
            createdAt: new Date().toISOString(),
        };
        saveAuth(data);
        console.warn('!!  AUTH: created ' + AUTH_PATH + ' with default credentials admin/admin — change immediately.');
    }
    return data;
}

function saveAuth(data) {
    fs.mkdirSync(path.dirname(AUTH_PATH), { recursive: true });
    fs.writeFileSync(AUTH_PATH, JSON.stringify(data, null, 2));
    try { fs.chmodSync(AUTH_PATH, 0o600); } catch (_) {}
}

function createSession(username) {
    // Enforce the size cap before inserting. Map iteration order is insertion
    // order, so the first entries are the oldest.
    while (SESSIONS.size >= SESSION_MAX_ENTRIES) {
        const oldest = SESSIONS.keys().next().value;
        if (oldest === undefined) break;
        SESSIONS.delete(oldest);
    }
    const sid = crypto.randomBytes(32).toString('hex');
    SESSIONS.set(sid, { username, expiresAt: Date.now() + SESSION_TTL_MS });
    return sid;
}

// Look up an IP's lockout state. Returns { locked, retryAfterSec } where
// locked is true when the IP is currently blocked from logging in.
function checkLoginLockout(ip) {
    const entry = LOGIN_ATTEMPTS.get(ip);
    if (!entry || !entry.lockedUntil) return { locked: false };
    const remaining = entry.lockedUntil - Date.now();
    if (remaining <= 0) {
        // Lockout expired — clear it so the user gets a fresh budget.
        LOGIN_ATTEMPTS.delete(ip);
        return { locked: false };
    }
    return { locked: true, retryAfterSec: Math.ceil(remaining / 1000) };
}

function recordLoginFailure(ip) {
    const entry = LOGIN_ATTEMPTS.get(ip) || { count: 0, lockedUntil: 0 };
    entry.count += 1;
    if (entry.count >= LOGIN_MAX_FAILURES) {
        entry.lockedUntil = Date.now() + LOGIN_LOCKOUT_MS;
    }
    LOGIN_ATTEMPTS.set(ip, entry);
}

function clearLoginFailures(ip) {
    LOGIN_ATTEMPTS.delete(ip);
}

// Best-effort client IP — req.socket.remoteAddress is fine for our LAN/local
// use case. If users front this with a reverse proxy they should bind to
// 127.0.0.1 anyway; we deliberately don't trust X-Forwarded-For here so a
// spoofed header can't dodge the rate limit.
function clientIp(req) {
    return (req.socket && req.socket.remoteAddress) || 'unknown';
}

function destroySession(sid) {
    if (sid) SESSIONS.delete(sid);
}

function checkSession(sid) {
    if (!sid) return null;
    const s = SESSIONS.get(sid);
    if (!s) return null;
    const now = Date.now();
    if (now > s.expiresAt) { SESSIONS.delete(sid); return null; }
    // Sliding expiry: any authenticated touch extends the TTL so an active
    // session won't get kicked mid-use. We deliberately don't re-set the
    // cookie on every request (the existing cookie's Max-Age is what the
    // browser remembers); the server-side store is the source of truth.
    s.expiresAt = now + SESSION_TTL_MS;
    return s;
}

function parseCookies(req) {
    const out = {};
    const raw = req.headers && req.headers.cookie;
    if (!raw) return out;
    for (const part of String(raw).split(/;\s*/)) {
        const eq = part.indexOf('=');
        if (eq < 1) continue;
        out[part.slice(0, eq).trim()] = decodeURIComponent(part.slice(eq + 1).trim());
    }
    return out;
}

function setSessionCookie(res, sid, maxAgeSec) {
    const attrs = [
        `${SESSION_COOKIE}=${sid}`,
        'Path=/',
        'HttpOnly',
        'SameSite=Lax',
    ];
    // Mark Secure when we know we're behind TLS termination. We avoid setting
    // it by default because the dashboard's primary deployment is plain HTTP
    // on a LAN, and a Secure cookie there would silently break login.
    if (TRUST_PROXY) attrs.push('Secure');
    if (typeof maxAgeSec === 'number') attrs.push(`Max-Age=${maxAgeSec}`);
    res.setHeader('Set-Cookie', attrs.join('; '));
}

// Periodically prune expired sessions and stale lockouts so neither map
// grows unbounded.
setInterval(() => {
    const now = Date.now();
    for (const [k, v] of SESSIONS) if (now > v.expiresAt) SESSIONS.delete(k);
    for (const [k, v] of LOGIN_ATTEMPTS) {
        // Drop entries whose lockout has expired AND that haven't been touched
        // recently — keep ones still inside the failure window so the count
        // doesn't reset between sweeps.
        if (v.lockedUntil && now > v.lockedUntil) LOGIN_ATTEMPTS.delete(k);
    }
}, 60 * 1000).unref();

// Update or append KEY=value in a dotenv-style file. Quotes the value if it
// contains whitespace or special chars. Creates the file (and dirs) if missing
// and chmod 600's it because it now contains secrets.
function upsertEnvVar(filePath, key, value) {
    if (!/^[A-Z_][A-Z0-9_]*$/i.test(key)) throw new Error('invalid env var name');
    let text = '';
    try { text = fs.readFileSync(filePath, 'utf8'); } catch (_) { /* file may not exist */ }
    const lines = text.split(/\r?\n/);
    const needsQuote = /[\s"'#$`\\]/.test(value);
    const escaped = needsQuote
        ? '"' + String(value).replace(/(["\\])/g, '\\$1') + '"'
        : String(value);
    const newLine = key + '=' + escaped;
    let replaced = false;
    const out = lines.map((line) => {
        const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/);
        if (m && m[1] === key) {
            replaced = true;
            return newLine;
        }
        return line;
    });
    if (!replaced) {
        // Trim trailing blank line then append.
        while (out.length && out[out.length - 1] === '') out.pop();
        out.push(newLine);
        out.push('');
    }
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, out.join('\n'));
    try { fs.chmodSync(filePath, 0o600); } catch (_) { /* not fatal on platforms without chmod */ }
}

// Read SSH status (active + enabled-on-boot). These commands don't require
// sudo and they exit non-zero when the answer is "no", so we treat any
// stdout content as the answer regardless of exit code.
function getSshStatus() {
    function run(args) {
        return new Promise((resolve) => {
            execFile('systemctl', args, { timeout: 5000 }, (err, stdout) => {
                resolve((stdout || '').trim() || (err && err.code != null ? 'unknown' : ''));
            });
        });
    }
    return Promise.all([
        run(['is-active', 'ssh']),
        run(['is-enabled', 'ssh']),
    ]).then(([active, enabled]) => ({ active, enabled }));
}

// Enable+start or disable+stop the system SSH service. Requires passwordless
// sudo for the specific systemctl invocations. Returns a hint with the
// sudoers config when sudo asks for a password.
function setSsh(action) {
    if (action !== 'enable' && action !== 'disable') {
        return Promise.resolve({ ok: false, error: 'invalid action' });
    }
    const sysArgs = action === 'enable'
        ? ['-n', 'systemctl', 'enable', '--now', 'ssh']
        : ['-n', 'systemctl', 'disable', '--now', 'ssh'];
    return new Promise((resolve) => {
        execFile('sudo', sysArgs, { timeout: 10000 }, async (err, stdout, stderr) => {
            if (!err) {
                // Give systemd a beat to actually flip the state, then re-read
                // it so the response carries the post-action truth (the UI
                // uses this to update the badges immediately).
                await new Promise((r) => setTimeout(r, 400));
                const status = await getSshStatus();
                resolve({ ok: true, action, status });
                return;
            }
            const msg = (stderr || stdout || err.message || '').trim() || ('exit code ' + err.code);
            const needsPasswordless = /password is required|sudo: a password|^a password is required/i.test(msg);
            const user = process.env.USER || process.env.LOGNAME || 'YOU';
            resolve({
                ok: false,
                error: msg,
                hint: needsPasswordless
                    ? `Passwordless sudo for SSH control isn't configured. Run on the Pi:\n` +
                      `  sudo visudo -f /etc/sudoers.d/openclaw-dashboard\n` +
                      `Add the line:\n` +
                      `  ${user} ALL=(root) NOPASSWD: /bin/systemctl enable --now ssh, /bin/systemctl disable --now ssh\n` +
                      `Save (Ctrl+X, Y, Enter), then retry from the dashboard.`
                    : null,
            });
        });
    });
}

// Try to restart the OpenClaw gateway via systemd --user. Returns details for
// the API response so the user knows what happened.
function restartGateway() {
    return new Promise((resolve) => {
        execFile('systemctl', ['--user', 'restart', 'openclaw-gateway'], { timeout: 10000 }, (err, stdout, stderr) => {
            if (!err) {
                resolve({ ok: true, method: 'systemctl --user restart openclaw-gateway' });
                return;
            }
            // Fall back: tell the caller how to restart manually. We don't try
            // to kill+respawn the process ourselves — too easy to leave the
            // user in a half-running state.
            resolve({
                ok: false,
                method: 'manual',
                error: (stderr || err.message || '').trim() || 'systemctl restart failed',
                hint: 'Restart the gateway manually so the new model/key take effect: `systemctl --user restart openclaw-gateway` (or stop the running gateway and run `openclaw gateway` again).',
            });
        });
    });
}

// ---------------------------------------------------------------------------
// status gathering

async function gatherStatus() {
    const cfg = readJsonSafe(CONFIG_PATH) || {};
    const sessionsRaw = readJsonSafe(SESSIONS_PATH);

    // Current model: agents.defaults.model.primary, e.g. "anthropic/claude-opus-4-6".
    const primaryRef = cfg.agents && cfg.agents.defaults && cfg.agents.defaults.model
        && cfg.agents.defaults.model.primary;
    let modelProvider = '', modelName = '';
    if (primaryRef && typeof primaryRef === 'string') {
        const slash = primaryRef.indexOf('/');
        if (slash > 0) {
            modelProvider = primaryRef.slice(0, slash);
            modelName = primaryRef.slice(slash + 1);
        } else {
            modelName = primaryRef;
        }
    }

    // Which provider keys are present in ~/.openclaw/.env (presence only —
    // never read values). We deliberately filter to env vars that look like
    // API keys so unrelated entries (e.g. PATH overrides, debug flags) don't
    // show up under the "Provider keys" label.
    //
    // The custom env var that was saved alongside a custom model is read from
    // openclaw.json and allowlisted here so it shows up even if its name
    // doesn't match the usual `_API_KEY` suffix.
    const customEnvVarName = (cfg.agents && cfg.agents.defaults && cfg.agents.defaults.model
        && typeof cfg.agents.defaults.model.customEnvVar === 'string')
        ? cfg.agents.defaults.model.customEnvVar : null;
    const knownProviderEnvVars = new Set(Object.values(PROVIDER_ENV));
    const envKeysPresent = {};
    try {
        const envText = fs.readFileSync(ENV_PATH, 'utf8');
        for (const line of envText.split(/\r?\n/)) {
            const m = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/);
            if (!m) continue;
            const name = m[1];
            if (knownProviderEnvVars.has(name) || /_API_KEY$/.test(name) || name === customEnvVarName) {
                envKeysPresent[name] = true;
            }
        }
    } catch (_) { /* file may not exist */ }

    // Telegram block (be defensive — config shape can vary).
    const tg = (cfg.channels && cfg.channels.telegram) || {};
    const telegram = {
        configured: Boolean(tg.botToken || tg.tokenFile || tg.accounts),
        enabled: tg.enabled === true,
        botToken: redactToken(tg.botToken),
        dmPolicy: tg.dmPolicy || (tg.botToken ? 'pairing' : null),
        groupPolicy: tg.groupPolicy || null,
        allowFromCount: Array.isArray(tg.allowFrom) ? tg.allowFrom.length : 0,
        groupCount: tg.groups ? Object.keys(tg.groups).length : 0,
        accounts: tg.accounts ? Object.keys(tg.accounts) : [],
    };

    // Sessions — shape unknown; show whatever shape we find as a count + list.
    const sessions = [];
    if (sessionsRaw && typeof sessionsRaw === 'object') {
        const entries = Array.isArray(sessionsRaw)
            ? sessionsRaw
            : Object.entries(sessionsRaw).map(([k, v]) => ({ key: k, ...((v && typeof v === 'object') ? v : { value: v }) }));
        for (const e of entries.slice(0, 50)) {
            sessions.push({
                key: e.key || e.id || e.sessionKey || JSON.stringify(e).slice(0, 80),
                model: e.model || e.modelId || null,
                updatedAt: e.updatedAt || e.lastSeen || e.lastActivity || null,
                tokens: e.tokens || e.tokenCount || null,
            });
        }
    }

    // Live calls — versioned + pairings (best effort, may fail if openclaw not on PATH).
    const [version, pairings, ssh] = await Promise.all([
        runOpenClaw(['--version'], 3000),
        runOpenClaw(['pairing', 'list', 'telegram'], 5000),
        getSshStatus(),
    ]);

    const auth = loadAuth();
    return {
        host: os.hostname(),
        time: new Date().toISOString(),
        config: {
            path: CONFIG_PATH,
            present: Boolean(readJsonSafe(CONFIG_PATH)),
            envPath: ENV_PATH,
        },
        auth: {
            username: auth.username,
            isDefaultPassword: !!auth.isDefaultPassword,
        },
        openclaw: {
            version: version.ok ? version.stdout : null,
            error: version.ok ? null : (version.stderr || version.code || 'not on PATH'),
        },
        model: {
            primary: primaryRef || null,
            provider: modelProvider,
            name: modelName,
            envKeysPresent,
            customEnvVar: customEnvVarName,
        },
        telegram,
        sessions: {
            path: SESSIONS_PATH,
            count: sessions.length,
            items: sessions,
        },
        pairings: {
            ok: pairings.ok,
            output: pairings.ok ? pairings.stdout : null,
            // Some openclaw subcommands write the human-readable error to
            // stdout instead of stderr, so check both before falling back to
            // the bare exit code.
            error: pairings.ok ? null : (pairings.stderr || pairings.stdout || ('exit code ' + (pairings.code != null ? pairings.code : '?'))),
        },
        ssh: {
            active: ssh.active,
            enabled: ssh.enabled,
        },
    };
}

// ---------------------------------------------------------------------------
// HTML rendering

function renderLoginPage(opts) {
    opts = opts || {};
    const errorBlock = opts.error
        ? `<div class="err-banner">${htmlEscape(opts.error)}</div>` : '';
    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Login · AgentLedger Dashboard</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; background:#0e0c0d; color:#e6e1de; margin:0; min-height:100vh; display:grid; place-items:center; }
  .box { background:#1a1718; border:1px solid #2c2728; border-radius:8px; padding:32px; min-width:320px; }
  .title-box { background:transparent; border:1px solid #2c2728; border-radius:4px; padding:10px; text-align:center; color:#FF8A6B; font-size:16px; font-weight:600; margin:0 0 24px 0; box-sizing:border-box; }
  .sub { color:#9a8e85; font-size:12px; margin-bottom:24px; }
  form { display:flex; flex-direction:column; gap:12px; }
  input { background:#0e0c0d; color:#e6e1de; border:1px solid #2c2728; border-radius:4px; padding:10px; font-family: inherit; font-size:13px; box-sizing:border-box; width:100%; }
  button { background:#FF5A36; color:#fff; border:0; border-radius:4px; padding:10px; font-weight:600; cursor:pointer; font-family: inherit; font-size:13px; box-sizing:border-box; width:100%; }
  button:hover { background:#FF8A6B; }
  .err-banner { background:#3a0f1a; color:#e27e94; border:1px solid #5a1f2a; padding:8px 12px; border-radius:4px; margin-bottom:12px; font-size:12px; }
  .hint { color:#9a8e85; font-size:11px; text-align:center; margin-top:8px; }
</style>
</head>
<body>
  <div class="box">
    <div class="title-box">AgentLedger Dashboard</div>
    ${errorBlock}
    <form method="POST" action="/api/auth/login">
      <input type="text" name="username" placeholder="Username" autofocus required autocomplete="username">
      <input type="password" name="password" placeholder="Password" required autocomplete="current-password">
      <button type="submit">Login</button>
    </form>
    <div class="hint">Default credentials are <code>admin</code>/<code>admin</code> on first boot. Change them immediately.</div>
  </div>
</body>
</html>`;
}

function renderPage(status) {
    const tg = status.telegram;
    const tgBadge = tg.enabled
        ? '<span class="badge ok">ENABLED</span>'
        : (tg.configured ? '<span class="badge warn">CONFIGURED, NOT ENABLED</span>' : '<span class="badge err">NOT CONFIGURED</span>');

    // Provider <option>s for the model form.
    const providerOptions = Object.keys(PROVIDER_ENV).map((p) => {
        const sel = (status.model.provider === p) ? ' selected' : '';
        const keyPresent = status.model.envKeysPresent[PROVIDER_ENV[p]] ? ' ✓' : '';
        return `<option value="${htmlEscape(p)}"${sel}>${htmlEscape(p)}${keyPresent}</option>`;
    }).join('') + `<option value="custom"${status.model.provider && !PROVIDER_ENV[status.model.provider] ? ' selected' : ''}>custom…</option>`;

    // For client-side hint switching + dropdown population.
    const providerHints = JSON.stringify(PROVIDER_MODEL_HINT);
    const providerEnv = JSON.stringify(PROVIDER_ENV);
    const providerModels = JSON.stringify(PROVIDER_MODELS);
    const currentModel = JSON.stringify(status.model.name || '');
    const currentProvider = JSON.stringify(status.model.provider || '');
    // Full saved model ref (e.g. "ollama/qwen3.5:latest") — used to pre-fill
    // the "Other…" text input when the saved provider is custom so the user
    // sees their model on reload instead of an empty field.
    const currentModelFull = JSON.stringify(status.model.primary || '');

    return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>AgentLedger Dashboard</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; background:#0e0c0d; color:#e6e1de; margin:0; padding:24px; font-size:13px; }
  h1 { margin:0 0 4px 0; font-size:20px; color:#FF8A6B; }
  .sub { color:#9a8e85; font-size:12px; margin-bottom:24px; }
  .grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap:16px; }
  .card { background:#1a1718; border:1px solid #2c2728; border-radius:8px; padding:16px; font-size:13px; }
  .card h2 { margin:0 0 12px 0; font-size:13px; color:#FF8A6B; text-transform:uppercase; letter-spacing:0.05em; }
  dl { margin:0; display:grid; grid-template-columns: 140px 1fr; gap:6px 12px; font-size:13px; }
  dt { color:#9a8e85; }
  dd { margin:0; word-break: break-all; }
  .badge { display:inline-block; padding:2px 8px; border-radius:4px; font-size:13px; font-weight:600; letter-spacing:0.05em; }
  .badge.ok { background:#0f3a1f; color:#7ee29a; }
  .badge.warn { background:#3a2f0f; color:#e2c97e; }
  .badge.err { background:#3a0f1a; color:#e27e94; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th, td { text-align:left; padding:6px 8px; border-bottom:1px solid #2c2728; }
  th { color:#9a8e85; font-weight:normal; text-transform:uppercase; letter-spacing:0.05em; font-size:13px; }
  pre { white-space: pre-wrap; word-break: break-all; background:#0e0c0d; border:1px solid #2c2728; border-radius:4px; padding:10px; font-size:13px; max-height:240px; overflow:auto; margin:0; }
  form { display:flex; gap:8px; flex-direction:column; }
  input, textarea, select { background:#0e0c0d; color:#e6e1de; border:1px solid #2c2728; border-radius:4px; padding:8px; font-family: inherit; font-size:13px; }
  textarea { min-height:60px; resize:vertical; }
  button { background:#FF5A36; color:#fff; border:0; border-radius:4px; padding:8px 16px; font-weight:600; cursor:pointer; font-family: inherit; font-size:13px; }
  button:hover { background:#FF8A6B; }
  .row { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
  .muted { color:#9a8e85; font-size:13px; }
  a { color:#FF8A6B; text-decoration:none; }
  a:hover { text-decoration:underline; }
</style>
</head>
<body>
  <div style="display:grid; grid-template-columns:1fr auto 1fr; align-items:baseline; gap:24px;">
    <div></div>
    <h1 style="margin:0; text-align:center;">AgentLedger Dashboard</h1>
    <div style="font-size:13px; font-weight:600; color:#FF8A6B; text-align:right;">
      signed in as <strong style="color:#e6e1de; font-weight:inherit;">${htmlEscape(status.auth.username)}</strong> · <a href="/api/auth/logout" id="logoutLink" style="color:#FF8A6B;">Logout</a>
    </div>
  </div>
  <div class="sub" style="text-align:center;">${htmlEscape(status.host)} · refreshed ${htmlEscape(new Date(status.time).toLocaleString())} (auto-refresh every 5s, paused while typing)</div>

  ${status.auth.isDefaultPassword ? `
  <div style="background:#3a0f1a; border:1px solid #5a1f2a; color:#e27e94; padding:10px 14px; border-radius:6px; margin-bottom:16px; font-size:13px;">
    ⚠ <strong>Default password in use.</strong> Change it now in the "Account" card below — anyone on this network can log in with <code>admin</code>/<code>admin</code>.
  </div>` : ''}

  <div class="grid">

    <div class="card">
      <h2>OpenClaw</h2>
      <dl>
        <dt>Version</dt><dd>${htmlEscape(status.openclaw.version || '—')}</dd>
        <dt>CLI</dt><dd>${status.openclaw.error ? '<span class="badge err">UNREACHABLE</span> ' + htmlEscape(status.openclaw.error) : '<span class="badge ok">REACHABLE</span>'}</dd>
        <dt>Config file</dt><dd>${htmlEscape(status.config.path)}</dd>
        <dt>Config status</dt><dd>${status.config.present ? '<span class="badge ok">PRESENT</span>' : '<span class="badge err">MISSING</span>'}</dd>
      </dl>
    </div>

    <div class="card">
      <h2>Model & API key</h2>
      <dl>
        <dt>Current model</dt><dd>${htmlEscape(status.model.primary || '— (not set)')}</dd>
        <dt>Provider keys</dt><dd>${
            Object.keys(status.model.envKeysPresent).length
                ? Object.keys(status.model.envKeysPresent).map((k) => {
                      const isCustom = status.model.customEnvVar && k === status.model.customEnvVar;
                      const label = isCustom ? htmlEscape(k) + ' (custom)' : htmlEscape(k);
                      return '<span class="badge ok" style="margin-right:4px" title="' + (isCustom ? 'custom env var for the current model' : 'recognized provider key') + '">' + label + '</span>';
                  }).join('')
                : '<span class="muted">(none in ~/.openclaw/.env)</span>'
        }</dd>
      </dl>
      <form id="modelForm" style="margin-top:12px">
        <div class="row">
          <select name="provider" id="modelProvider" style="flex:1; min-width:140px;">
            ${providerOptions}
          </select>
          <input type="text" name="customEnvVar" id="customEnvVar" placeholder="CUSTOM_API_KEY" value="${htmlEscape(status.model.customEnvVar || '')}" style="flex:1; display:none;">
        </div>
        <select name="modelSelect" id="modelSelect"></select>
        <input type="text" name="modelCustom" id="modelCustom" placeholder="${htmlEscape(PROVIDER_MODEL_HINT[status.model.provider] || 'model-id')}" style="display:none;">
        <input type="password" name="apiKey" placeholder="API key (leave blank to keep existing)">
        <label class="muted" style="display:flex; gap:6px; align-items:center;">
          <input type="checkbox" name="restart" id="restartGw" checked>
          restart gateway after saving
        </label>
        <div class="row">
          <button type="submit">Save</button>
          <span class="muted" id="modelResult"></span>
        </div>
      </form>
      <script>
        (function () {
          const HINTS  = ${providerHints};
          const ENV    = ${providerEnv};
          const MODELS = ${providerModels};
          const CURRENT_MODEL = ${currentModel};
          const CURRENT_PROVIDER = ${currentProvider};
          const CURRENT_MODEL_FULL = ${currentModelFull};
          const provSel = document.getElementById('modelProvider');
          const cust    = document.getElementById('customEnvVar');
          const mdlSel  = document.getElementById('modelSelect');
          const mdlCust = document.getElementById('modelCustom');

          function populateModels() {
            const p = provSel.value;
            mdlSel.innerHTML = '';
            const list = MODELS[p] || [];
            const sameProvider = (p === CURRENT_PROVIDER);

            // Only prepend the saved model as "(current)" when this provider
            // owns it AND the canonical list doesn't already include it.
            // For other providers, keep the dropdown clean — show only the
            // models that actually belong to the selected provider.
            if (sameProvider && CURRENT_MODEL && !list.includes(CURRENT_MODEL) && p !== 'custom') {
              const opt = document.createElement('option');
              opt.value = CURRENT_MODEL;
              opt.textContent = CURRENT_MODEL + ' (current)';
              opt.selected = true;
              mdlSel.appendChild(opt);
            }
            for (const m of list) {
              const opt = document.createElement('option');
              opt.value = m;
              opt.textContent = m;
              if (sameProvider && m === CURRENT_MODEL) opt.selected = true;
              mdlSel.appendChild(opt);
            }
            // Always include an "Other…" escape hatch for typing a model id
            // that isn't in the curated list.
            const other = document.createElement('option');
            other.value = '__other__';
            other.textContent = 'Other…';
            mdlSel.appendChild(other);

            // For custom provider, force "Other…" + show the text input.
            // Pre-fill it with the full saved ref (e.g. "ollama/qwen3.5:latest")
            // so a reload doesn't silently lose what's already configured.
            if (p === 'custom') {
              other.selected = true;
              if (CURRENT_MODEL_FULL) mdlCust.value = CURRENT_MODEL_FULL;
            }
            syncCustomModel();
          }

          function syncCustomModel() {
            const isOther = mdlSel.value === '__other__';
            mdlCust.style.display = isOther ? '' : 'none';
            mdlCust.required = isOther;
            mdlCust.placeholder = HINTS[provSel.value] || 'model-id';
          }

          function syncCustomEnvVar() {
            const isCustom = provSel.value === 'custom';
            cust.style.display = isCustom ? '' : 'none';
            cust.required = isCustom;
          }

          provSel.addEventListener('change', () => { populateModels(); syncCustomEnvVar(); });
          mdlSel.addEventListener('change', syncCustomModel);
          populateModels();
          syncCustomEnvVar();

          document.getElementById('modelForm').addEventListener('submit', async (e) => {
            e.preventDefault();
            const f = e.target;
            const out = document.getElementById('modelResult');
            // Resolve the actual model id from dropdown OR the "Other…" text input.
            const resolvedModel = (mdlSel.value === '__other__')
              ? mdlCust.value.trim()
              : mdlSel.value;
            if (!resolvedModel) {
              out.textContent = 'error: pick or type a model';
              return;
            }
            const payload = {
              provider:      f.provider.value,
              model:         resolvedModel,
              apiKey:        f.apiKey.value || null,
              customEnvVar:  f.customEnvVar.value || null,
              restart:       f.restart.checked,
            };
            out.textContent = 'saving…';
            try {
              const r = await fetch('/api/model/update', { method: 'POST', headers: {'content-type':'application/json'}, body: JSON.stringify(payload) });
              const j = await r.json();
              if (r.ok) {
                out.textContent = 'saved ✓ ' + (j.restart && j.restart.ok ? '(gateway restarted)' : (j.restart && !j.restart.ok ? '(restart failed — see hint)' : ''));
                f.apiKey.value = '';
                if (j.restart && j.restart.hint) alert(j.restart.hint);
              } else {
                out.textContent = 'error: ' + (j.error || r.status);
              }
            } catch (err) {
              out.textContent = 'network error: ' + err.message;
            }
          });
        })();
      </script>
    </div>

    <div class="card">
      <h2>Telegram</h2>
      <dl>
        <dt>Status</dt><dd>${tgBadge}</dd>
        <dt>Bot token</dt><dd>${htmlEscape(tg.botToken || '—')}</dd>
        <dt>DM policy</dt><dd>${htmlEscape(tg.dmPolicy || '—')}</dd>
        <dt>Group policy</dt><dd>${htmlEscape(tg.groupPolicy || '—')}</dd>
        <dt>allowFrom</dt><dd>${tg.allowFromCount} entries</dd>
        <dt>Configured groups</dt><dd>${tg.groupCount}</dd>
        <dt>Accounts</dt><dd>${tg.accounts.length ? htmlEscape(tg.accounts.join(', ')) : 'default'}</dd>
      </dl>
    </div>

    <div class="card">
      <h2>Update Telegram Pairing Code</h2>
      ${(() => {
          // Successful empty output, OR an exit-code-only failure (which
          // openclaw uses to mean "nothing to list" once you're already
          // authorized) both render as "no pending pairings".
          const errorIsJustExitCode = status.pairings.error && /^exit code/i.test(status.pairings.error);
          const hasOutput = status.pairings.ok && status.pairings.output;
          if (hasOutput) {
              return `<pre>${htmlEscape(status.pairings.output)}</pre>`;
          }
          if (status.pairings.ok || errorIsJustExitCode) {
              return `<div class="muted">No pending pairings.</div>`;
          }
          return `<pre class="muted">Could not fetch pairings: ${htmlEscape(status.pairings.error)}</pre>`;
      })()}
      <div class="muted" style="margin-top:8px">
        New pairings appear here when someone sends <code>/start</code> to your bot. Paste the code and click Approve, or run manually: <code>openclaw pairing approve telegram &lt;CODE&gt;</code>
      </div>

      <form id="pairForm" style="margin-top:8px;">
        <div class="row" style="gap:8px;">
          <input type="text" name="code" placeholder="Pairing code (e.g. EXX4WA2L)" required minlength="4" maxlength="32" autocapitalize="characters" style="flex:1; min-width:160px;">
          <button type="submit">Approve</button>
        </div>
        <span class="muted" id="pairResult"></span>
      </form>
      <script>
        document.getElementById('pairForm').addEventListener('submit', async (e) => {
          e.preventDefault();
          const f = e.target;
          const out = document.getElementById('pairResult');
          const code = (f.code.value || '').trim();
          if (!code) { out.textContent = 'enter a code'; return; }
          out.textContent = 'approving…';
          try {
            const r = await fetch('/api/telegram/pairing/approve', {
              method: 'POST',
              headers: {'content-type': 'application/json'},
              body: JSON.stringify({ code })
            });
            const j = await r.json();
            if (r.ok) {
              out.textContent = 'approved ✓';
              f.code.value = '';
              // Reload so the pairings <pre> above refreshes (the approved
              // code should disappear from the pending list).
              setTimeout(() => location.reload(), 1000);
            } else {
              out.textContent = 'error: ' + (j.error || r.status);
            }
          } catch (err) {
            out.textContent = 'network error: ' + err.message;
          }
        });
      </script>
    </div>

    <div class="card">
      <h2>Update Telegram Bot Token</h2>
      <div class="muted" style="margin-bottom:8px;">Current: ${htmlEscape(status.telegram.botToken || '— (not set)')}</div>
      <form id="tokenForm">
        <input type="password" name="botToken" placeholder="Paste new bot token from @BotFather" required minlength="20">
        <label class="muted" style="display:flex; gap:6px; align-items:center;">
          <input type="checkbox" name="restart" id="tokenRestart" checked>
          restart gateway after saving
        </label>
        <div class="row">
          <button type="submit">Save</button>
          <span class="muted" id="tokenResult"></span>
        </div>
      </form>
      <script>
        document.getElementById('tokenForm').addEventListener('submit', async (e) => {
          e.preventDefault();
          const f = e.target;
          const out = document.getElementById('tokenResult');
          out.textContent = 'saving…';
          try {
            const r = await fetch('/api/telegram/token', {
              method: 'POST',
              headers: {'content-type': 'application/json'},
              body: JSON.stringify({ botToken: f.botToken.value, restart: f.restart.checked })
            });
            const j = await r.json();
            if (r.ok) {
              const suffix = j.restart && j.restart.ok ? '(gateway restarted)' : (j.restart && !j.restart.ok ? '(restart failed — see hint)' : '');
              out.textContent = 'saved ✓ ' + suffix;
              f.botToken.value = '';
              if (j.restart && j.restart.hint) alert(j.restart.hint);
              // Reload after a brief delay so the user sees the success message,
              // then the "Current: ..." line above the form picks up the new
              // redacted token from the freshly-read config.
              setTimeout(() => location.reload(), 1200);
            } else {
              out.textContent = 'error: ' + (j.error || r.status);
            }
          } catch (err) {
            out.textContent = 'network error: ' + err.message;
          }
        });
      </script>
    </div>

    <div class="card">
      <h2>Remote Support</h2>
      <dl>
        <dt>Service</dt><dd id="sshActiveCell">${status.ssh.active === 'active' ? '<span class="badge ok">RUNNING</span>' : '<span class="badge err">' + htmlEscape((status.ssh.active || 'unknown').toUpperCase()) + '</span>'}</dd>
        <dt>On boot</dt><dd id="sshEnabledCell">${status.ssh.enabled === 'enabled' ? '<span class="badge ok">ENABLED</span>' : '<span class="badge err">' + htmlEscape((status.ssh.enabled || 'unknown').toUpperCase()) + '</span>'}</dd>
      </dl>
      <div class="row" style="margin-top:12px;">
        <button type="button" id="sshEnableBtn">Enable</button>
        <button type="button" id="sshDisableBtn" style="background:#7a2030;">Disable</button>
        <span class="muted" id="sshResult"></span>
      </div>
      <div class="muted" style="margin-top:8px;">
        Disabling remote support closes the door to remote access. If remote support is connected right now, the current session will stay open but won't be able to reconnect after disconnecting.
      </div>
      <script>
        async function sshAction(action) {
          if (action === 'disable' && !confirm('Disable SSH? You will not be able to reconnect via SSH after your current session ends.')) return;
          const out = document.getElementById('sshResult');
          out.textContent = action === 'enable' ? 'enabling…' : 'disabling…';
          try {
            const r = await fetch('/api/ssh/toggle', {
              method: 'POST',
              headers: {'content-type': 'application/json'},
              body: JSON.stringify({ action })
            });
            const j = await r.json();
            if (r.ok && j.ok) {
              out.textContent = (action === 'enable' ? 'enabled' : 'disabled') + ' ✓';
              // Update the Service / On boot badges immediately from the
              // post-action status the backend captured, so the user sees
              // the new state without waiting for the page reload.
              if (j.status) {
                const a = j.status.active || 'unknown';
                const e = j.status.enabled || 'unknown';
                const activeCell  = document.getElementById('sshActiveCell');
                const enabledCell = document.getElementById('sshEnabledCell');
                if (activeCell)  activeCell.innerHTML  = a === 'active'   ? '<span class="badge ok">RUNNING</span>'  : '<span class="badge err">' + a.toUpperCase() + '</span>';
                if (enabledCell) enabledCell.innerHTML = e === 'enabled'  ? '<span class="badge ok">ENABLED</span>'  : '<span class="badge err">' + e.toUpperCase() + '</span>';
              }
              setTimeout(() => location.reload(), 1500);
            } else {
              out.textContent = 'error: ' + (j.error || r.status);
              if (j.hint) alert(j.hint);
            }
          } catch (err) {
            out.textContent = 'network error: ' + err.message;
          }
        }
        document.getElementById('sshEnableBtn').addEventListener('click', () => sshAction('enable'));
        document.getElementById('sshDisableBtn').addEventListener('click', () => sshAction('disable'));
      </script>
    </div>

    <div class="card">
      <h2>Account</h2>
      <dl>
        <dt>Username</dt><dd>${htmlEscape(status.auth.username)}</dd>
        <dt>Password</dt><dd>${status.auth.isDefaultPassword ? '<span class="badge err">DEFAULT</span> change it below' : '<span class="badge ok">SET</span>'}</dd>
      </dl>
      <form id="pwForm" style="margin-top:12px">
        <input type="password" name="current" placeholder="Current password" required autocomplete="current-password">
        <input type="password" name="next" placeholder="New password (min 6 chars)" required minlength="6" autocomplete="new-password">
        <input type="password" name="confirm" placeholder="Confirm new password" required minlength="6" autocomplete="new-password">
        <div class="row">
          <button type="submit">Change password</button>
          <span class="muted" id="pwResult"></span>
        </div>
      </form>
      <script>
        document.getElementById('pwForm').addEventListener('submit', async (e) => {
          e.preventDefault();
          const f = e.target;
          const out = document.getElementById('pwResult');
          if (f.next.value !== f.confirm.value) { out.textContent = 'new passwords do not match'; return; }
          out.textContent = 'updating…';
          try {
            const r = await fetch('/api/auth/change-password', {
              method: 'POST',
              headers: {'content-type': 'application/json'},
              body: JSON.stringify({ current: f.current.value, next: f.next.value })
            });
            const j = await r.json();
            if (r.ok) {
              out.textContent = 'password updated ✓ — you stay signed in';
              f.reset();
            } else {
              out.textContent = 'error: ' + (j.error || r.status);
            }
          } catch (err) {
            out.textContent = 'network error: ' + err.message;
          }
        });
      </script>
    </div>

  </div>

  <script>
    // Auto-refresh the page every 5s, but pause while any form is being used
    // so the user doesn't lose input mid-typing (e.g. on the password form).
    (function () {
      function shouldSkipRefresh() {
        const a = document.activeElement;
        // Skip if a form field is focused.
        if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT')) {
          return true;
        }
        // Skip if any text/password/textarea has any content typed in.
        const fields = document.querySelectorAll('input[type="text"], input[type="password"], textarea');
        for (const el of fields) {
          if (el.value && el.value.length > 0) return true;
        }
        return false;
      }
      setInterval(() => {
        if (!shouldSkipRefresh()) location.reload();
      }, 5000);
    })();
  </script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// HTTP server

function readBody(req, max = 64 * 1024) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', (chunk) => {
            data += chunk;
            if (data.length > max) reject(new Error('payload too large'));
        });
        req.on('end', () => resolve(data));
        req.on('error', reject);
    });
}

// Routes that don't require an authenticated session.
function isPublicRoute(method, pathname) {
    if (method === 'GET' && pathname === '/login') return true;
    if (method === 'POST' && pathname === '/api/auth/login') return true;
    if (method === 'GET' && pathname === '/api/health') return true;
    return false;
}

const server = http.createServer(async (req, res) => {
    // WHATWG URL needs an absolute base. The base is only used as scaffolding
    // here — we just want pathname/searchParams from the request's relative URL.
    const parsed = new URL(req.url, 'http://localhost');
    const pathname = parsed.pathname;

    try {
        // --- auth gate -----------------------------------------------------
        const cookies = parseCookies(req);
        const session = checkSession(cookies[SESSION_COOKIE]);
        if (!session && !isPublicRoute(req.method, pathname)) {
            // For GET browser navigation, redirect to login. For everything
            // else, return JSON 401 so client-side fetches can handle it.
            if (req.method === 'GET') {
                res.writeHead(302, { 'location': '/login' });
                res.end();
                return;
            }
            res.writeHead(401, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ error: 'authentication required' }));
            return;
        }

        // --- login page ----------------------------------------------------
        if (req.method === 'GET' && pathname === '/login') {
            // If already logged in, send them home.
            if (session) { res.writeHead(302, { 'location': '/' }); res.end(); return; }
            res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
            res.end(renderLoginPage({ error: parsed.searchParams.get('error') || null }));
            return;
        }

        // --- login endpoint ------------------------------------------------
        if (req.method === 'POST' && pathname === '/api/auth/login') {
            const ip = clientIp(req);
            const ct = String(req.headers['content-type'] || '').toLowerCase();

            // Reject locked-out IPs before doing any password work so the
            // rate limit also defends scrypt CPU cost.
            const lockout = checkLoginLockout(ip);
            if (lockout.locked) {
                const msg = `too many failed attempts — try again in ${lockout.retryAfterSec}s`;
                if (ct.includes('application/json')) {
                    res.writeHead(429, { 'content-type': 'application/json', 'retry-after': String(lockout.retryAfterSec) });
                    res.end(JSON.stringify({ error: msg }));
                } else {
                    res.writeHead(302, { 'location': '/login?error=' + encodeURIComponent(msg) });
                    res.end();
                }
                return;
            }

            const body = await readBody(req);
            // Accept either form-urlencoded (HTML form) or JSON.
            let username = '', password = '';
            if (ct.includes('application/json')) {
                try { const j = JSON.parse(body); username = j.username || ''; password = j.password || ''; } catch (_) {}
            } else {
                const params = new URLSearchParams(body);
                username = params.get('username') || '';
                password = params.get('password') || '';
            }
            const auth = loadAuth();
            const ok = username === auth.username && verifyPassword(password, auth.passwordHash, auth.salt);
            if (!ok) {
                recordLoginFailure(ip);
                if (ct.includes('application/json')) {
                    res.writeHead(401, { 'content-type': 'application/json' });
                    res.end(JSON.stringify({ error: 'invalid credentials' }));
                } else {
                    res.writeHead(302, { 'location': '/login?error=' + encodeURIComponent('invalid credentials') });
                    res.end();
                }
                return;
            }
            // Success — clear the failure budget for this IP.
            clearLoginFailures(ip);
            const sid = createSession(username);
            setSessionCookie(res, sid, Math.floor(SESSION_TTL_MS / 1000));
            if (ct.includes('application/json')) {
                res.writeHead(200, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ ok: true }));
            } else {
                res.statusCode = 302;
                res.setHeader('location', '/');
                res.end();
            }
            return;
        }

        // --- logout (GET so the link in the header works) -----------------
        if ((req.method === 'GET' || req.method === 'POST') && pathname === '/api/auth/logout') {
            destroySession(cookies[SESSION_COOKIE]);
            setSessionCookie(res, '', 0);
            res.writeHead(302, { 'location': '/login' });
            res.end();
            return;
        }

        // --- change password ----------------------------------------------
        if (req.method === 'POST' && pathname === '/api/auth/change-password') {
            const body = await readBody(req);
            let current = '', next = '';
            try { const j = JSON.parse(body); current = j.current || ''; next = j.next || ''; } catch (_) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'expected JSON body' }));
                return;
            }
            if (!next || next.length < 6) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'new password must be at least 6 characters' }));
                return;
            }
            const auth = loadAuth();
            if (!verifyPassword(current, auth.passwordHash, auth.salt)) {
                res.writeHead(401, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'current password is incorrect' }));
                return;
            }
            const seed = hashPassword(next);
            auth.passwordHash = seed.hash;
            auth.salt = seed.salt;
            auth.isDefaultPassword = false;
            auth.updatedAt = new Date().toISOString();
            saveAuth(auth);
            // Invalidate every existing session for this user so a leaked
            // cookie elsewhere can't outlive the rotation, then issue a fresh
            // session to the caller so they stay signed in.
            for (const [sid, s] of SESSIONS) {
                if (s.username === auth.username) SESSIONS.delete(sid);
            }
            const newSid = createSession(auth.username);
            setSessionCookie(res, newSid, Math.floor(SESSION_TTL_MS / 1000));
            res.writeHead(200, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ ok: true }));
            return;
        }

        if (req.method === 'GET' && (pathname === '/' || pathname === '/index.html')) {
            const status = await gatherStatus();
            res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
            res.end(renderPage(status));
            return;
        }

        if (req.method === 'GET' && pathname === '/api/status') {
            const status = await gatherStatus();
            res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
            res.end(JSON.stringify(status, null, 2));
            return;
        }

        if (req.method === 'GET' && pathname === '/api/health') {
            res.writeHead(200, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ ok: true, time: new Date().toISOString() }));
            return;
        }

        if (req.method === 'POST' && pathname === '/api/model/update') {
            const body = await readBody(req);
            let payload = {};
            try { payload = JSON.parse(body); } catch (_) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'expected JSON body' }));
                return;
            }
            const provider = String(payload.provider || '').trim();
            const model    = String(payload.model || '').trim();
            const apiKey   = payload.apiKey ? String(payload.apiKey) : '';
            const customEnvVar = payload.customEnvVar ? String(payload.customEnvVar).trim() : '';
            const wantsRestart = payload.restart !== false;

            if (!provider || !model) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'provider and model are required' }));
                return;
            }
            if (provider === 'custom' && !customEnvVar && apiKey) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'provider=custom requires customEnvVar to know which env var to set' }));
                return;
            }

            // 1. Update agents.defaults.model.primary in openclaw.json.
            //    Construct the model ref as "<provider>/<model>" unless model already has a slash.
            let cfg = readJsonSafe(CONFIG_PATH) || {};
            cfg.agents = cfg.agents || {};
            cfg.agents.defaults = cfg.agents.defaults || {};
            cfg.agents.defaults.model = cfg.agents.defaults.model || {};
            const modelRef = (provider === 'custom' || model.includes('/')) ? model : (provider + '/' + model);
            cfg.agents.defaults.model.primary = modelRef;
            // Remember which env var a custom provider uses so the Provider Keys
            // badge can surface it on subsequent renders even if it doesn't match
            // the "_API_KEY" suffix. Clear it when switching back to a known
            // provider so stale entries don't linger.
            if (provider === 'custom' && customEnvVar) {
                cfg.agents.defaults.model.customEnvVar = customEnvVar;
            } else if (provider !== 'custom' && cfg.agents.defaults.model.customEnvVar) {
                delete cfg.agents.defaults.model.customEnvVar;
            }
            try {
                fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
                fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
                try { fs.chmodSync(CONFIG_PATH, 0o600); } catch (_) {}
            } catch (e) {
                res.writeHead(500, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'failed to write config: ' + e.message }));
                return;
            }

            // 2. If an API key was provided, write it to ~/.openclaw/.env.
            let keyResult = null;
            if (apiKey) {
                const envVar = (provider === 'custom') ? customEnvVar : PROVIDER_ENV[provider];
                if (!envVar) {
                    res.writeHead(400, { 'content-type': 'application/json' });
                    res.end(JSON.stringify({ error: 'unknown provider; cannot map to env var name' }));
                    return;
                }
                try {
                    upsertEnvVar(ENV_PATH, envVar, apiKey);
                    keyResult = { ok: true, envVar };
                } catch (e) {
                    keyResult = { ok: false, error: e.message };
                }
            }

            // 3. Optionally restart the gateway.
            const restart = wantsRestart ? await restartGateway() : { ok: true, skipped: true };

            res.writeHead(200, { 'content-type': 'application/json' });
            res.end(JSON.stringify({
                ok: true,
                modelRef,
                key: keyResult,
                restart,
            }));
            return;
        }

        if (req.method === 'POST' && pathname === '/api/ssh/toggle') {
            const body = await readBody(req);
            let payload = {};
            try { payload = JSON.parse(body); } catch (_) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'expected JSON body' }));
                return;
            }
            const action = String(payload.action || '').trim();
            if (action !== 'enable' && action !== 'disable') {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'action must be "enable" or "disable"' }));
                return;
            }
            const result = await setSsh(action);
            res.writeHead(result.ok ? 200 : 502, { 'content-type': 'application/json' });
            res.end(JSON.stringify(result));
            return;
        }

        if (req.method === 'POST' && pathname === '/api/telegram/pairing/approve') {
            const body = await readBody(req);
            let payload = {};
            try { payload = JSON.parse(body); } catch (_) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'expected JSON body' }));
                return;
            }
            const code = String(payload.code || '').trim();
            // OpenClaw pairing codes are short alphanumerics. Reject anything
            // with shell-special characters as a defense-in-depth measure on
            // top of execFile's no-shell behavior.
            if (!code || !/^[A-Za-z0-9_-]{4,32}$/.test(code)) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'pairing code must be 4-32 chars (letters, digits, _ or -)' }));
                return;
            }
            const result = await runOpenClaw(['pairing', 'approve', 'telegram', code], 10000);
            // Some openclaw subcommands write the human-readable error to stdout
            // (e.g. "no pending pairing with code X"). Include both streams so
            // the dashboard can show whichever has content.
            const message = result.stderr || result.stdout || ('exit code ' + (result.code != null ? result.code : '?'));
            res.writeHead(result.ok ? 200 : 502, { 'content-type': 'application/json' });
            res.end(JSON.stringify({
                ok: result.ok,
                stdout: result.stdout,
                stderr: result.stderr,
                code: result.code,
                error: result.ok ? null : message,
            }));
            return;
        }

        if (req.method === 'POST' && pathname === '/api/telegram/token') {
            const body = await readBody(req);
            let payload = {};
            try { payload = JSON.parse(body); } catch (_) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'expected JSON body' }));
                return;
            }
            const botToken = String(payload.botToken || '').trim();
            const wantsRestart = payload.restart !== false;
            // BotFather tokens look like "1234567890:AAH..." (digits + colon + alphanumerics).
            // Don't be too strict so future format changes don't lock us out.
            if (!botToken || botToken.length < 20 || !botToken.includes(':')) {
                res.writeHead(400, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'token must be at least 20 chars and contain ":" (BotFather format)' }));
                return;
            }
            // Merge into openclaw.json: channels.telegram.botToken + enabled:true.
            let cfg = readJsonSafe(CONFIG_PATH) || {};
            cfg.channels = cfg.channels || {};
            cfg.channels.telegram = cfg.channels.telegram || {};
            cfg.channels.telegram.botToken = botToken;
            if (cfg.channels.telegram.enabled === undefined) cfg.channels.telegram.enabled = true;
            if (cfg.channels.telegram.dmPolicy === undefined) cfg.channels.telegram.dmPolicy = 'pairing';
            try {
                fs.mkdirSync(path.dirname(CONFIG_PATH), { recursive: true });
                fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
                try { fs.chmodSync(CONFIG_PATH, 0o600); } catch (_) {}
            } catch (e) {
                res.writeHead(500, { 'content-type': 'application/json' });
                res.end(JSON.stringify({ error: 'failed to write config: ' + e.message }));
                return;
            }
            const restart = wantsRestart ? await restartGateway() : { ok: true, skipped: true };
            res.writeHead(200, { 'content-type': 'application/json' });
            res.end(JSON.stringify({ ok: true, restart }));
            return;
        }

        res.writeHead(404, { 'content-type': 'text/plain' });
        res.end('not found');
    } catch (e) {
        res.writeHead(500, { 'content-type': 'text/plain' });
        res.end('server error: ' + (e.message || String(e)));
    }
});

// Initialize the auth file at startup so the default-credentials warning
// shows up in the journal immediately (not only after the first HTTP hit).
loadAuth();

server.listen(PORT, HOST, () => {
    console.log(`OpenClaw dashboard listening on http://${HOST}:${PORT}/`);
});
