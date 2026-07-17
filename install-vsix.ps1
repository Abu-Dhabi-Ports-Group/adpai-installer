# Install the latest ADP AI SDLC VS Code extension from the
# Azure Artifacts Universal feed (Foundations / adpai-vsix).
#
# Prerequisites are checked before install, but not silently installed:
#   1. Azure CLI        (az)
#   2. VS Code CLI      (code)
#   3. DevOps extension (az extension add --name azure-devops)
#   4. Sign in          (az login, interactive when required, including Azure DevOps scope)
# The @adports/aidev CLI bootstrap still runs automatically unless -SkipCli is set.
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
function Die  ($m) { Write-Host "X  $m" -ForegroundColor Red; throw $m }

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

function Export-CertificatesToPem ($certificates, $path) {
  $pemBlocks = foreach ($certificate in $certificates) {
    try {
      $bytes = $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
      $base64 = [Convert]::ToBase64String($bytes, [Base64FormattingOptions]::InsertLineBreaks)
      "-----BEGIN CERTIFICATE-----`n$base64`n-----END CERTIFICATE-----"
    } catch {
      $null
    }
  }
  Set-Content -Path $path -Value (($pemBlocks | Where-Object { $_ }) -join "`n") -Encoding ascii
}

function Enable-AzureCliCorporateCa ([switch]$Force) {
  $bundleDir = Join-Path $env:USERPROFILE '.azure'
  $bundlePath = Join-Path $bundleDir 'adpai-windows-ca-bundle.pem'
  $isLegacyAdpaiBundle = $env:REQUESTS_CA_BUNDLE -and ([IO.Path]::GetFileName($env:REQUESTS_CA_BUNDLE) -ieq 'adpai-zscaler-root-ca.pem')

  if (-not $Force -and $env:REQUESTS_CA_BUNDLE -and (Test-Path $env:REQUESTS_CA_BUNDLE) -and -not $isLegacyAdpaiBundle) {
    Ok "Azure CLI CA bundle already set: $env:REQUESTS_CA_BUNDLE"
    $env:CURL_CA_BUNDLE = $env:REQUESTS_CA_BUNDLE
    return $true
  }

  $certificates = @(Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root, Cert:\CurrentUser\CA, Cert:\LocalMachine\CA -ErrorAction SilentlyContinue |
    Where-Object { $_.NotAfter -gt (Get-Date) } |
    Sort-Object Thumbprint -Unique)

  if (-not $certificates -or $certificates.Count -eq 0) {
    if ($env:REQUESTS_CA_BUNDLE -and (Test-Path $env:REQUESTS_CA_BUNDLE)) {
      Ok "Azure CLI CA bundle already set: $env:REQUESTS_CA_BUNDLE"
      $env:CURL_CA_BUNDLE = $env:REQUESTS_CA_BUNDLE
      return $true
    }
    return $false
  }

  New-Item -ItemType Directory -Force -Path $bundleDir | Out-Null
  Export-CertificatesToPem $certificates $bundlePath

  # Process scope: take effect immediately for this run.
  $env:REQUESTS_CA_BUNDLE = $bundlePath
  $env:CURL_CA_BUNDLE     = $bundlePath
  $env:NODE_EXTRA_CA_CERTS = $bundlePath
  $env:SSL_CERT_FILE      = $bundlePath

  # User scope: persist so re-runs and child tools (VS Code, extensions) trust the bundle.
  try {
    [Environment]::SetEnvironmentVariable('REQUESTS_CA_BUNDLE',  $bundlePath, 'User')
    [Environment]::SetEnvironmentVariable('CURL_CA_BUNDLE',      $bundlePath, 'User')
    [Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', $bundlePath, 'User')
    [Environment]::SetEnvironmentVariable('SSL_CERT_FILE',       $bundlePath, 'User')
  } catch { }

  Ok "Exported $($certificates.Count) Windows CA certs to $bundlePath (REQUESTS_CA_BUNDLE + CURL_CA_BUNDLE + NODE_EXTRA_CA_CERTS + SSL_CERT_FILE, persisted to user env)."
  return $true
}

function Enable-AzureCliDefaultCertStore ($azCmd) {
  $result = Invoke-Native $azCmd @('config', 'set', 'core.use_default_cert_store=true', '--only-show-errors')
  if ($result.ExitCode -ne 0) { return $false }

  Ok 'Azure CLI configured to use the Windows/default certificate store'
  return $true
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

function Install-VsixIntoVsCode ($codeCmd, $vsixPath) {
  # `code` is an Electron binary. When this installer runs from a context that
  # inherited ELECTRON_RUN_AS_NODE / VSCODE_* env vars (VS Code's integrated
  # terminal, the extension's own updater terminal, or any Electron-spawned
  # parent), `code --install-extension` aborts with
  #   [ERROR:icu_util.cc] Invalid file descriptor to ICU data received.
  # Clear those variables for the child `code` process so the CLI launches
  # cleanly, then restore them afterwards.
  $electronVars = @(
    'ELECTRON_RUN_AS_NODE', 'ELECTRON_NO_ATTACH_CONSOLE', 'ELECTRON_NO_ASAR',
    'ELECTRON_FORCE_IS_PACKAGED', 'VSCODE_PID', 'VSCODE_CWD', 'VSCODE_IPC_HOOK',
    'VSCODE_IPC_HOOK_CLI', 'VSCODE_NLS_CONFIG', 'VSCODE_CODE_CACHE_PATH',
    'VSCODE_ESM_ENTRYPOINT', 'VSCODE_HANDLES_UNCAUGHT_ERRORS',
    'VSCODE_L10N_BUNDLE_LOCATION', 'VSCODE_CRASH_REPORTER_PROCESS_TYPE'
  )
  $saved = @{}
  foreach ($v in $electronVars) {
    $saved[$v] = [Environment]::GetEnvironmentVariable($v, 'Process')
    if ($null -ne $saved[$v]) { Remove-Item "Env:$v" -ErrorAction SilentlyContinue }
  }
  try {
    return Invoke-Native $codeCmd @('--install-extension', $vsixPath, '--force')
  } finally {
    foreach ($v in $electronVars) {
      if ($null -ne $saved[$v]) { [Environment]::SetEnvironmentVariable($v, $saved[$v], 'Process') }
    }
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
    if ($login.ExitCode -ne 0 -and (Test-IsCertificateError $login.Output)) {
      Enable-AzureCliCorporateCa -Force | Out-Null
      Enable-AzureCliDefaultCertStore $azCmd | Out-Null
      Say "Retrying Azure DevOps scoped login with Windows CA bundle"
      $login = Invoke-Native $azCmd @('login', '--scope', '499b84ac-1321-427f-aa17-267ca6975798/.default', '--only-show-errors')
    }
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

  Die @(
    "Azure CLI ('az') is required before this installer can download the private VSIX.",
    'Install Azure CLI using your corporate Software Center / Company Portal, or ask IT to deploy it.',
    'If your workstation allows user-scope winget installs, you can try:',
    '    winget install -e --id Microsoft.AzureCLI --scope user',
    'Official install guidance:',
    '    https://aka.ms/installazurecli',
    'After installing, open a new normal PowerShell window and verify:',
    '    az version',
    'Then rerun this installer.'
  ) -join [Environment]::NewLine
}

function Ensure-VsCodeCli {
  $cmd = Resolve-CodeCli
  if ($cmd) { Ok 'VS Code CLI ready'; return $cmd }

  Die @(
    "VS Code CLI ('code') is required before this installer can install the VSIX.",
    'Install Visual Studio Code using your corporate Software Center / Company Portal, or ask IT to deploy it.',
    'If your workstation allows user-scope winget installs, you can try:',
    '    winget install -e --id Microsoft.VisualStudioCode --scope user',
    'If VS Code is already installed, close and reopen PowerShell so PATH refreshes, then verify:',
    '    code --version',
    'Then rerun this installer.'
  ) -join [Environment]::NewLine
}

function Ensure-AzureDevOpsExtension ($azCmd) {
  $extCheck = Invoke-Native $azCmd @('extension', 'list', '--query', "[?name=='azure-devops'].name", '-o', 'tsv')
  $extNames = @($extCheck.Output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  if ($extCheck.ExitCode -eq 0 -and ($extNames -contains 'azure-devops')) {
    Ok "Azure CLI extension 'azure-devops' ready"
    return
  }

  $details = (@($extCheck.Output) | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' '
  if (-not $details) { $details = "Azure CLI extension 'azure-devops' is not installed." }

  Die @(
    "Azure CLI extension 'azure-devops' is required before this installer can download the private VSIX.",
    "Details: $details",
    'Install it in a normal PowerShell window, then rerun this installer:',
    '    az extension add --name azure-devops --only-show-errors',
    'If corporate TLS inspection blocks the install, run:',
    '    az config set core.use_default_cert_store=true',
    '    az extension add --name azure-devops --only-show-errors'
  ) -join [Environment]::NewLine
}

function Resolve-PowerShellHost {
  $exeName = if ($env:OS -eq 'Windows_NT') {
    if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
  } else {
    'pwsh'
  }
  $currentHost = Join-Path $PSHOME $exeName
  if (Test-Path $currentHost) { return $currentHost }

  $cmd = Resolve-Cmd 'pwsh'
  if ($cmd) { return $cmd }
  return (Resolve-Cmd 'powershell')
}

function Invoke-AdpaiCliBootstrap {
  $powerShellCmd = Resolve-PowerShellHost
  if (-not $powerShellCmd) {
    Warn "Could not find a PowerShell host to run the CLI bootstrap. Run it manually: iwr -useb $CliInstallerUrl | iex"
    return 1
  }

  $cliScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("install-adpai-" + [System.Guid]::NewGuid() + ".ps1")
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $CliInstallerUrl -OutFile $cliScriptPath
    $arguments = @('-NoProfile')
    if ($env:OS -eq 'Windows_NT') {
      $arguments += @('-ExecutionPolicy', 'Bypass')
    }
    $arguments += @('-File', $cliScriptPath)
    # Pipe the inner script's output to Out-Host so it doesn't pollute this
    # function's return value. Without this, pnpm progress / npm http lines get
    # captured into the output stream and $cliExit becomes an array like
    # @(...output..., 0), which trips 'if ($cliExit -ne 0)' as truthy.
    & $powerShellCmd @arguments 2>&1 | Out-Host
    return $LASTEXITCODE
  } catch {
    Warn "CLI bootstrap failed: $($_.Exception.Message)"
    return 1
  } finally {
    Remove-Item -Force -Path $cliScriptPath -ErrorAction SilentlyContinue
  }
}

$AzCmd = Ensure-AzureCli
$CodeCmd = Ensure-VsCodeCli

# Proactively trust the corporate TLS chain (Zscaler etc.) before any az call.
Enable-AzureCliCorporateCa | Out-Null

if (Test-IsAdministrator) {
  Warn 'Running as Administrator is not recommended. Azure CLI extensions are installed per user and can fail with profile or ownership errors. Use a normal PowerShell window unless a prerequisite installer explicitly asks for elevation.'
}

Ensure-AzureDevOpsExtension $AzCmd

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
  Say "Downloading $Package@$Version from $Org/$Project/$Feed (a few MB; progress is shown below)"
  # Stream az output directly so the user sees download progress instead of a stalled prompt.
  & $AzCmd artifacts universal download `
    --organization $Org `
    --project $Project `
    --scope project `
    --feed $Feed `
    --name $Package `
    --version $Version `
    --path $tmp
  $downloadExit = $LASTEXITCODE
  if ($downloadExit -ne 0) {
    Die "Could not download $Package@$Version from $Org/$Project/$Feed (az exit $downloadExit). Check the output above for the specific error."
  }

  $vsix = Get-ChildItem -Path $tmp -Filter '*.vsix' -File | Select-Object -First 1
  if (-not $vsix) {
    Get-ChildItem -Path $tmp | Out-Host
    Die "No .vsix found in downloaded package."
  }

  # Refuse to install a version that we know crashes at activate() so that the
  # default 'iwr | iex' one-liner never silently leaves a user with a broken
  # extension. 1.1.122 - 1.1.124 ship with the bundled-recommender
  # import.meta.url crash; the fix lands in 2.1.2 and later. The user can
  # still opt in explicitly by passing -Version.
  $brokenVersions = @('1.1.122', '1.1.123', '1.1.124')
  if ($Version -eq '*' -and ($vsix.BaseName -split '-' | Select-Object -Last 1) -in $brokenVersions) {
    $badVersion = ($vsix.BaseName -split '-' | Select-Object -Last 1)
    Die @"
The latest published version ($($vsix.Name)) has a known activation crash that
disables Sign In and every command. Refusing to install it automatically.

Recommended actions, in order:

  1. Install the last known-good 1.x release (works today):
       iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.ps1 -OutFile install-vsix.ps1
       pwsh ./install-vsix.ps1 -Version 1.1.121

  2. If a fixed 2.x has been published since this script was written, install
     it explicitly with -Version 2.1.3 (or later).

  3. Or use the direct GitHub VSIX fallback:
       iwr -useb https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/raw/main/adp-ai-sdlc-latest.vsix ``
         -OutFile `$env:TEMP\adp-ai-sdlc-latest.vsix
       code --install-extension `$env:TEMP\adp-ai-sdlc-latest.vsix --force

To override this guard anyway, request the broken version explicitly with
-Version $badVersion.
"@
  }

  Say "Installing $($vsix.Name) into VS Code"
  $install = Install-VsixIntoVsCode $CodeCmd $vsix.FullName

  # `code --install-extension` can print the ICU stderr line (and even exit
  # non-zero) while the extension is or is not actually installed, so confirm
  # by listing installed extensions rather than trusting the exit code alone.
  $listed = Invoke-Native $CodeCmd @('--list-extensions', '--show-versions')
  $installed = ($listed.ExitCode -eq 0) -and (($listed.Output -join "`n") -match 'adports\.adp-ai-sdlc')

  if ($installed) {
    Ok "Extension installed: $($vsix.Name)"
  }
  else {
    $icu = ($install.Output -join "`n") -match 'Invalid file descriptor to ICU data'
    $stableVsix = Join-Path $env:TEMP $vsix.Name
    try { if ($vsix.FullName -ne $stableVsix) { Copy-Item $vsix.FullName $stableVsix -Force } } catch { $stableVsix = $vsix.FullName }
    Write-Warning ("VS Code CLI install did not complete" + $(if ($icu) { " (the 'code' CLI hit the ICU data-descriptor error)." } else { "." }))
    Write-Host ""
    Write-Host "   Install it via the VS Code UI instead (no 'code' CLI, avoids the ICU error):"
    Write-Host "     1. In VS Code: Ctrl+Shift+P -> 'Extensions: Install from VSIX...'"
    Write-Host "     2. Select: $stableVsix"
    Write-Host "     3. Ctrl+Shift+P -> 'Developer: Reload Window'"
  }

  if (-not $SkipCli) {
    Write-Host ""
    Write-Host ">> Bootstrapping @adports/aidev CLI ..."
    $cliExit = Invoke-AdpaiCliBootstrap
    if ($cliExit -ne 0) {
      Write-Warning "CLI bootstrap failed or was cancelled (exit $cliExit)."
      Write-Warning "The VS Code extension install may still be complete. To retry CLI setup later: iwr -useb $CliInstallerUrl | iex"
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
