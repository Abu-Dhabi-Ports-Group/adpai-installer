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

# Confirm the user is signed in.
if ! az account show >/dev/null 2>&1; then
  echo ">> Not signed in. Running 'az login' ..."
  az login --only-show-errors >/dev/null
fi

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
az artifacts universal download \
  --organization "$ORG" \
  --project "$PROJECT" \
  --scope project \
  --feed "$FEED" \
  --name "$PACKAGE" \
  --version "$VERSION" \
  --path "$TMP_DIR" \
  --only-show-errors

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
