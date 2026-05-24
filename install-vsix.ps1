# Install the latest ADP AI SDLC VS Code extension from the
# Azure Artifacts Universal feed (Foundations / adpai-vsix).
#
# Prerequisites are bootstrapped when possible:
#   1. Azure CLI        (winget, then Chocolatey fallback)
#   2. VS Code CLI      (winget, then Chocolatey fallback)
#   3. DevOps extension (az extension add --name azure-devops)
#   4. Sign in          (az login, interactive when required)
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

function Say  ($m) { Write-Host ">> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "OK $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "!! $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "ERROR $m" -ForegroundColor Red; exit 1 }

function Invoke-Native ($filePath, $arguments) {
  $oldErrorActionPreference = $ErrorActionPreference
  $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue
  $oldNativePreference = $null
  if ($nativePreference) {
    $oldNativePreference = $global:PSNativeCommandUseErrorActionPreference
    $global:PSNativeCommandUseErrorActionPreference = $false
  }

  try {
    $ErrorActionPreference = 'Continue'
    $output = & $filePath @arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
    if ($nativePreference) {
      $global:PSNativeCommandUseErrorActionPreference = $oldNativePreference
    }
  }

  [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($output)
  }
}

function Resolve-Cmd ($name) {
  $commands = @(Get-Command $name -All -ErrorAction SilentlyContinue)
  if ($commands.Count -eq 0) { return $null }

  foreach ($ext in @('.cmd', '.exe', '.bat')) {
    foreach ($cmd in $commands) {
      $path = if ($cmd.Path) { $cmd.Path } elseif ($cmd.Source) { $cmd.Source } else { $cmd.Name }
      if ($path -and $path.EndsWith($ext, [System.StringComparison]::OrdinalIgnoreCase)) { return $path }
    }
  }

  $firstPath = if ($commands[0].Path) { $commands[0].Path } elseif ($commands[0].Source) { $commands[0].Source } else { $commands[0].Name }
  if ($firstPath -and $firstPath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
    $cmdShim = [System.IO.Path]::ChangeExtension($firstPath, '.cmd')
    if (Test-Path $cmdShim) { return $cmdShim }
  }
  return $firstPath
}

function Add-PathIfExists ($path) {
  if (-not $path -or -not (Test-Path $path)) { return }
  $parts = @($env:Path -split ';' | Where-Object { $_ })
  if (-not ($parts | Where-Object { $_.TrimEnd('\') -ieq $path.TrimEnd('\') })) {
    $env:Path = "$path;$env:Path"
  }
}

function Refresh-Path {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $currentParts = @($env:Path -split ';' | Where-Object { $_ })
  $refreshedParts = @((@($machinePath, $userPath) -join ';') -split ';' | Where-Object { $_ })
  foreach ($part in $currentParts) {
    if (-not ($refreshedParts | Where-Object { $_.TrimEnd('\') -ieq $part.TrimEnd('\') })) {
      $refreshedParts += $part
    }
  }
  $env:Path = ($refreshedParts -join ';')
}

function Install-WithPackageManager ($displayName, $wingetId, $chocoPackage) {
  $winget = Resolve-Cmd 'winget'
  if ($winget) {
    Say "Installing $displayName with winget"
    $result = Invoke-Native $winget @('install', '-e', '--id', $wingetId, '--silent', '--accept-package-agreements', '--accept-source-agreements')
    if ($result.ExitCode -eq 0) { Refresh-Path; return $true }
    Warn "winget could not install $displayName (exit $($result.ExitCode)); trying Chocolatey if available."
  }

  $choco = Resolve-Cmd 'choco'
  if ($choco) {
    Say "Installing $displayName with Chocolatey"
    $result = Invoke-Native $choco @('install', $chocoPackage, '-y', '--no-progress')
    if ($result.ExitCode -eq 0) { Refresh-Path; return $true }
    Warn "Chocolatey could not install $displayName (exit $($result.ExitCode))."
  }

  return $false
}

function Resolve-CodeCli {
  $cmd = Resolve-Cmd 'code'
  if ($cmd) { return $cmd }

  $candidateRoots = @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
  foreach ($root in $candidateRoots) {
    $candidate = Join-Path $root 'Programs\Microsoft VS Code\bin\code.cmd'
    if ($root -eq $env:ProgramFiles -or $root -eq ${env:ProgramFiles(x86)}) {
      $candidate = Join-Path $root 'Microsoft VS Code\bin\code.cmd'
    }
    if ($candidate -and (Test-Path $candidate)) {
      Add-PathIfExists (Split-Path -Parent $candidate)
      return $candidate
    }
  }

  return $null
}

function Ensure-AzureCli {
  $cmd = Resolve-Cmd 'az'
  if ($cmd) { Ok 'Azure CLI ready'; return $cmd }

  if (-not (Install-WithPackageManager 'Azure CLI' 'Microsoft.AzureCLI' 'azure-cli')) {
    Die 'Azure CLI is required and could not be installed silently. Install it from https://aka.ms/installazurecli and re-run.'
  }

  $cmd = Resolve-Cmd 'az'
  if (-not $cmd) { Die 'Azure CLI installed, but az is still not on PATH. Open a new PowerShell window and re-run.' }
  Ok 'Azure CLI ready'
  return $cmd
}

function Ensure-VsCodeCli {
  $cmd = Resolve-CodeCli
  if ($cmd) { Ok 'VS Code CLI ready'; return $cmd }

  if (-not (Install-WithPackageManager 'Visual Studio Code' 'Microsoft.VisualStudioCode' 'vscode')) {
    Die "VS Code CLI 'code' is required and could not be installed silently. Install VS Code and re-run."
  }

  $cmd = Resolve-CodeCli
  if (-not $cmd) { Die "VS Code installed, but 'code' is still not available. Open VS Code and run 'Shell Command: Install code command in PATH', then re-run." }
  Ok 'VS Code CLI ready'
  return $cmd
}

$AzCmd = Ensure-AzureCli
$CodeCmd = Ensure-VsCodeCli

# Ensure azure-devops extension is installed (idempotent).
$hasExt = & $AzCmd extension show --name azure-devops 2>$null
if (-not $hasExt) {
  Say "Installing 'azure-devops' Azure CLI extension"
  & $AzCmd extension add --name azure-devops --only-show-errors --yes | Out-Null
}

# Confirm signed in.
$account = & $AzCmd account show 2>$null
if (-not $account) {
  Say "Not signed in. Running 'az login'"
  & $AzCmd login --only-show-errors | Out-Null
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("adpai-vsix-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  Say "Downloading $Package@$Version from $Org/$Project/$Feed"
  & $AzCmd artifacts universal download `
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

  Say "Installing $($vsix.Name) into VS Code"
  & $CodeCmd --install-extension $vsix.FullName --force

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
