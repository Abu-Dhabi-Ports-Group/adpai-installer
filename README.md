# adpai-installer

Public bootstrap installers for the AD Ports SDLC AI tooling:

- [`@adports/aidev`](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/Npm/@adports%2Faidev/overview) — the CLI catalog scaffolder
- [`adports.adp-ai-sdlc`](https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix) — the VS Code extension

These scripts are mirrored from [`ai-skills/dist/public/`](https://dev.azure.com/abudhabiports/Foundations/_git/ai-skills?path=/dist/public). The source of truth is `ai-skills`; do not edit files in this repo directly.

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

1. Verifies Azure CLI (`az`) and the `azure-devops` extension are present.
2. Runs `az login` if no active session.
3. Downloads the requested VSIX from the private `adpai-vsix` Azure Artifacts Universal feed.
4. Runs `code --install-extension <vsix> --force`.
5. Bootstraps the `@adports/aidev` CLI by chaining `install-adpai.{sh,ps1}` (skip with `--skip-cli` / `-SkipCli`).

The user must have **Feed Reader** on both the [`adpai-vsix` feed](https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix/settings/permissions) (VSIX) and the [`adpai` feed](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions) (CLI). The scripts contain no secrets.

## What the CLI installer does

1. Verify Node 18+ (offer to install via `brew`/`apt` if missing).
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
| `ERROR: 'az' not found` (VSIX installer) | Install Azure CLI: <https://aka.ms/installazurecli> (`winget install Microsoft.AzureCLI` on Windows, `brew install azure-cli` on macOS). |
| `ERROR: no .vsix found` after download | Confirm the requested version exists at <https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix>. Omit the version arg to grab the latest. |
| `code: command not found` | In VS Code: Command Palette → **Shell Command: Install 'code' command in PATH**. |
