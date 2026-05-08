#!/usr/bin/env bash
# AD Ports — install @adports/aidev (macOS / Linux)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can run it without cloning the ai-skills repo.
# It contains no secrets. The user authenticates to the private Azure
# Artifacts feed using AD Ports SSO via Azure CLI — the only auth path.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-adpai.sh | bash
#
# What happens when you run it:
#   1. Checks Node 18+ (offers to install via brew/apt if missing).
#   2. Installs Azure CLI if missing.
#   3. Opens a Microsoft sign-in window in your browser.
#      You enter your AD Ports email + password + MFA in the BROWSER.
#      Nothing is typed in the terminal.
#   4. Writes a feed token to ~/.npmrc.
#   5. Runs npm install -g @adports/aidev.
#   6. Prints adpai --help.
#
# Prerequisites:
#   - Node 18+ (will be auto-installed if brew/apt is available).
#   - Your AD Ports identity must have Feed Reader on the adpai feed:
#       https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions

set -euo pipefail

# Public, well-known constants — no secrets.
AZURE_DEVOPS_RESOURCE_ID='499b84ac-1321-427f-aa17-267ca6975798'
FEED_REGISTRY_HOST='//pkgs.dev.azure.com/abudhabiports/_packaging/adpai/npm/registry/'
FEED_BASE_HOST='//pkgs.dev.azure.com/abudhabiports/_packaging/adpai/npm/'
FEED_URL="https:${FEED_REGISTRY_HOST}"
PKG='@adports/aidev'
NPMRC="$HOME/.npmrc"

case "${1:-}" in
  --help|-h)
    sed -n '1,26p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- Node ----------
say 'Checking Node.js (need 18+)'
if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say 'Installing Node 20 LTS via Homebrew'
    brew install node@20
    brew link --overwrite --force node@20
  elif command -v apt-get >/dev/null 2>&1; then
    say 'Installing Node 20 LTS via apt'
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    die "Node not found and no supported package manager. Install Node 18+ from https://nodejs.org and re-run."
  fi
fi
NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
[ "$NODE_MAJOR" -ge 18 ] || die "Node $(node -v) detected; need Node 18 or newer."
ok "Node $(node -v), npm $(npm -v)"

# ---------- Azure CLI ----------
if ! command -v az >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say 'Azure CLI not found — installing via Homebrew'
    brew install azure-cli
  elif command -v apt-get >/dev/null 2>&1; then
    say 'Azure CLI not found — installing via apt'
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  else
    die "Azure CLI not found and no auto-install available. Install it manually: https://aka.ms/installazurecli"
  fi
fi
ok "Azure CLI: $(az version --query '\"azure-cli\"' -o tsv 2>/dev/null || echo present)"

# ---------- Microsoft sign-in (browser) ----------
if ! az account show >/dev/null 2>&1; then
  say 'Opening Microsoft sign-in window in your browser'
  echo '   (Sign in with your AD Ports account — including MFA — in the browser.'
  echo '    Nothing needs to be typed in this terminal.)'
  if ! az login >/dev/null 2>&1; then
    say 'Browser sign-in failed — falling back to device code'
    az login --use-device-code >/dev/null
  fi
fi
ACCOUNT=$(az account show --query user.name -o tsv 2>/dev/null || echo "unknown")
ok "Signed in as: $ACCOUNT"

# ---------- DevOps token ----------
say 'Fetching Azure DevOps access token'
TOKEN=$(az account get-access-token \
  --resource "$AZURE_DEVOPS_RESOURCE_ID" \
  --query accessToken -o tsv 2>/dev/null || true)
if [ -z "$TOKEN" ] || [ "${#TOKEN}" -lt 100 ]; then
  die "Could not obtain access token. Try: az login --tenant 3b618463-9352-4fa4-a67c-112da2837c29"
fi

# ---------- Update ~/.npmrc ----------
say 'Updating ~/.npmrc'
touch "$NPMRC"
chmod 600 "$NPMRC" 2>/dev/null || true

tmp=$(mktemp)
grep -v '^@adports:registry='                                                   "$NPMRC" \
  | grep -v 'pkgs\.dev\.azure\.com/abudhabiports/_packaging/adpai'              \
  | grep -v 'pkgs\.dev\.azure\.com/abudhabiports/Foundations/_packaging/ai-native' \
  | grep -v '^always-auth=' \
  > "$tmp" || true
mv "$tmp" "$NPMRC"

cat >> "$NPMRC" <<EOF
@adports:registry=${FEED_URL}
${FEED_REGISTRY_HOST}:_authToken=${TOKEN}
${FEED_BASE_HOST}:_authToken=${TOKEN}
EOF
unset TOKEN
ok '~/.npmrc updated'

# ---------- Verify + install ----------
say 'Verifying feed access'
if ! VER=$(npm view "$PKG" version 2>/dev/null); then
  die "Feed access failed. Most likely: your AD Ports identity is missing 'Feed Reader' on the adpai feed.
   Ask the admin to grant access at:
   https://dev.azure.com/abudhabiports/_artifacts/feed/adpai/settings/permissions"
fi
ok "Feed reachable — latest $PKG = $VER"

say "Installing $PKG globally"
npm install -g "$PKG" >/dev/null
ok "Installed: $(adpai --version 2>/dev/null || echo "$PKG@$VER")"

# ---------- Done ----------
echo ''
ok 'Setup complete. Try:'
echo "    adpai --help"
echo "    adpai -y --preset backend-nestjs --tools claude"
echo ''
echo 'The SSO access token is short-lived (~1 hour). If npm install ever 401s,'
echo 'just re-run this installer — your az session will still be valid.'
