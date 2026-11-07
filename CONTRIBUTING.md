---
type: Contribution Guide
description: Focused contribution and validation expectations for Arcbox changes.
created: "2026-11-07"
---
# Contributing

Read [AGENTS.md](AGENTS.md), [the development guide](docs/DEVELOPMENT.md) and [the product journey](docs/customer-journey.md).

- Keep changes focused on observable user behavior.
- Implement operation behavior once in ArcboxCore, then expose it consistently to GUI/CLI/MCP.
- Preserve originals and reject existing output paths.
- Update English and Russian translations together; keep protocol error codes stable.
- Describe the verification performed, especially data round trips and error recovery.
- Do not commit private files, passwords, build outputs, or downloaded archive fixtures.
- New persistent tests, fixtures, CI checks or external services need explicit maintainer approval.

For a bug report, include macOS version, chip architecture, Arcbox version, archive format and minimal reproduction steps. A synthetic example is preferable to a personal archive.
