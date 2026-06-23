# Privacy Policy — AD Ports AI Catalog (Browser Extension)

_Last updated: 2026-06-17_

The **AD Ports AI Catalog** browser extension (Chrome / Edge MV3) is published by
the AD Ports Group AI SDLC team. This document explains exactly what the
extension does and does not do with your data.## Summary

- The extension **does not collect, transmit, sell, or share** any personal data.
- It makes **no network requests** to any AD Ports server, third party, analytics
  provider, or telemetry endpoint.
- The full skill catalog (skill metadata, SKILL.md bodies, workflows,
  references, templates) is **bundled inside the extension package** at build
  time and loaded locally from your browser's extension storage.
- All user preferences (favorites, recents, settings, PII-guard toggle) are
  stored locally via `chrome.storage.local` and **never leave your device**.

## What the extension does

- Reads the text you type in the prompt input of supported AI chat sites
  (Claude, ChatGPT, Gemini, Perplexity, GitHub Copilot) **only inside your
  browser tab** in order to:
  - detect `//skill-id` and `@@role-id` palette triggers,
  - run the optional pre-send PII guard against locally-defined patterns,
  - rank suggestions to display in the side panel.
- Inserts skill / role preamble text into the chat input when you click
  **Insert into prompt**, press a favorite keyboard shortcut, or commit the
  palette.
- Optionally saves the assistant's reply to disk (via the browser's standard
  download flow) as a Markdown artifact, only when you click **Save**.

## What the extension does NOT do

- No tracking, no analytics, no telemetry, no crash reporting.
- No remote code execution. All JavaScript is bundled in the extension package
  reviewed by the Chrome Web Store.
- No reading or writing of cookies, authentication tokens, conversation
  history, or account information of the AI chat sites.
- No transmission of your prompt text, the assistant's reply, your favorites,
  your settings, or any usage signal to any server.

## Permissions justification

| Permission | Why it is required |
|---|---|
| `storage` | Persist favorites, recents, and the PII-guard tenant toggle locally. |
| `scripting` | Inject the skill preamble text into the prompt input on supported chat sites. |
| `sidePanel` | Display the catalog UI in Chrome's side panel. |
| `activeTab` | Identify the active supported chat tab when you click Insert. |
| `downloads` | Save assistant replies to disk as Markdown when you click Save. |
| Host permissions for `claude.ai`, `chatgpt.com`, `chat.openai.com`, `gemini.google.com`, `perplexity.ai`, `github.com/copilot` | Detect each site's prompt input and reply DOM to enable insert and save. |

## Data we store locally

| Item | Storage | Leaves your device? |
|---|---|---|
| Favorite skill / role IDs | `chrome.storage.local` | No |
| Recent skill / role IDs | `chrome.storage.local` | No |
| Settings (PII-guard tenant toggle, etc.) | `chrome.storage.local` | No |
| Last-invoked skill ID (for Save context) | `chrome.storage.local` | No |
| Catalog (`catalog.json`, `skill-bundles.json`) | Bundled at build time | No (already on disk) |

You can clear all of this at any time by removing the extension from
`chrome://extensions`.

## Children's privacy

The extension is intended for AD Ports Group staff and contractors during
software-development work. It is not directed at children under 13.

## Changes to this policy

Any change to the data-handling behavior described above will be reflected
in this file before the new version is published to the Chrome Web Store.

## Contact

For questions about this policy, open an issue at:

<https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/issues>

---

# Privacy Policy — AD Ports AI Codex Plugin Server (`adpai-plugin-server`)

_Last updated: 2026-07-04_

This section covers the **server-side Codex / Claude plugin** that runs in the
AD Ports landing zone and brokers MCP tool calls for the `adports-dev-ai`
plugin. It is separate from the browser-extension policy above.

## What gets stored, where, and how

| Item | Where | How long | Encryption |
|---|---|---|---|
| Entra refresh tokens | Azure Tables `adpaipluginsessions` (`adpai-plugin-secrets` storage account) | 24 h absolute / 8 h idle | AES-256-GCM at rest (key = single 32-byte `ADPAI_SESSION_KEY`) |
| Plugin session JWT (returned to Codex) | Client only | 8 h idle / 24 h absolute | HS256, same `ADPAI_SESSION_KEY` |
| Telemetry opt-out flag | Azure Tables `adpaipluginoptout` | indefinite (until you change it) | At-rest by Azure Storage |
| App Insights telemetry | Application Insights | per AI SDLC retention policy | TLS in transit, Microsoft at-rest defaults |

**No raw `upn`, `tid`, or `displayName` is ever placed in the plugin session
JWT.** Claims are limited to `{sub, sid, tier, tidHash, upnHash, nonce, iat,
nbf, exp, abs}`. Hashes are sha256 truncated to 16 hex chars.

## What's in the plugin session JWT (HS256)

| Claim | Value |
|---|---|
| `sub` | session GUID (base64url) — same as `sid` |
| `sid` | session GUID |
| `tier` | `essentials` \| `advanced` \| `enterprise` |
| `tidHash` | sha256(tenantId)[:16] |
| `upnHash` | sha256(upn)[:16] |
| `nonce` | random base64url |
| `iat`, `nbf`, `exp`, `abs` | UNIX seconds |

The tenant ID, the user principal name, and the display name **never appear
in the JWT** and **never appear in App Insights** (they are denylisted by
`@adports/adpai-telemetry`).

## Telemetry — allowlisted events only

The plugin server emits exactly the following events. The full list is enforced
at runtime by [`@adports/adpai-telemetry`](../../packages/adpai-telemetry) and
audited in [`internal/telemetry-allowlist.md`](../../internal/telemetry-allowlist.md).

| Event | When | Properties |
|---|---|---|
| `pluginServer.started` | Once per container revision after boot | `version` |
| `pluginServer.tool.invoked` | After every successful tool call | `tool`, `tier`, `durationMs` |
| `pluginServer.tool.failed` | After a tool call rejected for tier, schema, or unhandled error | `tool`, `reason` (one of `TIER_DENIED`, `INVALID_INPUT`, `UNHANDLED`) |
| `pluginServer.optOut.changed` | When a user calls `opt_out_telemetry` | `choice` (`opt-in` \| `opt-out`) |

The plugin server never emits a request body, never emits a prompt, never
emits a token, and never emits a raw upn/tid.

## Telemetry opt-out

Per-user opt-out is honored server-side. Two ways to opt out:

1. Call the `opt_out_telemetry` MCP tool from Codex / Claude with
   `{"choice": "opt-out"}`. The decision is persisted to
   `adpaipluginoptout` keyed by `(tidHash, upnHash)` and is enforced on every
   subsequent request automatically.
2. AD Ports staff are **opted-in by default**. Every other tenant is
   **opted-out by default** (fail-closed). Cross-tenant guests cannot enable
   telemetry on themselves — the tenant gate in
   [`adp-bknd-net-crosscut`](../../.claude/skills/adp-bknd-net-crosscut) blocks
   non-AD-Ports tenants from binding sessions.

Opt-out state is read on every request before any tool fires. If the
`adpaipluginoptout` table is unreachable, the server **treats the caller as
opted-out** (fail-closed) until the table recovers.

## MCP bridge — what flows where

The server exposes three MCP-bridge endpoints behind bearer auth:

- `GET  /mcp/_targets` — returns the visible-by-tier list of upstream MCP
  targets (id, label, audience, minTier). No upstream call.
- `POST /mcp/<id>/messages` — proxies one MCP message to the upstream MCP
  server configured for `<id>`. The server strips `authorization`, `cookie`,
  `proxy-authorization`, `x-ms-client-principal`, and
  `x-forwarded-authorization` from the inbound request before forwarding, and
  injects an audience-specific brokered bearer (never the plugin session JWT)
  into the upstream call.
- `GET  /mcp/<id>/sse` — same auth + stripping, forwards the upstream Server-
  Sent-Events stream verbatim.

Upstream MCP servers see only the `User-Agent` and content headers the AD Ports
broker chooses. The user's plugin session JWT never reaches an upstream MCP
server.

## What the plugin server does NOT do

- Does not write to your local disk. Skill-management tools return a shell
  command for you to run; they never spawn a process or invoke `git`.
- Does not store the assistant's reply, the prompt, or any AI output.
- Does not log token material at any level.
- Does not collect IP addresses beyond what App Insights / the Azure load
  balancer record at the platform layer.
- Does not share data with anyone outside AD Ports Group.

## Contact

For questions about server-side data handling, file an issue at:

<https://github.com/Abu-Dhabi-Ports-Group/adpai-installer/issues>

or contact the AD Ports AI SDLC team via the existing AD Ports support
channels.
