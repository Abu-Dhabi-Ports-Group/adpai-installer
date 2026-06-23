# AD Ports — install ALL AD Ports AI tooling (Windows)
#
# Publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can bootstrap the full toolchain with one command.
# No secrets, no PAT input — each sub-installer handles its own auth.
#
# Usage:
#   iex (irm https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-all.ps1)
#
# What it installs (in order):
#   1. @adports/aidev CLI       (required — install-adpai.ps1)
#   2. ADP AI VS Code extension (required — install-vsix.ps1)
#   3. Codex Desktop plugin     (optional — install-codex-plugin.ps1; skipped if `codex` is missing)
#   4. Claude Code plugin       (optional — install-claude-plugin.ps1; skipped if `claude` is missing)
#
# Skip behavior:
#   - Steps 1 and 2 are required. If either fails, the script exits non-zero.
#   - Steps 3 and 4 are optional. If the host CLI is missing or the install
#     fails, the step is logged and skipped — the overall script keeps going.

$ErrorActionPreference = 'Continue'

$BASE = $env:ADPAI_INSTALLER_BASE
if (-not $BASE) { $BASE = 'https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main' }

function Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Cyan }
function OkSay($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "! $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

function Invoke-Step {
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$Url
  )
  Say "Installing: $Label"
  $scriptText = $null
  try {
    $scriptText = (Invoke-WebRequest -UseBasicParsing -Uri $Url).Content
  } catch {
    return @{ ok = $false; reason = "Download failed: $($_.Exception.Message)" }
  }
  try {
    Invoke-Expression $scriptText
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
      return @{ ok = $false; reason = "Installer returned exit code $LASTEXITCODE" }
    }
    return @{ ok = $true }
  } catch {
    return @{ ok = $false; reason = "Installer threw: $($_.Exception.Message)" }
  }
}

function Run-Required {
  param([string]$Label, [string]$Url)
  $r = Invoke-Step -Label $Label -Url $Url
  if ($r.ok) { OkSay "$Label installed" }
  else       { Die "$Label installation failed: $($r.reason). Required step; aborting." }
}

function Run-Optional {
  param([string]$Label, [string]$Url, [string]$HostCli)
  if (-not (Get-Command $HostCli -ErrorAction SilentlyContinue)) {
    Warn "$Label`: '$HostCli' CLI not found on PATH — skipping."
    return
  }
  $r = Invoke-Step -Label $Label -Url $Url
  if ($r.ok) { OkSay "$Label installed" }
  else       { Warn "$Label installation failed: $($r.reason) — continuing (optional step)." }
}

# --- Required ------------------------------------------------------------
Run-Required 'AD Ports CLI (@adports/aidev)'           "$BASE/install-adpai.ps1"
Run-Required 'AD Ports VS Code extension (adp-ai-sdlc)' "$BASE/install-vsix.ps1"

# --- Optional (only if host CLI is present) ------------------------------
Run-Optional 'Codex Desktop plugin'  "$BASE/install-codex-plugin.ps1"  'codex'
Run-Optional 'Claude Code plugin'    "$BASE/install-claude-plugin.ps1" 'claude'

Write-Host ""
OkSay "Done. Run 'adpai --help' in a new PowerShell window to verify the CLI is on PATH."
Write-Host "  Restart VS Code to load the extension."
Write-Host "  Sign in to the Codex / Claude plugin from the host UI on first use."
