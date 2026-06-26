# Privacy Policy — AD Ports AI Catalog (Browser Extension)

_Last updated: 2026-06-26_

The **AD Ports AI Catalog** browser extension (Chrome / Edge MV3) is published by
the AD Ports Group AI SDLC team. This document explains exactly what the
extension does and does not do with your data.

## Summary

- The extension **does not collect, transmit, sell, or share** any personal data.
- It makes **no network requests by default**. The only outbound request the
  extension can make is an **optional** catalog-refresh `GET` to a URL **you
  type yourself** in Settings (empty by default); the request carries no prompt
  text, no reply text, no cookies, no user identifier.
- The full skill catalog (skill metadata, `SKILL.md` bodies, workflows,
  references, templates) is **bundled inside the extension package** at build
  time and loaded locally from your browser's extension storage.
- All user preferences (favorites, recents, settings, PII-guard toggle) are
  stored locally via `chrome.storage.local` / `chrome.storage.sync` and
  **never leave your device**.

## What the extension does

- Reads the text you type in the prompt input of supported AI chat sites
  (Claude, ChatGPT, Gemini, Perplexity, GitHub Copilot) **only inside your
  browser tab** in order to:
  - detect `//skill-id` and `@@role-id` palette triggers,
  - run the optional pre-send PII / data-classification guard against
    locally-defined patterns,
  - rank suggestions to display in the side panel.
- Inserts skill / role preamble text into the chat input when you click
  **Insert into prompt**, press a favorite keyboard shortcut, or commit the
  palette.
- Optionally saves the assistant's reply to disk as a Markdown artifact when
  you click **Save**. The save action is implemented entirely in the page as
  a client-side `<a download>` link backed by a `Blob` URL; the extension does
  **not** use the `chrome.downloads` API.

## What the extension does NOT do

- No tracking, no analytics, no telemetry, no crash reporting.
- No remote code execution. All JavaScript is bundled in the extension package
  reviewed by the Chrome Web Store.
- No reading or writing of cookies, authentication tokens, conversation
  history, or account information of the AI chat sites.
- No transmission of your prompt text, the assistant's reply, your favorites,
  your settings, or any usage signal to any AD Ports server, chat host, or
  third party.

## Permissions justification (v1.1.2)

| Permission | Why it is required |
|---|---|
| `storage` | Persist favorites, recents, settings, the PII-guard tenant toggle, and the PII override audit log locally. |
| `sidePanel` | Display the catalog UI in Chrome's side panel. |
| `alarms` | Schedule a best-effort 24-hour catalog snapshot refresh from the background service worker. The alarm only triggers a metadata refresh and never collects, transmits, or reacts to user data. |
| Host permissions for `claude.ai`, `chatgpt.com`, `chat.openai.com`, `gemini.google.com`, `www.perplexity.ai`, `github.com/copilot` | Detect each site's prompt input and reply DOM to enable insert, the pre-send guard, and save. |

The extension deliberately does **not** request `activeTab`, `tabs`,
`scripting`, `downloads`, `webRequest`, `cookies`, `history`, `bookmarks`,
`notifications`, `nativeMessaging`, `identity`, `geolocation`, or
`<all_urls>`. Content scripts are statically declared, the save-reply action
uses a client-side `<a download>` Blob link, and `host_permissions` cover
every target the extension talks to.

## Data we store locally

| Item | Storage | Leaves your device? |
|---|---|---|
| Favorite skill / role IDs | `chrome.storage.local` and `chrome.storage.sync` (`adp.favorites`) | No |
| Recent skill / role IDs | `chrome.storage.local` (`adp.recents`) | No |
| Settings (tenant toggle, optional catalog URL, GitHub target repo, override-allowed flag, custom rules) | `chrome.storage.sync` (`adp.settings`) | No |
| Catalog snapshot cache | `chrome.storage.local` (`adp.catalog`) | No |
| PII / data-classification override audit log | `chrome.storage.local` (`adp.pii.auditLog`) — stores only the matched rule IDs and a 16-character SHA-256 hash prefix of the prompt; **never the prompt itself** | No |
| Catalog (`catalog.json`, `skill-bundles.json`) | Bundled at build time | No (already on disk) |

You can clear all of this at any time by removing the extension from
`chrome://extensions`, or clear the PII audit log on its own from the side
panel's Settings.

## Limited Use disclosure

The use of the data described above adheres to the
[Chrome Web Store User Data Policy](https://developer.chrome.com/docs/webstore/program-policies/user-data-faq)
and its Limited Use requirements:

- **Allowed use only.** The data is used solely to provide the extension's
  single insert-guard-capture purpose (insert a catalog entry into the
  prompt, check the prompt against the data-classification rules before
  send, and capture the assistant's reply on user click). It is not used
  for any other product feature, model training, profiling, or aggregation.
- **No transfer.** The data is not transferred to AD Ports servers, the
  chat host's servers, or any third party. It does not leave the browser.
  The only outbound network call the extension can make is the optional
  user-configured catalog-refresh `GET` to the URL the user typed in
  Settings, and that request carries no prompt text, no reply text, no
  cookies, and no user identifier.
- **No advertising.** The data is not used for advertising of any kind,
  including personalized or retargeted advertising. The extension contains
  no advertising SDK and no advertising endpoint.
- **No humans read it.** No human at AD Ports Group, no human at Google,
  and no third party reads the user's prompt text, reply text, or tab URLs,
  except (a) with the user's affirmative consent for a specific instance,
  (b) when required to comply with applicable law, or (c) for security
  investigation of suspected abuse of the extension.

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
