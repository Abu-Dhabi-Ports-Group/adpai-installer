# AD Ports Codex Desktop plugin installer (Windows)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Codex Desktop. It contains no secrets and never logs user data.
#
# NOTE ON OWNERSHIP: this is the CANONICAL copy. sync-installer-repo.sh in this
# same directory publishes it to the URL above, so this file is what users
# actually download. ext-hosts/hosts/codex/installers/install-codex-plugin.ps1 is a
# byte-equivalent mirror - see the "Installer ownership" section of
# ext-hosts/README.md. Change both or neither.
#
# Usage:
#   iex (irm https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.ps1)
#
# What happens when you run it:
#   1. Checks that the `codex` CLI is on PATH (Codex Desktop ships one).
#   2. Registers the AD Ports marketplace source with Codex Desktop.
#   3. Installs the `adp-ai-sdlc-codex` plugin from that marketplace.
#   4. Reminds the user to sign in (which is done in the Codex Desktop UI).
#
# Override the marketplace source with $env:ADPAI_MARKETPLACE_SOURCE when
# smoke-testing a staging rendering.

$ErrorActionPreference = 'Stop'

# Codex marketplace SOURCE - verified against codex-cli 0.139.0:
#   `codex plugin marketplace add [OPTIONS] <SOURCE>`
#   <SOURCE> := "a local path, owner/repo[@ref], HTTPS Git URL, or SSH Git URL"
# A bare .json URL is NOT a valid source: codex `git clone`s whatever it is
# given, so passing the rendered codex.marketplace.json URL fails with
# `fatal: repository '.../codex.marketplace.json/' not found`. The source must
# be a repo/directory containing `.agents/plugins/marketplace.json`.
# $env:ADPAI_MARKETPLACE_URL is still honoured for backwards compatibility, but
# it must now hold a SOURCE in one of the forms above, not a manifest URL.
$marketplaceSource = 'https://github.com/Abu-Dhabi-Ports-Group/adpai-installer'
if ($env:ADPAI_MARKETPLACE_URL)    { $marketplaceSource = $env:ADPAI_MARKETPLACE_URL }
if ($env:ADPAI_MARKETPLACE_SOURCE) { $marketplaceSource = $env:ADPAI_MARKETPLACE_SOURCE }

# Plugin selector - verified against codex-cli 0.139.0:
#   `codex plugin add [OPTIONS] <PLUGIN[@MARKETPLACE]>`
# The @MARKETPLACE half is the `name` field of the marketplace manifest, NOT a
# publisher/owner path. `codex plugin add adports/adp-ai-sdlc-codex` fails with
# "plugin requires --marketplace unless passed as <plugin>@<marketplace>".
$pluginSelector = 'adp-ai-sdlc-codex@adports'

function Say($msg)  { Write-Host "> $msg" -ForegroundColor Cyan }
function OkSay($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "! $msg" -ForegroundColor Yellow }
function Die($msg)  { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
  Die "Codex Desktop CLI ('codex') not found on PATH. Install Codex Desktop from https://openai.com/codex first."
}

try { $codexVer = (codex --version 2>$null) } catch { $codexVer = 'unknown' }
OkSay "Codex CLI present: $codexVer"

# Capability probe, not a version check - the same pattern the Claude installer
# uses. `codex plugin marketplace add` and `codex plugin add` exist on current
# Codex Desktop (verified against codex-cli 0.139.0), but older builds managed
# plugins differently. Probe rather than assume: with $ErrorActionPreference =
# 'Stop' an installer that invokes a subcommand the local build does not have
# dies on a raw clap usage error, which is worse than printing instructions.
#
# Note `codex plugin install` does NOT exist on any build - it is `plugin add`.
# The pre-merge installer called `install` and passed two positionals to
# `marketplace add`; both were fatal.
$hasPluginCli = $false
try {
  codex plugin marketplace add --help *> $null
  if ($LASTEXITCODE -eq 0) {
    codex plugin add --help *> $null
    $hasPluginCli = ($LASTEXITCODE -eq 0)
  }
} catch { $hasPluginCli = $false }

if ($hasPluginCli) {
  Say "Registering AD Ports marketplace: $marketplaceSource"
  codex plugin marketplace add $marketplaceSource
  if ($LASTEXITCODE -ne 0) { Die "codex plugin marketplace add failed (exit $LASTEXITCODE)" }
  OkSay 'Marketplace registered'

  Say "Installing $pluginSelector"
  codex plugin add $pluginSelector
  if ($LASTEXITCODE -ne 0) { Die "codex plugin add failed (exit $LASTEXITCODE)" }
  OkSay 'Plugin installed'
} else {
  Warn "This Codex build has no 'codex plugin add' CLI - printing manual steps."
  Write-Host ""
  Write-Host "Update Codex Desktop, then run:"
  Write-Host ""
  Write-Host "  codex plugin marketplace add $marketplaceSource"
  Write-Host "  codex plugin add $pluginSelector"
  Write-Host ""
}

Write-Host @'

Done. Open Codex Desktop and sign in to the AD Ports plugin:
  - Click the plugin in the chat composer.
  - Choose "Sign in".
  - Complete the AD Ports Microsoft sign-in flow in your browser.

Sign-in uses your existing AD Ports Microsoft account. The plugin server
never sees your password, and your refresh token never leaves the AD Ports
landing zone.
'@
