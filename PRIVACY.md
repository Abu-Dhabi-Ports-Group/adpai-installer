# Privacy Policy — AD Ports AI Catalog (Browser Extension)

_Last updated: 2026-06-17_

The **AD Ports AI Catalog** browser extension (Chrome / Edge MV3) is published by
the AD Ports Group AI SDLC team. This document explains exactly what the
extension does and does not do with your data.

## Summary

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
