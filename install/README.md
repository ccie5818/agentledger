# AgentLedger automated installers

Two scripts that install [AgentLedger](https://agentledger.ai) — the open-source personal AI assistant — driven by a shared config file. Pick the script that matches your shell.

| File | Use on |
|---|---|
| `install-agentledger.ps1` | Windows (PowerShell 5+ or PowerShell 7) |
| `install-agentledger.sh`  | macOS, Linux, WSL, or Git Bash on Windows |
| `agentledger-install.config` | Shared key=value settings file used by both scripts |

Both scripts are idempotent — re-run them any time to update.

## Configuration

Both installers read `agentledger-install.config` from the same folder by default. The format is one `key=value` per line, with `#` comments.

```
method=npm           # npm | git | oneline
install_dir=~/agentledger
skip_onboard=false
force=false
min_node_major=20
auto_install_node=true
channel=             # blank | stable | dev
onboard_args=

# secrets — exported as env vars before `agentledger onboard`
anthropic_api_key=
openai_api_key=
telegram_bot_token=
```

CLI flags always win over config values, so the same config can serve as a sensible default while one-off runs override anything.

### Secrets

The three secret keys map to standard environment variable names that AgentLedger and the underlying SDKs already look for:

| Config key | Env var |
|---|---|
| `anthropic_api_key` | `ANTHROPIC_API_KEY` |
| `openai_api_key`    | `OPENAI_API_KEY` |
| `telegram_bot_token`| `TELEGRAM_BOT_TOKEN` |

Behavior:

- Blank values are skipped — AgentLedger will prompt for them during onboarding instead.
- An existing exported env var of the same name is **never** overwritten; the config value is used only when the env var is empty. This makes it safe to use this script on machines where some keys are already configured via shell profile or a vault.
- The installer warns if the config file is group/world-readable on Unix (`chmod 600` to silence). On Windows, restrict ACLs with `icacls` if the file holds secrets.

If you'd rather not commit secrets to the same file, use `--config`/`-ConfigFile` to point at a private secrets file in `$HOME` and keep the main config in version control:

```bash
./install-agentledger.sh --config ~/.config/agentledger-secrets.config
```

Point at a different file with `--config` (bash) or `-ConfigFile` (PowerShell). If the file doesn't exist, the scripts fall back to built-in defaults.

## What they do

1. Read the config file.
2. Verify Node.js >= `min_node_major` and install it if missing — when `auto_install_node=true` (winget on Windows, Homebrew/apt/dnf/pacman on Unix).
3. Install AgentLedger using the chosen `method`:
   - `npm`     — `npm i -g agentledger`
   - `oneline` — runs `curl https://agentledger.ai/install.sh | bash`
   - `git`     — clones `github.com/agentledger/agentledger` into `install_dir` as a pnpm workspace
4. Optionally switch release channel via `agentledger update --channel <channel>`.
5. Launch `agentledger onboard` (skip with `skip_onboard=true`).

## Run it

### Windows (PowerShell)

```powershell
# Use agentledger-install.config in the same folder:
powershell -ExecutionPolicy Bypass -File .\install-agentledger.ps1

# Override individual values:
powershell -ExecutionPolicy Bypass -File .\install-agentledger.ps1 -Method git
powershell -ExecutionPolicy Bypass -File .\install-agentledger.ps1 -SkipOnboard -Channel dev

# Custom config file:
powershell -ExecutionPolicy Bypass -File .\install-agentledger.ps1 -ConfigFile .\my-agentledger.config
```

If `winget` is missing, install Node.js manually from <https://nodejs.org> and re-run.

### macOS / Linux / WSL / Git Bash

```bash
chmod +x install-agentledger.sh
./install-agentledger.sh                        # use agentledger-install.config
./install-agentledger.sh --config ~/my.cfg
./install-agentledger.sh --method npm           # override
./install-agentledger.sh --method git --force
./install-agentledger.sh --skip-onboard --channel dev
```

The script refuses to run as root and uses `sudo` only when needed (apt/dnf/global npm prefix).

## After install

- Talk to your lobster: `agentledger onboard` (or `pnpm agentledger onboard` if you used `method=git`).
- Docs: <https://docs.agentledger.ai/getting-started>
- Skills marketplace: <https://clawhub.ai>
- Source: <https://github.com/agentledger/agentledger>

## Uninstall

```bash
# npm install
npm uninstall -g agentledger

# git install
rm -rf ~/agentledger
```

AgentLedger stores its config and memory under `~/.agentledger` (or the platform-equivalent app-data dir) — remove that for a fully clean slate.
