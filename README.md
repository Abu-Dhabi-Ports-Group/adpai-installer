# adpai-installer

Public bootstrap installers for the AD Ports SDLC AI tooling:

- [`@adports/aidev`](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/Npm/@adports%2Faidev/overview) — the CLI catalog scaffolder
- [`adports.adp-ai-sdlc`](https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix) — the VS Code extension
- `adp-ai-sdlc-codex` — the Codex Desktop plugin (hosted plugin server)
- `adp-ai-sdlc-claude` — the Claude Code plugin (same server, separate marketplace)

These scripts are mirrored from [`ai-skills/catalog/public-installers/`](https://dev.azure.com/abudhabiports/Foundations/_git/ai-skills?path=/catalog/public-installers). The source of truth is `ai-skills`; do not edit files in this repo directly.

## Install everything in one go

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-all.sh | bash
```

Windows (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-all.ps1 | iex
```

`install-all` installs the CLI + VS Code extension unconditionally, then installs the Codex plugin if the `codex` CLI is present and the Claude plugin if the `claude` CLI is present. Missing host CLIs are skipped with a warning; failures in the optional plugin steps do **not** block the overall install.

## ADP AI CLI (`@adports/aidev`)

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.sh | bash
```

Windows (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex
```

## ADP AI VS Code Extension (`adports.adp-ai-sdlc`)

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.sh | bash
```

Windows (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.ps1 | iex
```

### Direct VSIX download fallback

If the installer command is blocked by Azure CLI, corporate TLS, or Azure Artifacts access issues, download the latest VSIX directly from GitHub and install it with the VS Code CLI:

```powershell
iwr -useb https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/raw/main/adp-ai-sdlc-latest.vsix -OutFile adp-ai-sdlc-latest.vsix
code --install-extension .\adp-ai-sdlc-latest.vsix --force
```

GitHub direct download works:

- Latest VSIX: https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/raw/main/adp-ai-sdlc-latest.vsix
- Versioned VSIX: https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/raw/main/adp-ai-sdlc-1.1.69.vsix
- Verified local install: `adports.adp-ai-sdlc@1.1.69`

After downloading the `.vsix`, double-click may open VS Code and start installation if Windows has `.vsix` associated with VS Code. The most reliable install path is: in VS Code, open **Extensions**, choose **Install from VSIX...**, and select the downloaded file. You can also run `code --install-extension .\adp-ai-sdlc-latest.vsix --force` from PowerShell in the download folder.

The direct VSIX installs only the VS Code extension. Run the CLI installer separately if you also need `adpai` on the command line:

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.sh | bash -s -- 2.0.1
```

```powershell
$script = iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.ps1
Invoke-Expression "$($script.Content); & { param([string]`$Version='2.0.1') }"
# or save and run: iwr ... -OutFile install-vsix.ps1; pwsh install-vsix.ps1 -Version 2.0.1
```

### What the VSIX installer does

1. Checks Azure CLI (`az`) and stops with manual install instructions if it is missing.
2. Checks the VS Code CLI (`code`) and stops with manual install instructions if it is missing.
3. Checks the `azure-devops` extension for Azure CLI and stops with manual install instructions if it is missing.
4. Runs `az login` if no active session.
5. Downloads the requested VSIX from the private `adpai-vsix` Azure Artifacts Universal feed.
6. Runs `code --install-extension <vsix> --force`.
7. Bootstraps the `@adports/aidev` CLI by chaining `install-adpai.{sh,ps1}` in a child PowerShell process (skip with `--skip-cli` / `-SkipCli`).

The Windows VSIX installer does not silently install Azure CLI, VS Code, or Chocolatey. If a prerequisite is missing, install it through Company Portal / Software Center or an approved user-scope installer, then rerun the one-liner.

The user must have **Feed Reader** on both the [`adpai-vsix` feed](https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix/settings/permissions) (VSIX) and the [`adpai` feed](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions) (CLI). The scripts contain no secrets.

## Codex Desktop plugin (`adp-ai-sdlc-codex`)

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.sh | bash
```

Windows (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.ps1 | iex
```

Requires Codex Desktop and its `codex` CLI on PATH. The installer registers the AD Ports marketplace URL and installs the plugin; sign-in happens in the Codex Desktop UI on first use (uses your existing AD Ports Microsoft account — no PAT, no secrets in this script).

## Claude Code plugin (`adp-ai-sdlc-claude`)

Mac / Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-claude-plugin.sh | bash
```

Windows (PowerShell):

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-claude-plugin.ps1 | iex
```

Requires Claude Code and its `claude` CLI on PATH. The installer prints the two `/plugin` commands to run inside any Claude Code session to register and install the plugin.

## What the CLI installer does

1. Verify Node 18+ (bootstrap with `winget`/Chocolatey on Windows, offer `brew`/`apt` on macOS/Linux).
2. Authenticate the user to the private adpai Azure Artifacts feed via SSO.
3. Write feed credentials to `~/.npmrc`.
4. Run `npm install -g @adports/aidev`.
5. Print `adpai --help`.

The scripts contain no secrets. Each user authenticates with their own AD Ports identity, which must have **Feed Reader** on the [adpai feed](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `401 Unauthorized` on `npm view` | Confirm the user has **Feed Reader** on the adpai Azure Artifacts feed, then rerun the installer. |
| `E404 registry.npmjs.org` | The `@adports` npm scope did not map to the private feed. Rerun the installer or add `@adports:registry=https://pkgs.dev.azure.com/abudhabiports/_packaging/adpai/npm/registry/` to `~/.npmrc`. |
| `Ignoring extra certs from ... zscaler-root-ca.crt` | `NODE_EXTRA_CA_CERTS` points to a missing or inaccessible certificate. Fix the path or run `Remove-Item Env:NODE_EXTRA_CA_CERTS` for the current PowerShell session, then rerun the installer. |
| `CERTIFICATE_VERIFY_FAILED` or `SSLCertVerificationError` during `az extension add` | Corporate TLS inspection, commonly Zscaler, is trusted by Windows but not always by Azure CLI's Python certificate bundle. Preferred Windows fix: run `az config set core.use_default_cert_store=true`, then rerun `az extension add --name azure-devops --only-show-errors`. |
| `Azure CLI ('az') is required` | Install Azure CLI from Company Portal / Software Center or ask IT to deploy it. If user-scope winget is allowed, try `winget install -e --id Microsoft.AzureCLI --scope user`. Then close and reopen PowerShell and rerun the installer. |
| `ERROR: no .vsix found` after download | Confirm the requested version exists at <https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix>. Omit the version arg to grab the latest. |
| `VS Code CLI ('code') is required` | If VS Code is installed, open VS Code and run Command Palette -> **Shell Command: Install 'code' command in PATH**, then reopen PowerShell. If VS Code is missing and user-scope winget is allowed, try `winget install -e --id Microsoft.VisualStudioCode --scope user`. |
