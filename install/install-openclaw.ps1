<#
.SYNOPSIS
  Automated installer for OpenClaw (https://openclaw.ai) on Windows.

.DESCRIPTION
  Installs OpenClaw — the open-source personal AI assistant by Peter Steinberger.
  Configuration is read from a key=value config file (default:
  openclaw-install.config next to this script). Any CLI parameter overrides
  the corresponding config value.

  Steps:
    1. Verify Node.js (>= min_node_major). Install LTS via winget if missing
       and auto_install_node=true.
    2. Verify npm.
    3. Install (or update) OpenClaw using the chosen method.
    4. Optionally switch release channel.
    5. Optionally run `openclaw onboard`.

  Re-running is safe: the script skips work that's already done.

.PARAMETER ConfigFile
  Path to the config file. Defaults to openclaw-install.config alongside
  this script. If the file is missing, built-in defaults are used.

.PARAMETER Method
  Override `method=` from config. One of: npm, git, oneline.

.PARAMETER InstallDir
  Override `install_dir=` from config (used only with -Method git).

.PARAMETER SkipOnboard
  Override `skip_onboard=true` to skip the onboarding step.

.PARAMETER Force
  Override `force=true` to reinstall even if already present.

.PARAMETER Channel
  Override `channel=` to switch release channels after install (stable|dev).

.EXAMPLE
  .\install-openclaw.ps1
  .\install-openclaw.ps1 -ConfigFile .\my-openclaw.config
  .\install-openclaw.ps1 -Method git -SkipOnboard
#>
[CmdletBinding()]
param(
    [string]$ConfigFile,

    [ValidateSet('npm', 'git', 'oneline')]
    [string]$Method,

    [string]$InstallDir,

    [switch]$SkipOnboard,

    [switch]$Force,

    [ValidateSet('', 'stable', 'dev')]
    [string]$Channel
)

$ErrorActionPreference = 'Stop'

# --- output helpers -------------------------------------------------------

function Write-Step    { param([string]$msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok      { param([string]$msg) Write-Host "    $msg" -ForegroundColor Green }
function Write-Warning2 { param([string]$msg) Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$msg) Write-Host "!!  $msg" -ForegroundColor Red }

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# --- config loading -------------------------------------------------------

function ConvertTo-Bool {
    param([string]$Value, [bool]$Default = $false)
    if ($null -eq $Value -or $Value -eq '') { return $Default }
    switch -Regex ($Value.Trim().ToLower()) {
        '^(1|true|yes|y|on)$'  { return $true }
        '^(0|false|no|n|off)$' { return $false }
        default                { return $Default }
    }
}

function Expand-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ($Path.StartsWith('~')) {
        return Join-Path $HOME $Path.Substring(1).TrimStart('/', '\')
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Read-ConfigFile {
    param([string]$Path)
    $cfg = @{}
    if (-not $Path -or -not (Test-Path $Path)) { return $cfg }
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq).Trim().ToLower()
        $val = $line.Substring($eq + 1).Trim()
        # strip matching surrounding quotes
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or
            ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $cfg[$key] = $val
    }
    return $cfg
}

# Resolve config file path: explicit -> next to script -> none.
if (-not $ConfigFile) {
    $ConfigFile = Join-Path $PSScriptRoot 'openclaw-install.config'
}
$cfg = Read-ConfigFile -Path $ConfigFile

# Merge config + CLI. CLI wins when explicitly bound.
$bound = $PSBoundParameters
$effMethod      = if ($bound.ContainsKey('Method')      -and $Method)     { $Method }     elseif ($cfg.method)      { $cfg.method }      else { 'npm' }
$effInstallDir  = if ($bound.ContainsKey('InstallDir')  -and $InstallDir) { $InstallDir } elseif ($cfg.install_dir) { Expand-Path $cfg.install_dir } else { Join-Path $HOME 'openclaw' }
$effSkipOnboard = if ($bound.ContainsKey('SkipOnboard'))                  { [bool]$SkipOnboard } else { ConvertTo-Bool $cfg.skip_onboard $false }
$effForce       = if ($bound.ContainsKey('Force'))                        { [bool]$Force }       else { ConvertTo-Bool $cfg.force $false }
$effChannel     = if ($bound.ContainsKey('Channel'))                      { $Channel }           elseif ($cfg.channel) { $cfg.channel } else { '' }
$effMinNode     = if ($cfg.min_node_major) { [int]$cfg.min_node_major } else { 20 }
$effAutoNode    = ConvertTo-Bool $cfg.auto_install_node $true
$effOnboardArgs = if ($cfg.onboard_args) { $cfg.onboard_args } else { '' }

# Secrets — env-var name -> config key. Existing env vars are not overwritten.
$Secrets = @(
    @{ Env = 'ANTHROPIC_API_KEY';   Key = 'anthropic_api_key';   Label = 'Anthropic API key' }
    @{ Env = 'OPENAI_API_KEY';      Key = 'openai_api_key';      Label = 'OpenAI API key'    }
    @{ Env = 'TELEGRAM_BOT_TOKEN';  Key = 'telegram_bot_token';  Label = 'Telegram bot token'}
)

if ($effMethod -notin @('npm', 'git', 'oneline')) {
    Write-Err "Invalid method '$effMethod' (use: npm | git | oneline)"
    exit 1
}

# --- node + npm -----------------------------------------------------------

function Get-NodeMajorVersion {
    if (-not (Test-Command node)) { return 0 }
    try {
        $v = (& node --version) -replace '^v', ''
        return [int]($v.Split('.')[0])
    } catch { return 0 }
}

function Install-NodeViaWinget {
    Write-Step 'Installing Node.js LTS via winget'
    if (-not (Test-Command winget)) {
        Write-Err 'winget is not available. Install Node.js manually from https://nodejs.org/ and re-run.'
        throw 'winget missing'
    }
    & winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install failed (exit $LASTEXITCODE)" }
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

function Ensure-Node {
    Write-Step 'Checking Node.js'
    $major = Get-NodeMajorVersion
    if ($major -ge $effMinNode) {
        Write-Ok "Node.js v$major detected (>= $effMinNode)."
        return
    }
    if ($major -gt 0) {
        Write-Warning2 "Node.js v$major is too old (need >= $effMinNode)."
    } else {
        Write-Warning2 'Node.js not found.'
    }
    if (-not $effAutoNode) {
        throw "auto_install_node=false in config — install Node.js >= v$effMinNode and re-run."
    }
    Install-NodeViaWinget
    $major = Get-NodeMajorVersion
    if ($major -lt $effMinNode) {
        throw "Node.js install did not produce >= v$effMinNode (got v$major). Open a new terminal and re-run."
    }
    Write-Ok "Node.js v$major ready."
}

function Ensure-Npm {
    if (-not (Test-Command npm)) {
        throw 'npm not found on PATH after Node install. Open a fresh PowerShell window and re-run.'
    }
}

# --- install methods ------------------------------------------------------

function Install-OpenClawViaNpm {
    Write-Step 'Installing OpenClaw via npm (global)'
    $already = $false
    try {
        $list = & npm ls -g --depth=0 --json 2>$null | ConvertFrom-Json
        if ($list.dependencies.openclaw) { $already = $true }
    } catch { }

    if ($already -and -not $effForce) {
        Write-Ok 'openclaw already installed globally — running update.'
        & npm update -g openclaw
    } else {
        & npm install -g openclaw
    }
    if ($LASTEXITCODE -ne 0) { throw "npm install failed (exit $LASTEXITCODE)" }
    Write-Ok 'openclaw npm package installed.'
}

function Install-OpenClawFromGit {
    Write-Step "Cloning OpenClaw into $effInstallDir"
    if (-not (Test-Command git)) {
        throw 'git is required for method=git. Install Git for Windows: https://git-scm.com/download/win'
    }
    if (Test-Path $effInstallDir) {
        if ($effForce) {
            Write-Warning2 "Removing existing $effInstallDir (force=true)"
            Remove-Item -Recurse -Force $effInstallDir
        } else {
            Write-Ok 'Existing checkout found — pulling latest.'
            Push-Location $effInstallDir
            try { & git pull --ff-only } finally { Pop-Location }
        }
    }
    if (-not (Test-Path $effInstallDir)) {
        & git clone https://github.com/openclaw/openclaw.git $effInstallDir
        if ($LASTEXITCODE -ne 0) { throw 'git clone failed' }
    }

    Write-Step 'Enabling corepack and installing pnpm workspace deps'
    & corepack enable
    Push-Location $effInstallDir
    try {
        & pnpm install
        if ($LASTEXITCODE -ne 0) { throw 'pnpm install failed' }
    } finally { Pop-Location }
    Write-Ok "Source install ready at $effInstallDir"
}

function Install-OpenClawOneLiner {
    Write-Step 'Running official one-liner (requires Git Bash or WSL)'
    if     (Test-Command bash)    { & bash -c 'curl -fsSL https://openclaw.ai/install.sh | bash' }
    elseif (Test-Command 'wsl')   { & wsl bash -c 'curl -fsSL https://openclaw.ai/install.sh | bash' }
    else {
        throw 'Need bash on PATH (Git Bash) or WSL for method=oneline.'
    }
    if ($LASTEXITCODE -ne 0) { throw "one-liner install failed (exit $LASTEXITCODE)" }
}

# --- secrets --------------------------------------------------------------

function Warn-ConfigFilePermissions {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    # Strip inherited ACEs for a quick, conservative check: complain if more
    # than just the current user has access. PowerShell on Windows only.
    try {
        $acl = Get-Acl -LiteralPath $Path
        $me = "$env:USERDOMAIN\$env:USERNAME"
        $extra = $acl.Access | Where-Object {
            $_.IdentityReference.Value -ne $me -and
            $_.IdentityReference.Value -notmatch '^(NT AUTHORITY\\SYSTEM|BUILTIN\\Administrators|.*\\Administrators)$'
        }
        if ($extra) {
            Write-Warning2 "Config file '$Path' is accessible to additional principals. Consider:"
            Write-Warning2 "  icacls `"$Path`" /inheritance:r /grant:r `"$env:USERNAME`":F"
        }
    } catch { }
}

function Apply-Secrets {
    $set = @()
    foreach ($s in $Secrets) {
        $current = [Environment]::GetEnvironmentVariable($s.Env, 'Process')
        if ($current) { continue }     # never overwrite an existing env var
        $val = $cfg[$s.Key]
        if (-not $val) { continue }
        Set-Item -Path "env:$($s.Env)" -Value $val
        $set += $s.Label
    }
    if ($set.Count -gt 0) {
        Write-Step 'Exporting credentials from config'
        foreach ($name in $set) { Write-Ok "  $name -> environment" }
    }
}

# --- post-install steps ---------------------------------------------------

function Switch-Channel {
    if (-not $effChannel) { return }
    Write-Step "Switching OpenClaw to '$effChannel' channel"
    if ($effMethod -eq 'git') {
        Push-Location $effInstallDir
        try { & pnpm openclaw update --channel $effChannel } finally { Pop-Location }
    } else {
        & openclaw update --channel $effChannel
    }
}

function Invoke-Onboard {
    if ($effSkipOnboard) {
        Write-Ok 'Skipping onboarding (skip_onboard=true).'
        Write-Ok 'When ready, run: openclaw onboard'
        return
    }
    Write-Step 'Starting OpenClaw onboarding'
    Write-Ok 'This is interactive — answer the prompts to meet your lobster.'
    $argList = @()
    if ($effOnboardArgs) {
        $argList = $effOnboardArgs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    }
    if ($effMethod -eq 'git') {
        Push-Location $effInstallDir
        try { & pnpm openclaw onboard @argList } finally { Pop-Location }
    } else {
        & openclaw onboard @argList
    }
}

# --- main -----------------------------------------------------------------

Write-Host ''
Write-Host '+--------------------------------------------+' -ForegroundColor Magenta
Write-Host '|        OpenClaw Automated Installer        |' -ForegroundColor Magenta
Write-Host '+--------------------------------------------+' -ForegroundColor Magenta
if (Test-Path $ConfigFile) {
    Write-Host "    config:  $ConfigFile" -ForegroundColor DarkGray
} else {
    Write-Host "    config:  (not found — using built-in defaults)" -ForegroundColor DarkGray
}
Write-Host  "    method:  $effMethod"      -ForegroundColor DarkGray
if ($effMethod -eq 'git') { Write-Host "    dir:     $effInstallDir" -ForegroundColor DarkGray }
if ($effChannel)          { Write-Host "    channel: $effChannel"    -ForegroundColor DarkGray }
Write-Host ''

try {
    switch ($effMethod) {
        'oneline' {
            Install-OpenClawOneLiner
        }
        'git' {
            Ensure-Node
            Ensure-Npm
            if (-not (Test-Command pnpm)) {
                Write-Step 'Installing pnpm globally'
                & npm install -g pnpm
            }
            Install-OpenClawFromGit
        }
        default {
            Ensure-Node
            Ensure-Npm
            Install-OpenClawViaNpm
        }
    }

    Switch-Channel
    Warn-ConfigFilePermissions -Path $ConfigFile
    Apply-Secrets
    Invoke-Onboard

    Write-Host ''
    Write-Ok 'Done. Docs: https://docs.openclaw.ai/getting-started'
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
