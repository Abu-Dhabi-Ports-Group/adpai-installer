#!/usr/bin/env bash
# Install the latest ADP AI SDLC VS Code extension from the
# Azure Artifacts Universal feed (Foundations / adpai-vsix).
#
# Prerequisites (one-time, per user):
#   1. Azure CLI:        winget install Microsoft.AzureCLI  (Windows)
#                        brew install azure-cli             (macOS)
#                        See https://aka.ms/installazurecli (other)
#   2. DevOps extension: az extension add --name azure-devops
#   3. Sign in:          az login
#
# Usage:
#   bash install-vsix.sh                # latest version, also installs CLI
#   bash install-vsix.sh 2.0.1           # specific version
#   bash install-vsix.sh 2.0.1 --skip-cli  # VSIX only, skip CLI bootstrap
#
# This script does NOT need to be run from a repo clone — it can be fetched
# and executed standalone:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.sh | bash
set -euo pipefail

ORG="https://dev.azure.com/abudhabiports"
PROJECT="Foundations"
FEED="adpai-vsix"
PACKAGE="adp-ai-sdlc"
ADPORTS_TENANT_ID="3b618463-9352-4fa4-a67c-112da2837c29"
FEED_PERMS_URL="https://dev.azure.com/abudhabiports/Foundations/_artifacts/feed/adpai-vsix/settings/permissions"
CLI_INSTALLER_URL="https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.sh"

VERSION="*"
SKIP_CLI=0
for arg in "$@"; do
  case "$arg" in
    --skip-cli) SKIP_CLI=1 ;;
    -h|--help)
      sed -n '1,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) VERSION="$arg" ;;
  esac
done

if ! command -v az >/dev/null 2>&1; then
  echo "ERROR: Azure CLI ('az') not found. Install it: https://aka.ms/installazurecli" >&2
  exit 1
fi

if ! command -v code >/dev/null 2>&1; then
  echo "ERROR: VS Code CLI ('code') not found on PATH." >&2
  echo "  In VS Code: Command Palette -> 'Shell Command: Install code command in PATH'" >&2
  exit 1
fi

# Ensure the devops extension is available (idempotent).
if ! az extension show --name azure-devops >/dev/null 2>&1; then
  echo ">> Installing 'azure-devops' Azure CLI extension ..."
  az extension add --name azure-devops --only-show-errors
fi

# Confirm the user is signed in to the AD Ports tenant.
# Many AD Ports devs have a personal/MSA tenant cached from a previous 'az login';
# without forcing the AD Ports tenant, the Foundations project is invisible and
# the download fails with: VS800075: The project ... does not exist, or you do
# not have permission to access it.
CURRENT_TENANT="$(az account show --query tenantId -o tsv 2>/dev/null || true)"
if [[ "$CURRENT_TENANT" != "$ADPORTS_TENANT_ID" ]]; then
  # Prefer an already-cached AD Ports subscription (no browser, no MFA) before
  # falling back to an interactive login.
  ADPORTS_SUB="$(az account list --query "[?tenantId=='$ADPORTS_TENANT_ID'] | [0].id" -o tsv 2>/dev/null || true)"
  if [[ -n "$ADPORTS_SUB" ]]; then
    echo ">> Switching default Azure subscription to AD Ports tenant (cached)."
    az account set --subscription "$ADPORTS_SUB"
  else
    if [[ -z "$CURRENT_TENANT" ]]; then
      echo ">> Not signed in. Running 'az login --tenant $ADPORTS_TENANT_ID' ..."
    else
      echo ">> Current Azure session is not in the AD Ports tenant"
      echo "   (current: $CURRENT_TENANT, expected: $ADPORTS_TENANT_ID)."
      echo ">> Signing in to the AD Ports tenant ..."
    fi
    if ! az login --tenant "$ADPORTS_TENANT_ID" --only-show-errors >/dev/null; then
      cat >&2 <<EOM

ERROR: 'az login --tenant $ADPORTS_TENANT_ID' failed.

Try one of these manually, then re-run the installer:

  # Standard browser login (works on most machines):
  az login --tenant $ADPORTS_TENANT_ID

  # If the browser does not open (SSH session, headless, restricted browser):
  az login --tenant $ADPORTS_TENANT_ID --use-device-code

Re-run:
  curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.sh | bash

EOM
      exit 1
    fi
  fi
fi
ACCOUNT_USER="$(az account show --query user.name -o tsv 2>/dev/null || echo unknown)"
echo ">> Signed in as: $ACCOUNT_USER"

# ---------- Rosetta 2 preflight (Apple Silicon macOS) ----------
# 'az artifacts universal download' shells out to a vendored helper called
# 'artifacttool' which Microsoft ships ONLY as an Intel (osx-x64) binary.
# On Apple Silicon (M1/M2/M3/...) this requires Rosetta 2; without it the
# download fails with: [Errno 86] Bad CPU type in executable.
if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
  if ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    cat >&2 <<'EOM'
>> Apple Silicon Mac detected without Rosetta 2.
>> 'az artifacts' uses an Intel-only helper (artifacttool), so Rosetta 2
>> is required to download the VSIX. Attempting auto-install now
>> (you may be prompted for your macOS password):
>>
>>     sudo softwareupdate --install-rosetta --agree-to-license
EOM
    if sudo softwareupdate --install-rosetta --agree-to-license; then
      echo ">> Rosetta 2 installed." >&2
    else
      cat >&2 <<'EOM'

ERROR: Rosetta 2 auto-install failed (or was cancelled).

Install it manually first:

    sudo softwareupdate --install-rosetta --agree-to-license

Then re-run this installer:

    curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-vsix.sh | bash

EOM
      exit 1
    fi
  fi
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo ">> Downloading $PACKAGE@$VERSION from $ORG/$PROJECT/$FEED ..."
DOWNLOAD_LOG="$(mktemp)"
if ! az artifacts universal download \
      --organization "$ORG" \
      --project "$PROJECT" \
      --scope project \
      --feed "$FEED" \
      --name "$PACKAGE" \
      --version "$VERSION" \
      --path "$TMP_DIR" \
      --only-show-errors 2>"$DOWNLOAD_LOG"; then
  cat "$DOWNLOAD_LOG" >&2
  if grep -q "VS800075" "$DOWNLOAD_LOG" 2>/dev/null; then
    cat >&2 <<EOM

ERROR: Cannot see the '$PROJECT' project or '$FEED' feed in Azure DevOps.

This usually means one of:

  1. You signed in with a non-AD-Ports Microsoft account.
     Verify with:   az account show
     The 'tenantId' must be: $ADPORTS_TENANT_ID
     If wrong, run:  az login --tenant $ADPORTS_TENANT_ID
     then re-run this installer.

  2. Your AD Ports identity has no 'Feed Reader' permission on '$FEED'.
     Ask the AD Ports DevOps admin to grant access here:
        $FEED_PERMS_URL

EOM
  fi
  rm -f "$DOWNLOAD_LOG"
  exit 1
fi
rm -f "$DOWNLOAD_LOG"

VSIX="$(ls -1 "$TMP_DIR"/*.vsix 2>/dev/null | head -n1 || true)"
if [[ -z "$VSIX" || ! -f "$VSIX" ]]; then
  echo "ERROR: no .vsix found in downloaded package." >&2
  ls -la "$TMP_DIR" >&2
  exit 1
fi

echo ">> Installing $(basename "$VSIX") into VS Code ..."
code --install-extension "$VSIX" --force

if [[ "$SKIP_CLI" -eq 0 ]]; then
  echo
  echo ">> Bootstrapping @adports/aidev CLI ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$CLI_INSTALLER_URL" | bash || {
      echo "WARN: CLI bootstrap failed. Run it manually:" >&2
      echo "  curl -fsSL $CLI_INSTALLER_URL | bash" >&2
    }
  else
    echo "WARN: curl not found \u2014 skipping CLI bootstrap. Install manually:" >&2
    echo "  curl -fsSL $CLI_INSTALLER_URL | bash" >&2
  fi
else
  echo
  echo ">> --skip-cli set; @adports/aidev CLI NOT installed."
  echo "   To install later: curl -fsSL $CLI_INSTALLER_URL | bash"
fi

echo
echo ">> Done. Reload VS Code window (Ctrl+Shift+P -> 'Developer: Reload Window') to activate the extension."
