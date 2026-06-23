#!/usr/bin/env bash
# AD Ports Codex Desktop plugin installer (macOS / Linux)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Codex Desktop. It contains no secrets and never logs user data.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.sh | bash
#
# What happens when you run it:
#   1. Checks that the `codex` CLI is on PATH (Codex Desktop ships one).
#   2. Adds the AD Ports marketplace URL to Codex Desktop.
#   3. Installs the `adp-ai-sdlc-codex` plugin.
#   4. Reminds the user to sign in (which is done in the Codex Desktop UI).
#
# Override the marketplace URL with $ADPAI_MARKETPLACE_URL when smoke-testing
# a staging rendering.

set -euo pipefail

MARKETPLACE_URL="${ADPAI_MARKETPLACE_URL:-https://adports.github.io/adpai-installer/codex.marketplace.json}"
PLUGIN_ID='adports/adp-ai-sdlc-codex'

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --help|-h)
    sed -n '1,18p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  die "Codex Desktop CLI ('codex') not found on PATH. Install Codex Desktop from https://openai.com/codex first."
fi
ok "Codex CLI present: $(codex --version 2>/dev/null || echo unknown)"

say "Registering AD Ports marketplace: $MARKETPLACE_URL"
codex plugin marketplace add adports "$MARKETPLACE_URL"
ok 'Marketplace registered'

say "Installing $PLUGIN_ID"
codex plugin install "$PLUGIN_ID"
ok 'Plugin installed'

cat <<'EOF'

Done. Open Codex Desktop and sign in to the AD Ports plugin:
  - Click the plugin in the chat composer.
  - Choose "Sign in".
  - Complete the AD Ports Microsoft sign-in flow in your browser.

Sign-in uses your existing AD Ports Microsoft account. The plugin server
never sees your password, and your refresh token never leaves the AD Ports
landing zone.
EOF
