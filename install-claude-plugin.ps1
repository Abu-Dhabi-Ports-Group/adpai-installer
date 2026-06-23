# AD Ports Claude Code plugin installer (Windows)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Claude Code session.
#
# Usage:
#   iex (irm https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-claude-plugin.ps1)

$ErrorActionPreference = 'Stop'

$marketplaceUrl = if ($env:ADPAI_MARKETPLACE_URL) { $env:ADPAI_MARKETPLACE_URL } `
                  else { 'https://adports.github.io/adpai-installer/claude.marketplace.json' }
$pluginId = 'adp-ai-sdlc-claude'

function Say($msg)  { Write-Host "▸ $msg" -ForegroundColor Cyan }
function OkSay($msg) { Write-Host "✓ $msg" -ForegroundColor Green }
function Die($msg)  { Write-Host "✗ $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Die "Claude Code CLI ('claude') not found on PATH. Install Claude Code from https://www.anthropic.com/claude-code first."
}
try { $claudeVer = (claude --version 2>$null) } catch { $claudeVer = 'unknown' }
OkSay "Claude CLI present: $claudeVer"

Write-Host ""
Write-Host "Run these two commands inside any Claude Code session to register and install:"
Write-Host ""
Write-Host "  /plugin marketplace add adports $marketplaceUrl"
Write-Host "  /plugin install $pluginId"
Write-Host ""
Write-Host "After installation, sign in by invoking any AD Ports tool — Claude Code will"
Write-Host "hand you off to the OAuth flow in your browser."
Write-Host ""
Write-Host "Sign-in uses your existing AD Ports Microsoft account. The plugin server"
Write-Host "never sees your password, and your refresh token never leaves the AD Ports"
Write-Host "landing zone."
