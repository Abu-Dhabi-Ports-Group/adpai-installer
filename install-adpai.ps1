# AD Ports - install @adports/aidev (Windows PowerShell)
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
#   - Node 18+ (bootstrapped with winget, then Chocolatey fallback when missing)
#   - Your AD Ports identity must have Feed Reader on the adpai feed:
#       https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions

$ErrorActionPreference = 'Stop'

$FeedRegistryHost = '//pkgs.dev.azure.com/abudhabiports/_packaging/adpai/npm/registry/'
$FeedUrl          = "https:$FeedRegistryHost"
$Pkg              = '@adports/aidev'
$Npmrc            = Join-Path $HOME '.npmrc'

function Say  ($m) { Write-Host "> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "OK $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "! $m" -ForegroundColor Yellow }
function Die  ($m) { Write-Host "X $m" -ForegroundColor Red; exit 1 }
function Test-IsTlsInterception ($output) {
  $details = (@($output) | ForEach-Object { "$_" }) -join ' '
  return ($details -match 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY|unable to get local issuer certificate|SELF_SIGNED_CERT_IN_CHAIN|self.signed certificate|CERT_HAS_EXPIRED|ERR_TLS_CERT_ALTNAME_INVALID')
}
function Repair-CorporateTls {
  # Corporate proxies (e.g. Zscaler) re-sign TLS, but Node ships its own CA
  # bundle and does not trust the Windows certificate store by default.
  # Two layers, both needed for full npm coverage (feed + registry.npmjs.org
  # + dependency hosts):
  #   1. NODE_OPTIONS=--use-system-ca  -> Node reads the Windows cert store
  #      directly. Available on Node 22.10+.
  #   2. NODE_EXTRA_CA_CERTS=<bundle>  -> fallback / belt-and-braces: a PEM
  #      file containing every trusted root + intermediate from the Windows
  #      store, used by Node and by npm's own HTTPS client.
  Say 'Ensuring npm/Node trust the Windows corporate TLS chain (NODE_OPTIONS=--use-system-ca + NODE_EXTRA_CA_CERTS=<windows cert bundle>).'

  $existing = [Environment]::GetEnvironmentVariable('NODE_OPTIONS', 'User')
  if ($existing -and ($existing -notmatch '--use-system-ca')) {
    $combined = (($existing -replace '--use-openssl-ca','').Trim() + ' --use-system-ca').Trim()
  } elseif (-not $existing) {
    $combined = '--use-system-ca'
  } else {
    $combined = $existing
  }
  [Environment]::SetEnvironmentVariable('NODE_OPTIONS', $combined, 'User')
  $env:NODE_OPTIONS = $combined

  # Export every trusted root + CA from the Windows store into one PEM bundle.
  # This catches Zscaler AND any intermediate that npmjs.org / dependency CDNs
  # are re-signed under.
  try {
    $bundle = Join-Path $HOME 'adpai-windows-ca-bundle.pem'
    $certs = @(Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root, Cert:\CurrentUser\CA, Cert:\LocalMachine\CA -ErrorAction SilentlyContinue |
      Where-Object { $_.NotAfter -gt (Get-Date) } |
      Sort-Object Thumbprint -Unique)
    if ($certs.Count -gt 0) {
      $blocks = foreach ($cert in $certs) {
        try {
          $b64 = [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
          "-----BEGIN CERTIFICATE-----`n$b64`n-----END CERTIFICATE-----"
        } catch { $null }
      }
      Set-Content -Path $bundle -Value (($blocks | Where-Object { $_ }) -join "`n") -Encoding ascii
      [Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', $bundle, 'User')
      $env:NODE_EXTRA_CA_CERTS = $bundle
      # Belt: also tell npm directly (independent of Node's TLS path).
      $null = Invoke-Native $NpmCmd @('config', 'set', 'cafile', $bundle)
      Ok "Exported $($certs.Count) Windows CA certs to $bundle (NODE_EXTRA_CA_CERTS + npm cafile)."
    } else {
      Warn 'Found no certificates in the Windows trust store to export.'
    }
  } catch {
    Warn "Could not export Windows CA bundle: $($_.Exception.Message)"
  }
}
function Reset-StaleAdpaiInstall {
  # npm 11 fails reify with 'Cannot destructure property package of node.target as it is null'
  # when an earlier partial install left a half-cleaned tree under %APPDATA%\npm\node_modules\@adports\aidev,
  # often because Windows Defender / file indexer holds nested @opentelemetry files open.
  # Wipe the stale tree, kill stray node.exe processes that own a handle inside it, and clear the cache.
  # Every step is wrapped in try/catch so this function can never throw back to the caller;
  # if cleanup fails we just let npm try again and surface its own error.
  $globalRoot = $null
  try {
    $prefixResult = Invoke-Native $NpmCmd @('prefix', '-g')
    if ($prefixResult.ExitCode -eq 0 -and $prefixResult.Output) {
      $globalRoot = ($prefixResult.Output | Select-Object -First 1).ToString().Trim()
    }
  } catch { }
  if (-not $globalRoot) { $globalRoot = Join-Path $env:APPDATA 'npm' }
  $stale = Join-Path $globalRoot 'node_modules\@adports'
  if (Test-Path -LiteralPath $stale) {
    Say 'Cleaning up partial @adports install (silent auto-recovery)'
    # Stop adpai-related node processes that may hold handles on the stale tree.
    # Filter narrowly so we don't kill VS Code / unrelated tools.
    try {
      $stalePattern = [regex]::Escape($stale)
      Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
          $_.CommandLine -and (
            $_.CommandLine -match '@adports' -or
            $_.CommandLine -match $stalePattern
          )
        } |
        ForEach-Object {
          try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
    } catch { }
    # Try several deletion strategies with backoff. Antivirus / search indexer
    # often releases the handle within a second.
    $deleted = $false
    for ($attempt = 1; $attempt -le 4; $attempt++) {
      if (-not (Test-Path -LiteralPath $stale)) { $deleted = $true; break }
      try { & cmd /c "rd /s /q `"$stale`"" 2>$null | Out-Null } catch { }
      if (-not (Test-Path -LiteralPath $stale)) { $deleted = $true; break }
      try { Remove-Item -LiteralPath $stale -Recurse -Force -ErrorAction SilentlyContinue } catch { }
      if (-not (Test-Path -LiteralPath $stale)) { $deleted = $true; break }
      Start-Sleep -Milliseconds (200 * $attempt)
    }
    # Last resort: rename the locked tree out of the way so npm sees an empty slot.
    if (-not $deleted) {
      try {
        $stamp = (Get-Date).ToString('yyyyMMddHHmmss')
        Rename-Item -LiteralPath $stale -NewName "@adports.broken-$stamp" -ErrorAction Stop
        $deleted = $true
      } catch { }
    }
    if (-not $deleted) {
      # Don't escalate to the user yet; npm may still recover, and we have one more
      # install attempt with --force after this. Just note it quietly.
      Warn 'Could not fully clear stale @adports tree; continuing anyway.'
    }
  }
  # npm cache may also contain partial tarballs from the failed reify.
  try {
    $cacheClean = Invoke-Native $NpmCmd @('cache', 'clean', '--force')
    if ($cacheClean.ExitCode -eq 0) { Ok 'npm cache cleaned' }
  } catch { }
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
function Resolve-NpmGlobalCmd ($name) {
  $cmd = Resolve-Cmd $name
  if ($cmd) { return $cmd }

  $prefixResult = Invoke-Native $NpmCmd @('prefix', '-g')
  if ($prefixResult.ExitCode -ne 0 -or -not $prefixResult.Output) { return $null }

  $prefix = ($prefixResult.Output | Select-Object -First 1).ToString().Trim()
  foreach ($candidate in @(
    (Join-Path $prefix "$name.cmd"),
    (Join-Path $prefix "$name.ps1"),
    (Join-Path $prefix $name)
  )) {
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
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

function Ensure-NodeLts {
  $script:NodeCmd = Resolve-Cmd 'node'
  $script:NpmCmd = Resolve-Cmd 'npm'
  $needsInstall = (-not $script:NodeCmd -or -not $script:NpmCmd)

  if (-not $needsInstall) {
    $nodeResult = Invoke-Native $script:NodeCmd @('-v')
    $nodeLine = $nodeResult.Output | Where-Object { $_ -match '^v?\d+\.' } | Select-Object -First 1
    if (-not $nodeLine) { Die "Node.js version output was not recognized: $($nodeResult.Output -join [Environment]::NewLine)" }
    $nodeVer = $nodeLine.ToString().Trim().TrimStart('v')
    $nodeMajor = [int]($nodeVer.Split('.')[0])
    $needsInstall = $nodeMajor -lt 18
  }

  if ($needsInstall) {
    if (-not (Install-WithPackageManager 'Node.js LTS' 'OpenJS.NodeJS.LTS' 'nodejs-lts')) {
      Die 'Node.js 18+ and npm are required and could not be installed silently. Install Node 18+ from https://nodejs.org and re-run.'
    }
    $script:NodeCmd = Resolve-Cmd 'node'
    $script:NpmCmd = Resolve-Cmd 'npm'
  }

  if (-not $script:NodeCmd) { Die 'Node.js not found after bootstrap. Open a new PowerShell window and re-run.' }
  if (-not $script:NpmCmd) { Die 'npm not found after bootstrap. Open a new PowerShell window and re-run.' }
}

# ---------- Node ----------
Say 'Checking Node.js + npm'
Ensure-NodeLts
if ($env:NODE_EXTRA_CA_CERTS -and -not (Test-Path $env:NODE_EXTRA_CA_CERTS)) {
  Warn "NODE_EXTRA_CA_CERTS points to a missing or inaccessible certificate: $env:NODE_EXTRA_CA_CERTS"
  Warn 'The installer will continue, but fix or unset NODE_EXTRA_CA_CERTS if npm TLS access fails.'
}
$nodeResult = Invoke-Native $NodeCmd @('-v')
if ($nodeResult.ExitCode -ne 0 -or -not $nodeResult.Output) { Die "Node.js check failed: $($nodeResult.Output -join [Environment]::NewLine)" }
$npmResult = Invoke-Native $NpmCmd @('-v')
if ($npmResult.ExitCode -ne 0 -or -not $npmResult.Output) { Die "npm check failed: $($npmResult.Output -join [Environment]::NewLine)" }
$nodeLine = $nodeResult.Output | Where-Object { $_ -match '^v?\d+\.' } | Select-Object -First 1
$npmLine = $npmResult.Output | Where-Object { $_ -match '^\d+\.' } | Select-Object -First 1
if (-not $nodeLine) { Die "Node.js version output was not recognized: $($nodeResult.Output -join [Environment]::NewLine)" }
if (-not $npmLine) { Die "npm version output was not recognized: $($npmResult.Output -join [Environment]::NewLine)" }
$nodeVer = $nodeLine.ToString().Trim().TrimStart('v')
$npmVer = $npmLine.ToString().Trim()
$nodeMajor = [int]($nodeVer.Split('.')[0])
if ($nodeMajor -lt 18) { Die "Node $nodeVer detected; need Node 18 or newer." }
Ok "Node v$nodeVer, npm $npmVer"

# ---------- vsts-npm-auth ----------
$VstsNpmAuthCmd = Resolve-Cmd 'vsts-npm-auth'
if (-not $VstsNpmAuthCmd) {
  Say 'Installing vsts-npm-auth (Microsoft Azure Artifacts auth helper)'
  $authInstallResult = Invoke-Native $NpmCmd @('install', '-g', 'vsts-npm-auth')
  if ($authInstallResult.ExitCode -ne 0) {
    Die "Failed to install vsts-npm-auth: $($authInstallResult.Output -join [Environment]::NewLine)"
  }
  $VstsNpmAuthCmd = Resolve-NpmGlobalCmd 'vsts-npm-auth'
  if (-not $VstsNpmAuthCmd) {
    Die 'vsts-npm-auth installed, but its command shim was not found on PATH or in the npm global prefix. Restart PowerShell and re-run this installer.'
  }
}
Ok 'vsts-npm-auth ready'

# ---------- Project-scoped .npmrc for vsts-npm-auth to read ----------
$tempRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$work = Join-Path $tempRoot "adpai-bootstrap-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$projectNpmrc = Join-Path $work '.npmrc'
@(
  "@adports:registry=$FeedUrl"
) | Set-Content -Path $projectNpmrc -Encoding ASCII

# ---------- SSO sign-in ----------
Say 'Running vsts-npm-auth (browser will open for AD Ports SSO)'
Push-Location $work
try {
  $authResult = Invoke-Native $VstsNpmAuthCmd @('-config', $projectNpmrc)
  if ($authResult.ExitCode -ne 0) {
    Die "vsts-npm-auth failed (exit code $($authResult.ExitCode)): $($authResult.Output -join [Environment]::NewLine)"
  }
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
    if ($line -match '^always-auth\s*=') { continue }
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
  }
  $kept | Set-Content -Path $Npmrc -Encoding ASCII
}

# ---------- Verify + install ----------
Say 'Verifying feed access'
$viewResult = Invoke-Native $NpmCmd @('view', $Pkg, 'version')
$ver = $viewResult.Output | Where-Object { $_ -notmatch '^npm warn' -and $_ -match '^\d+\.' } | Select-Object -First 1
if (($viewResult.ExitCode -ne 0 -or -not $ver) -and (Test-IsTlsInterception $viewResult.Output)) {
  Repair-CorporateTls
  Say 'Retrying feed access after TLS auto-fix'
  $viewResult = Invoke-Native $NpmCmd @('view', $Pkg, 'version')
  $ver = $viewResult.Output | Where-Object { $_ -notmatch '^npm warn' -and $_ -match '^\d+\.' } | Select-Object -First 1
}
if ($viewResult.ExitCode -ne 0 -or -not $ver) {
  if (Test-IsTlsInterception $viewResult.Output) {
    Die @"
Feed access failed because Node.js does not trust the corporate TLS root (Zscaler).
The auto-fix did not stick. Run these two lines in PowerShell, then re-run the installer:

    [Environment]::SetEnvironmentVariable('NODE_OPTIONS','--use-system-ca','User')
    # close ALL PowerShell windows, open a fresh one, then:
    iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex

npm output:
$($viewResult.Output -join [Environment]::NewLine)
"@
  }
  Die @"
Feed access failed. Most likely: your AD Ports identity is missing 'Feed Reader' on the adpai feed.
Ask the admin to grant access at:
https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions

npm output:
$($viewResult.Output -join [Environment]::NewLine)
"@
}
Ok "Feed reachable - latest $Pkg = $ver"

Say "Installing $Pkg globally (2-5 minutes is normal on corporate networks)"
# Ensure npm dependency fetches from registry.npmjs.org trust corporate TLS
# inspection before the first install attempt. Feed auth success only proves the
# Azure Artifacts token works; public dependencies use a different TLS chain.
Repair-CorporateTls
# Stream npm output live (no pipe / no Tee, those buffer the npm http fetch lines).
$oldErrorActionPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  & $NpmCmd install -g $Pkg --no-fund --no-audit --loglevel=http
  $installExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $oldErrorActionPreference
}

if ($installExit -ne 0) {
  # Could be corporate TLS interception on registry.npmjs.org / dep CDNs,
  # OR a stale half-installed @adports tree from a prior aborted run
  # (npm 11 surfaces this as 'Cannot destructure property package of node.target as it is null'
  # plus EPERM rmdir warnings on nested @opentelemetry directories).
  # Both fixes are idempotent and quick, so just run them and retry once.
  Warn "npm install failed (exit $installExit). Attempting silent auto-fix and one retry."
  Repair-CorporateTls
  Reset-StaleAdpaiInstall
  Say "Retrying $Pkg install with --force (overwrites any leftover state)."
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $NpmCmd install -g $Pkg --no-fund --no-audit --force --loglevel=http
    $installExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

if ($installExit -ne 0) {
  # Attempt 3: --install-strategy=nested sidesteps the npm 11 'reify cleanup' phase
  # entirely (npm v6-style nested node_modules) — the cleanup is where the
  # 'Cannot destructure property package of node.target as it is null' bug fires.
  Warn 'Second attempt failed. Trying nested install strategy (silent).'
  Reset-StaleAdpaiInstall
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $NpmCmd install -g $Pkg --no-fund --no-audit --force --legacy-peer-deps --install-strategy=nested --loglevel=http
    $installExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

if ($installExit -ne 0) {
  # Attempt 4 (final silent fallback): npm 11.13 has a confirmed reify bug on this
  # @grpc/@opentelemetry tree. npm 10 uses a different reify path that handles it.
  # Install npm@10 (one isolated package install — does NOT trigger the same bug),
  # then retry @adports/aidev. Leaves the user on npm 10, which is fully supported.
  Warn 'Third attempt failed (npm 11 reify bug). Falling back to npm 10 (silent).'
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $NpmCmd install -g npm@10 --no-fund --no-audit --loglevel=error 2>&1 | Out-Null
    $downgradeExit = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
  if ($downgradeExit -eq 0) {
    # The npm shim under %APPDATA%\npm now points at npm 10. Re-resolve so we use it.
    $resolved = Resolve-Cmd 'npm'
    if ($resolved) { $NpmCmd = $resolved }
    Reset-StaleAdpaiInstall
    Say "Retrying $Pkg install with npm 10..."
    $oldErrorActionPreference = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      & $NpmCmd install -g $Pkg --no-fund --no-audit --loglevel=http
      $installExit = $LASTEXITCODE
    } finally {
      $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($installExit -eq 0) {
      Ok 'Installed via npm 10 fallback. (Your global npm is now pinned to v10; run ''npm install -g npm@latest'' to return to npm 11 if desired.)'
    }
  } else {
    Warn 'Could not install npm@10 either.'
  }
}

if ($installExit -ne 0) {
  Die @"
Failed to install $Pkg globally after 4 attempts (npm exit $installExit).

This is npm 11's 'node.target is null' reify bug, triggered when Windows Defender
or a search indexer briefly locks files inside the deeply nested @opentelemetry tree.

Try these one at a time:

  1. Run PowerShell as Administrator and re-run the installer:
         iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex

  2. Exclude the global npm folder from Windows Defender real-time scanning,
     then re-run the installer:
         Add-MpPreference -ExclusionPath \"$env:APPDATA\npm\"

  3. Manually downgrade to npm 10 and retry:
         npm install -g npm@10
         npm install -g $Pkg

Full diagnostic log:
         npm install -g $Pkg --loglevel=verbose
"@
}
$AdpaiCmd = Resolve-NpmGlobalCmd 'adpai'
if ($AdpaiCmd) {
  $installedResult = Invoke-Native $AdpaiCmd @('--version')
  if ($installedResult.ExitCode -eq 0) {
    $installed = $installedResult.Output | Where-Object { $_ -notmatch '^npm warn' } | Select-Object -First 1
  }
}
if (-not $installed) {
  $installed = "$Pkg@$ver"
  Warn 'adpai was installed, but the command is not on this PowerShell PATH yet. Open a new PowerShell window if adpai is not recognized.'
}
Ok "Installed: $installed"

# ---------- Done ----------
Write-Host ''
Ok 'Setup complete. Try:'
Write-Host '    adpai --help'
Write-Host '    adpai -y --preset backend-nestjs --tools claude'
Write-Host ''
Write-Host 'The vsts-npm-auth refresh token lasts ~90 days and renews automatically.'
