---
type: Security Policy
description: How to report Arcbox security issues and what the current release protects.
created: "2026-11-07"
---
# Security

Please use [GitHub's private vulnerability reporting](https://github.com/ai-babai/arcbox/security/advisories/new) for security issues. Do not post unpatched vulnerabilities in public issues. Include the affected version, archive format, reproduction steps and expected behavior. Use a minimal non-sensitive reproduction; do not upload personal archives, passwords or credentials.

Для сообщения об уязвимости используй [закрытый отчёт GitHub](https://github.com/ai-babai/arcbox/security/advisories/new), а не публичный issue. Укажи версию и шаги воспроизведения без личных архивов и паролей.

You can also contact the maintainer privately via Telegram [@SkifMax](https://t.me/SkifMax) or email [wip.maks.craft@yandex.com](mailto:wip.maks.craft@yandex.com). English and Russian are welcome.

Arcbox processes untrusted archive metadata. It rejects traversal paths, links, ambiguous listings and conflicting names, confines extraction writes, validates the output, and uses new destinations. These measures are defense in depth, not a formal security audit. Keep the bundled engine updated through reviewed, checksum-pinned releases.

The MCP server runs with the file permissions of its launching account. Connect it only to trusted clients; archive content must not be treated as agent instructions.

Release downloads include SHA-256 checksums and ad-hoc code signatures. They are not Developer ID signed or notarized. Verify the download and follow the documented per-app Gatekeeper flow; do not globally disable platform security.
