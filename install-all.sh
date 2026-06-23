#!/usr/bin/env bash
# AD Ports — install ALL AD Ports AI tooling (macOS / Linux)
#
# Publicly hosted at https://github.com/Abu-Dhabi-Ports-Group/adpai-installer
# so any AD Ports developer can bootstrap the full toolchain with one command.
# No secrets, no PAT input — each sub-installer handles its own auth.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main/install-all.sh | bash
#
# What it installs (in order):
#   1. @adports/aidev CLI       (required — install-adpai.sh)
#   2. ADP AI VS Code extension (required — install-vsix.sh)
#   3. Codex Desktop plugin     (optional — install-codex-plugin.sh; skipped if `codex` CLI is missing)
#   4. Claude Code plugin       (optional — install-claude-plugin.sh; skipped if `claude` CLI is missing)
#
# Skip behavior:
#   - Steps 1 and 2 are required. If either fails, the script exits non-zero.
#   - Steps 3 and 4 are optional. If the host CLI is missing or the install
#     fails, the step is logged and skipped — the overall script keeps going.

set -uo pipefail

BASE="${ADPAI_INSTALLER_BASE:-https://raw.githubusercontent.com/Abu-Dhabi-Ports-Group/adpai-installer/main}"

say()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --help|-h)
    sed -n '1,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

run_required() {
  local label="$1" url="$2"
  say "Installing: ${label}"
  if curl -fsSL "$url" | bash; then
    ok "${label} installed"
    return 0
  fi
  die "${label} installation failed — see output above. Required step; aborting."
}

run_optional() {
  local label="$1" url="$2" host_cli="$3"
  if ! command -v "$host_cli" >/dev/null 2>&1; then
    warn "${label}: '${host_cli}' CLI not found on PATH — skipping."
    return 0
  fi
  say "Installing: ${label}"
  if curl -fsSL "$url" | bash; then
    ok "${label} installed"
  else
    warn "${label} installation failed — continuing (optional step)."
  fi
}

# --- Required ------------------------------------------------------------
run_required "AD Ports CLI (@adports/aidev)"        "${BASE}/install-adpai.sh"
run_required "AD Ports VS Code extension (adp-ai-sdlc)" "${BASE}/install-vsix.sh"

# --- Optional (only if host CLI is present) ------------------------------
run_optional "Codex Desktop plugin"   "${BASE}/install-codex-plugin.sh"  codex
run_optional "Claude Code plugin"     "${BASE}/install-claude-plugin.sh" claude

echo
ok "Done. Run 'adpai --help' to verify the CLI is on PATH."
echo "  Restart VS Code to load the extension."
echo "  Sign in to the Codex / Claude plugin from the host UI on first use."
