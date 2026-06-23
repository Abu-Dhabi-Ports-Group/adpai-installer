#!/usr/bin/env bash
# AD Ports Claude Code plugin installer (macOS / Linux)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Claude Code session.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-claude-plugin.sh | bash
#
# Claude Code uses the same plugin server but a separate marketplace.json that
# advertises adp-ai-sdlc-claude (Anthropic naming). The plugin itself is the
# same OAuth/tool/MCP surface.

set -euo pipefail

MARKETPLACE_URL="${ADPAI_MARKETPLACE_URL:-https://adports.github.io/adpai-installer/claude.marketplace.json}"
PLUGIN_ID='adp-ai-sdlc-claude'

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --help|-h)
    sed -n '1,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

if ! command -v claude >/dev/null 2>&1; then
  die "Claude Code CLI ('claude') not found on PATH. Install Claude Code from https://www.anthropic.com/claude-code first."
fi
ok "Claude CLI present: $(claude --version 2>/dev/null || echo unknown)"

cat <<EOF

Run these two commands inside any Claude Code session to register and install:

  /plugin marketplace add adports $MARKETPLACE_URL
  /plugin install $PLUGIN_ID

After installation, sign in by invoking any AD Ports tool — Claude Code will
hand you off to the OAuth flow in your browser.

Sign-in uses your existing AD Ports Microsoft account. The plugin server
never sees your password, and your refresh token never leaves the AD Ports
landing zone.
EOF
