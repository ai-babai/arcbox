---
type: Contribution Guide
description: Focused contribution and validation expectations for Arcbox changes.
created: "2026-11-07"
---
# Contributing

Read [the quality contract](docs/QUALITY.md) ([Русский](docs/QUALITY.ru.md)), [AGENTS.md](AGENTS.md), [the development guide](docs/DEVELOPMENT.md) and [the product journey](docs/customer-journey.en.md).

Bug reports and focused pull requests are welcome. Issues and discussions in English or Russian are welcome. By submitting a contribution, you agree to license it under the project's [MIT license](LICENSE).

- Keep changes focused on observable user behavior.
- Implement operation behavior once in ArcboxCore, then expose it consistently to GUI/CLI/MCP.
- Preserve originals and reject existing output paths.
- Update English and Russian translations together; keep protocol error codes stable.
- Describe the verification performed, especially data round trips and error recovery.
- Do not commit private files, passwords, build outputs, or downloaded archive fixtures.
- Add focused behavioral tests and property tests where they express a domain invariant. Generate disposable fixtures; committed personal archives are forbidden.
- Run `./scripts/setup-quality.sh` once, then `./scripts/quality.sh --base origin/main` before committing. The default local check covers formatting, lint, complexity, module boundaries and tooling tests. Use `--full` for builds, application tests, coverage/CRAP and mutations when relevant.
- Failures require revision. Do not disable checks, bypass the hook or change thresholds just to pass. Explain genuine tooling/policy changes in the PR.
- GitHub CI and mandatory PRs are disabled. Maintainers can push locally validated changes directly to main; contributors may submit PRs for review. See the quality contract for scope. External services still require maintainer approval.

For a bug report, include macOS version, chip architecture, Arcbox version, archive format and minimal reproduction steps. A synthetic example is preferable to a personal archive.

For questions or collaboration, contact the maintainer through [Telegram or email](README.md#contact). English and Russian are welcome.
