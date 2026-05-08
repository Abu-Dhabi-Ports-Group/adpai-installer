# AD Ports — install @adports/aidev (Windows PowerShell)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can run it without cloning the ai-skills repo.
# It contains no secrets. The user still authenticates to the private Azure
# Artifacts feed using their own AD Ports identity (SSO via vsts-npm-auth,
# Microsoft's official Azure Artifacts helper).
#
# Usage:
#   iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex
#
# Prerequisites:
#   - Node 18+ (download from https://nodejs.org if missing)
#   - Your AD Ports identity must have Feed Reader on the adpai feed:
#       https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions

$ErrorActionPreference = 'Stop'

$FeedRegistryHost = '//pkgs.dev.azure.com/abudhabiports/_packaging/adpai/npm/registry/'
$FeedUrl          = "https:$FeedRegistryHost"
$Pkg              = '@adports/aidev'
$Npmrc            = Join-Path $HOME '.npmrc'

function Say  ($m) { Write-Host "▸ $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "✓ $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

# ---------- Node ----------
Say 'Checking Node.js (need 18+)'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Die 'Node.js not found. Install Node 18+ from https://nodejs.org and re-run.'
}
$nodeVer = (node -v).TrimStart('v')
$nodeMajor = [int]($nodeVer.Split('.')[0])
if ($nodeMajor -lt 18) { Die "Node $nodeVer detected; need Node 18 or newer." }
Ok "Node v$nodeVer, npm $(npm -v)"

# ---------- vsts-npm-auth ----------
if (-not (Get-Command vsts-npm-auth -ErrorAction SilentlyContinue)) {
  Say 'Installing vsts-npm-auth (Microsoft Azure Artifacts auth helper)'
  npm install -g vsts-npm-auth | Out-Null
}
Ok 'vsts-npm-auth ready'

# ---------- Project-scoped .npmrc for vsts-npm-auth to read ----------
$work = Join-Path $env:TEMP "adpai-bootstrap-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$projectNpmrc = Join-Path $work '.npmrc'
@(
  "@adports:registry=$FeedUrl",
  'always-auth=true'
) | Set-Content -Path $projectNpmrc -Encoding ASCII

# ---------- SSO sign-in ----------
Say 'Running vsts-npm-auth (browser will open for AD Ports SSO)'
Push-Location $work
try {
  & vsts-npm-auth -config $projectNpmrc
  if ($LASTEXITCODE -ne 0) { Die "vsts-npm-auth failed (exit code $LASTEXITCODE)." }
} finally {
  Pop-Location
}
Ok 'vsts-npm-auth wrote refresh token to ~/.npmrc'

# ---------- Clean legacy / duplicate scope lines ----------
if (Test-Path $Npmrc) {
  $existing = Get-Content $Npmrc -ErrorAction SilentlyContinue
  $kept = @()
  $sawScope = $false
  foreach ($line in $existing) {
    if ($line -match '^@adports:registry=') {
      if (-not $sawScope -and $line -match 'adpai') {
        $kept += $line
        $sawScope = $true
      }
      continue
    }
    if ($line -match 'pkgs\.dev\.azure\.com/abudhabiports/Foundations/_packaging/ai-native') { continue }
    $kept += $line
  }
  if (-not $sawScope) {
    $kept += "@adports:registry=$FeedUrl"
    $kept += 'always-auth=true'
  }
  $kept | Set-Content -Path $Npmrc -Encoding ASCII
}

# ---------- Verify + install ----------
Say 'Verifying feed access'
$ver = & npm view $Pkg version 2>$null
if (-not $ver) {
  Die @"
Feed access failed. Most likely: your AD Ports identity is missing 'Feed Reader' on the adpai feed.
Ask the admin to grant access at:
https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions
"@
}
Ok "Feed reachable — latest $Pkg = $ver"

Say "Installing $Pkg globally"
npm install -g $Pkg | Out-Null
$installed = & adpai --version 2>$null
if (-not $installed) { $installed = "$Pkg@$ver" }
Ok "Installed: $installed"

# ---------- Done ----------
Write-Host ''
Ok 'Setup complete. Try:'
Write-Host '    adpai --help'
Write-Host '    adpai -y --preset backend-nestjs --tools claude'
Write-Host ''
Write-Host 'The vsts-npm-auth refresh token lasts ~90 days and renews automatically.'
