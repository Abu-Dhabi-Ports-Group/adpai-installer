# adpai-installer

Public bootstrap installers for [`@adports/aidev`](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/Npm/@adports%2Faidev/overview) — the AD Ports SDLC AI agent CLI.

These scripts are mirrored from [`ai-skills/dist/public/`](https://dev.azure.com/abudhabiports/Foundations/_git/ai-skills?path=/dist/public). The source of truth is `ai-skills`; do not edit files in this repo directly.

## Usage

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.sh | bash
```

### Windows (PowerShell)

```powershell
iwr -useb https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.ps1 | iex
```

## What the scripts do

1. Verify Node 18+ (offer to install via `brew`/`apt` if missing).
2. Authenticate the user to the private adpai Azure Artifacts feed via SSO.
3. Write feed credentials to `~/.npmrc`.
4. Run `npm install -g @adports/aidev`.
5. Print `adpai --help`.

The scripts contain no secrets. Each user authenticates with their own AD Ports identity, which must have **Feed Reader** on the [adpai feed](https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions).
