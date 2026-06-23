# AD Ports Codex Desktop plugin installer (Windows)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Codex Desktop. It contains no secrets and never logs user data.
#
# Usage:
#   iex (irm https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.ps1)
#
# What happens when you run it:
#   1. Checks that the `codex` CLI is on PATH (Codex Desktop ships one).
#   2. Adds the AD Ports marketplace URL to Codex Desktop.
#   3. Installs the `adp-ai-sdlc-codex` plugin.
#   4. Reminds the user to sign in (which is done in the Codex Desktop UI).
#
# Override the marketplace URL with $env:ADPAI_MARKETPLACE_URL when smoke-testing
# a staging rendering.

$ErrorActionPreference = 'Stop'

$marketplaceUrl = if ($env:ADPAI_MARKETPLACE_URL) { $env:ADPAI_MARKETPLACE_URL } `
                  else { 'https://adports.github.io/adpai-installer/codex.marketplace.json' }
$pluginId = 'adports/adp-ai-sdlc-codex'

function Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Cyan }
function OkSay($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "! $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
  Die "Codex Desktop CLI ('codex') not found on PATH. Install Codex Desktop from https://openai.com/codex first."
}

try { $codexVer = (codex --version 2>$null) } catch { $codexVer = 'unknown' }
OkSay "Codex CLI present: $codexVer"

Say "Registering AD Ports marketplace: $marketplaceUrl"
codex plugin marketplace add adports $marketplaceUrl
OkSay 'Marketplace registered'

Say "Installing $pluginId"
codex plugin install $pluginId
OkSay 'Plugin installed'

Write-Host @'

Done. Open Codex Desktop and sign in to the AD Ports plugin:
  - Click the plugin in the chat composer.
  - Choose "Sign in".
  - Complete the AD Ports Microsoft sign-in flow in your browser.

Sign-in uses your existing AD Ports Microsoft account. The plugin server
never sees your password, and your refresh token never leaves the AD Ports
landing zone.
'@
