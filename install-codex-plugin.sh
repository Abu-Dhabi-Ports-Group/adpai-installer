#!/usr/bin/env bash
# AD Ports Codex Desktop plugin installer (macOS / Linux)
#
# This script is publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can register the AD Ports marketplace with their
# local Codex Desktop. It contains no secrets and never logs user data.
#
# NOTE ON OWNERSHIP: this is the CANONICAL copy. sync-installer-repo.sh in this
# same directory publishes it to the URL above, so this file is what users
# actually download. ext-hosts/hosts/codex/installers/install-codex-plugin.sh is a
# byte-equivalent mirror — see the "Installer ownership" section of
# ext-hosts/README.md. Change both or neither.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-codex-plugin.sh | bash
#
# What happens when you run it:
#   1. Checks that the `codex` CLI is on PATH (Codex Desktop ships one).
#   2. Registers the AD Ports marketplace source with Codex Desktop.
#   3. Installs the `adp-ai-sdlc-codex` plugin from that marketplace.
#   4. Reminds the user to sign in (which is done in the Codex Desktop UI).
#
# Override the marketplace source with $ADPAI_MARKETPLACE_SOURCE when
# smoke-testing a staging rendering.

set -euo pipefail

# Codex marketplace SOURCE — verified against codex-cli 0.139.0:
#   `codex plugin marketplace add [OPTIONS] <SOURCE>`
#   <SOURCE> := "a local path, owner/repo[@ref], HTTPS Git URL, or SSH Git URL"
# A bare .json URL is NOT a valid source: codex `git clone`s whatever it is
# given, so passing the rendered codex.marketplace.json URL fails with
# `fatal: repository '.../codex.marketplace.json/' not found`. The source must
# be a repo/directory containing `.agents/plugins/marketplace.json`.
# $ADPAI_MARKETPLACE_URL is still honoured for backwards compatibility, but it
# must now hold a SOURCE in one of the forms above, not a manifest URL.
MARKETPLACE_SOURCE="${ADPAI_MARKETPLACE_SOURCE:-${ADPAI_MARKETPLACE_URL:-https://github.com/Abu-Dhabi-Ports-Group/adpai-installer}}"

# Plugin selector — verified against codex-cli 0.139.0:
#   `codex plugin add [OPTIONS] <PLUGIN[@MARKETPLACE]>`
# The @MARKETPLACE half is the `name` field of the marketplace manifest, NOT a
# publisher/owner path. `codex plugin add adports/adp-ai-sdlc-codex` fails with
# "plugin requires --marketplace unless passed as <plugin>@<marketplace>".
PLUGIN_SELECTOR='adp-ai-sdlc-codex@adports'

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --help|-h)
    sed -n '1,24p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  die "Codex Desktop CLI ('codex') not found on PATH. Install Codex Desktop from https://openai.com/codex first."
fi
ok "Codex CLI present: $(codex --version 2>/dev/null || echo unknown)"

# Capability probe, not a version check — the same pattern the Claude installer
# uses. `codex plugin marketplace add` and `codex plugin add` exist on current
# Codex Desktop (verified against codex-cli 0.139.0), but older builds managed
# plugins differently. Probe rather than assume: under `set -euo pipefail` an
# installer that invokes a subcommand the local build does not have dies on a
# raw clap usage error, which is worse than printing instructions.
#
# Note `codex plugin install` does NOT exist on any build — it is `plugin add`.
# The pre-merge installer called `install` and passed two positionals to
# `marketplace add`; both were fatal.
if codex plugin marketplace add --help >/dev/null 2>&1 &&
   codex plugin add --help >/dev/null 2>&1; then
  say "Registering AD Ports marketplace: $MARKETPLACE_SOURCE"
  codex plugin marketplace add "$MARKETPLACE_SOURCE"
  ok 'Marketplace registered'

  say "Installing $PLUGIN_SELECTOR"
  codex plugin add "$PLUGIN_SELECTOR"
  ok 'Plugin installed'
else
  warn "This Codex build has no 'codex plugin add' CLI — printing manual steps."
  cat <<EOF

Update Codex Desktop, then run:

  codex plugin marketplace add $MARKETPLACE_SOURCE
  codex plugin add $PLUGIN_SELECTOR

EOF
fi

cat <<'EOF'

Done. Open Codex Desktop and sign in to the AD Ports plugin:
  - Click the plugin in the chat composer.
  - Choose "Sign in".
  - Complete the AD Ports Microsoft sign-in flow in your browser.

Sign-in uses your existing AD Ports Microsoft account. The plugin server
never sees your password, and your refresh token never leaves the AD Ports
landing zone.
EOF
