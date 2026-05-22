# Install the latest ADP AI SDLC VS Code extension from the
# Azure Artifacts Universal feed (Foundations / adpai-vsix).
#
# Prerequisites (one-time, per user):
#   1. Azure CLI:        winget install Microsoft.AzureCLI
#   2. DevOps extension: az extension add --name azure-devops
#   3. Sign in:          az login
#
# Usage:
#   pwsh install-vsix.ps1                       # latest version, also installs CLI
#   pwsh install-vsix.ps1 -Version 2.0.1
#   pwsh install-vsix.ps1 -SkipCli              # VSIX only, skip CLI bootstrap
[CmdletBinding()]
param(
  [string]$Version = "*",
  [string]$Org     = "https://dev.azure.com/abudhabiports",
  [string]$Project = "Foundations",
  [string]$Feed    = "adpai-vsix",
  [string]$Package = "adp-ai-sdlc",
  [switch]$SkipCli
)

$ErrorActionPreference = 'Stop'
$CliInstallerUrl = 'https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1'

function Require-Command($name, $hint) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Error "Required command not found: '$name'. $hint"
  }
}

Require-Command 'az'   "Install Azure CLI: https://aka.ms/installazurecli"
Require-Command 'code' "Open VS Code, run 'Shell Command: Install code command in PATH'."

# Ensure azure-devops extension is installed (idempotent).
$hasExt = az extension show --name azure-devops 2>$null
if (-not $hasExt) {
  Write-Host ">> Installing 'azure-devops' Azure CLI extension ..."
  az extension add --name azure-devops --only-show-errors | Out-Null
}

# Confirm signed in.
$account = az account show 2>$null
if (-not $account) {
  Write-Host ">> Not signed in. Running 'az login' ..."
  az login --only-show-errors | Out-Null
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("adpai-vsix-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  Write-Host ">> Downloading $Package@$Version from $Org/$Project/$Feed ..."
  az artifacts universal download `
    --organization $Org `
    --project $Project `
    --scope project `
    --feed $Feed `
    --name $Package `
    --version $Version `
    --path $tmp `
    --only-show-errors

  $vsix = Get-ChildItem -Path $tmp -Filter '*.vsix' -File | Select-Object -First 1
  if (-not $vsix) {
    Get-ChildItem -Path $tmp | Out-Host
    Write-Error "No .vsix found in downloaded package."
  }

  Write-Host ">> Installing $($vsix.Name) into VS Code ..."
  & code --install-extension $vsix.FullName --force

  if (-not $SkipCli) {
    Write-Host ""
    Write-Host ">> Bootstrapping @adports/aidev CLI ..."
    try {
      Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri $CliInstallerUrl).Content
    }
    catch {
      Write-Warning "CLI bootstrap failed: $($_.Exception.Message)"
      Write-Warning "Run it manually: iwr -useb $CliInstallerUrl | iex"
    }
  }
  else {
    Write-Host ""
    Write-Host ">> -SkipCli set; @adports/aidev CLI NOT installed."
    Write-Host "   To install later: iwr -useb $CliInstallerUrl | iex"
  }

  Write-Host ""
  Write-Host ">> Done. Reload VS Code window (Ctrl+Shift+P -> 'Developer: Reload Window') to activate the extension."
}
finally {
  Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
}
