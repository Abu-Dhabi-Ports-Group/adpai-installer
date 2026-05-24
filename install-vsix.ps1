# Install the latest ADP AI SDLC VS Code extension from the
# Azure Artifacts Universal feed (Foundations / adpai-vsix).
#
# Prerequisites are bootstrapped when possible:
#   1. Azure CLI        (winget, then Chocolatey fallback)
#   2. VS Code CLI      (winget, then Chocolatey fallback)
#   3. DevOps extension (az extension add --name azure-devops)
#   4. Sign in          (az login, interactive when required, including Azure DevOps scope)
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
function Die  ($m) { throw "ERROR $m" }

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsCertificateError ($output) {
  $details = (@($output) | ForEach-Object { "$_" }) -join ' '
  return ($details -match 'CERTIFICATE_VERIFY_FAILED|SSLCertVerificationError|unable to get local issuer certificate')
}

function Test-IsAzureDevOpsAuthError ($output) {
  $details = (@($output) | ForEach-Object { "$_" }) -join ' '
  return ($details -match 'Before you can run Azure DevOps commands|az devops login|setup credentials|VS30063|TF400813|Unauthorized|401')
}

function Export-CertificateToPem ($certificate, $path) {
  $bytes = $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
  $base64 = [Convert]::ToBase64String($bytes, [Base64FormattingOptions]::InsertLineBreaks)
  $pem = "-----BEGIN CERTIFICATE-----`n$base64`n-----END CERTIFICATE-----`n"
  Set-Content -Path $path -Value $pem -Encoding ascii
}

function Enable-AzureCliCorporateCa {
  if ($env:REQUESTS_CA_BUNDLE -and (Test-Path $env:REQUESTS_CA_BUNDLE)) {
    Ok "Azure CLI CA bundle already set: $env:REQUESTS_CA_BUNDLE"
    $env:CURL_CA_BUNDLE = $env:REQUESTS_CA_BUNDLE
    return $true
  }

  $cert = Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root, Cert:\CurrentUser\CA, Cert:\LocalMachine\CA -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -match 'Zscaler' -or $_.Issuer -match 'Zscaler' -or $_.FriendlyName -match 'Zscaler' } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

  if (-not $cert) { return $false }

  $bundleDir = Join-Path $env:USERPROFILE '.azure'
  New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
  $bundlePath = Join-Path $bundleDir 'adpai-zscaler-root-ca.pem'
  Export-CertificateToPem $cert $bundlePath
  $env:REQUESTS_CA_BUNDLE = $bundlePath
  $env:CURL_CA_BUNDLE = $bundlePath
  Ok "Azure CLI CA bundle set from Windows certificate store: $bundlePath"
  return $true
}

function Enable-AzureCliDefaultCertStore ($azCmd) {
  $result = Invoke-Native $azCmd @('config', 'set', 'core.use_default_cert_store=true', '--only-show-errors')
  if ($result.ExitCode -ne 0) { return $false }

  Ok 'Azure CLI configured to use the Windows/default certificate store'
  return $true
}

function Install-AzureDevOpsExtensionFromLocalWheel ($azCmd) {
  $indexUri = 'https://aka.ms/azure-cli-extension-index-v1'
  $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("adpai-azext-" + [System.Guid]::NewGuid())
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

  try {
    Say "Downloading Azure DevOps Azure CLI extension metadata with PowerShell"
    $index = Invoke-RestMethod -UseBasicParsing -Uri $indexUri
    $entries = @($index.extensions.'azure-devops')
    if ($entries.Count -eq 0) { return $false }

    $entry = $entries |
      Sort-Object @{ Expression = { [version]$_.metadata.version }; Descending = $true } |
      Select-Object -First 1
    if (-not $entry.downloadUrl -or -not $entry.filename) { return $false }

    $wheel = Join-Path $tmpDir $entry.filename
    Say "Downloading $($entry.filename) with PowerShell"
    Invoke-WebRequest -UseBasicParsing -Uri $entry.downloadUrl -OutFile $wheel

    if ($entry.sha256Digest) {
      $actualHash = (Get-FileHash -Algorithm SHA256 -Path $wheel).Hash.ToLowerInvariant()
      if ($actualHash -ne $entry.sha256Digest.ToLowerInvariant()) {
        Warn "Downloaded extension hash did not match the Azure CLI index; skipping local wheel fallback."
        return $false
      }
    }

    Say "Installing 'azure-devops' Azure CLI extension from local wheel"
    $install = Invoke-Native $azCmd @('extension', 'add', '--source', $wheel, '--yes', '--only-show-errors')
    return ($install.ExitCode -eq 0)
  } catch {
    Warn "PowerShell local wheel fallback failed: $($_.Exception.Message)"
    return $false
  } finally {
    Remove-Item -Recurse -Force -Path $tmpDir -ErrorAction SilentlyContinue
  }
}

function Get-AzureDevOpsExtensionInstallHelp ($output) {
  $details = (@($output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' '
  if (-not $details) { $details = 'az extension add returned a non-zero exit code.' }

  if (Test-IsCertificateError $output) {
    return @(
      "Could not install Azure CLI extension 'azure-devops' because Azure CLI does not trust the corporate TLS inspection certificate.",
      "Details: $details",
      'Zscaler recovery:',
      '1. Open a normal PowerShell window as the same Windows user, not Administrator.',
      '2. Ask IT/security for the Zscaler root CA certificate in PEM/Base64 format, or export it from certmgr.msc.',
      '3. Preferred Windows fix: az config set core.use_default_cert_store=true',
      '4. Alternative: download the azure-devops .whl with PowerShell from https://aka.ms/azure-cli-extension-index-v1 and install it with az extension add --source <wheel>.',
      '5. If using a PEM file instead, save it for example as: $env:USERPROFILE\.azure\zscaler-root-ca.pem',
      '6. Run: $env:REQUESTS_CA_BUNDLE="$env:USERPROFILE\.azure\zscaler-root-ca.pem"',
      '7. Run: $env:CURL_CA_BUNDLE=$env:REQUESTS_CA_BUNDLE',
      '8. Run: az extension add --name azure-devops --only-show-errors',
      '9. Rerun this installer.'
    ) -join [Environment]::NewLine
  }

  return @(
    "Could not install Azure CLI extension 'azure-devops'.",
    "Details: $details",
    'Recovery:',
    '1. Close this Administrator PowerShell window and open a normal PowerShell as the same Windows user.',
    '2. Run: az extension add --name azure-devops --only-show-errors',
    '3. If Azure CLI reports azext_metadata.json is owned by another account, run:',
    '   Remove-Item -Recurse -Force "$env:USERPROFILE\.azure\cliextensions\azure-devops"',
    '   Then run step 2 again and rerun this installer.'
  ) -join [Environment]::NewLine
}

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

function Ensure-AzureDevOpsAuth ($azCmd, $organizationUrl, $project) {
  Enable-AzureCliCorporateCa | Out-Null

  Invoke-Native $azCmd @(
    'devops', 'configure',
    '--defaults', "organization=$organizationUrl", "project=$project",
    '--only-show-errors'
  ) | Out-Null

  $probe = Invoke-Native $azCmd @(
    'devops', 'project', 'show',
    '--organization', $organizationUrl,
    '--project', $project,
    '-o', 'none',
    '--only-show-errors'
  )
  if ($probe.ExitCode -eq 0) { return }

  if (Test-IsAzureDevOpsAuthError $probe.Output) {
    Say "Azure DevOps sign-in required. Running 'az login' with Azure DevOps scope"
    $login = Invoke-Native $azCmd @('login', '--scope', '499b84ac-1321-427f-aa17-267ca6975798/.default', '--only-show-errors')
    if ($login.ExitCode -ne 0) { Die "Azure DevOps scoped login failed. $($login.Output -join ' ')" }

    $probe = Invoke-Native $azCmd @(
      'devops', 'project', 'show',
      '--organization', $organizationUrl,
      '--project', $project,
      '-o', 'none',
      '--only-show-errors'
    )
    if ($probe.ExitCode -eq 0) { return }
  }

  Die "Azure DevOps authentication failed for $organizationUrl/$project. Run 'az login --scope 499b84ac-1321-427f-aa17-267ca6975798/.default' or 'az devops login', then rerun this installer. $($probe.Output -join ' ')"
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

if (Test-IsAdministrator) {
  Warn 'Running as Administrator is not recommended. Azure CLI extensions are installed per user and can fail with profile or ownership errors. Use a normal PowerShell window unless a prerequisite installer explicitly asks for elevation.'
}

# Ensure azure-devops extension is installed (idempotent).
$extCheck = Invoke-Native $AzCmd @('extension', 'list', '--query', "[?name=='azure-devops'].name", '-o', 'tsv')
$extNames = @($extCheck.Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
if ($extCheck.ExitCode -ne 0 -or -not ($extNames -contains 'azure-devops')) {
  Say "Installing 'azure-devops' Azure CLI extension"
  $addExt = Invoke-Native $AzCmd @('extension', 'add', '--name', 'azure-devops', '--only-show-errors', '--yes')
  if ($addExt.ExitCode -ne 0 -and (Test-IsCertificateError $addExt.Output) -and (Enable-AzureCliCorporateCa)) {
    Say "Retrying 'azure-devops' Azure CLI extension install with corporate CA bundle"
    $addExt = Invoke-Native $AzCmd @('extension', 'add', '--name', 'azure-devops', '--only-show-errors', '--yes')
  }
  if ($addExt.ExitCode -ne 0 -and (Test-IsCertificateError $addExt.Output) -and (Enable-AzureCliDefaultCertStore $AzCmd)) {
    Say "Retrying 'azure-devops' Azure CLI extension install with Windows/default certificate store"
    $addExt = Invoke-Native $AzCmd @('extension', 'add', '--name', 'azure-devops', '--only-show-errors', '--yes')
  }
  if ($addExt.ExitCode -ne 0 -and (Test-IsCertificateError $addExt.Output) -and (Install-AzureDevOpsExtensionFromLocalWheel $AzCmd)) {
    $addExt = Invoke-Native $AzCmd @('extension', 'show', '--name', 'azure-devops', '--only-show-errors')
  }
  if ($addExt.ExitCode -ne 0) { Die (Get-AzureDevOpsExtensionInstallHelp $addExt.Output) }
}

# Confirm signed in.
$account = Invoke-Native $AzCmd @('account', 'show', '-o', 'none')
if ($account.ExitCode -ne 0) {
  Say "Not signed in. Running 'az login'"
  $login = Invoke-Native $AzCmd @('login', '--only-show-errors')
  if ($login.ExitCode -ne 0) { Die "Azure login failed. $($login.Output -join ' ')" }
}

Ensure-AzureDevOpsAuth $AzCmd $Org $Project

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("adpai-vsix-" + [System.Guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  Enable-AzureCliCorporateCa | Out-Null
  Say "Downloading $Package@$Version from $Org/$Project/$Feed"
  $download = Invoke-Native $AzCmd @(
    'artifacts', 'universal', 'download',
    '--organization', $Org,
    '--project', $Project,
    '--scope', 'project',
    '--feed', $Feed,
    '--name', $Package,
    '--version', $Version,
    '--path', $tmp,
    '--only-show-errors'
  )
  if ($download.ExitCode -ne 0) {
    Die "Could not download $Package@$Version from $Org/$Project/$Feed. $($download.Output -join ' ')"
  }

  $vsix = Get-ChildItem -Path $tmp -Filter '*.vsix' -File | Select-Object -First 1
  if (-not $vsix) {
    Get-ChildItem -Path $tmp | Out-Host
    Die "No .vsix found in downloaded package."
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
