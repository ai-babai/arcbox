## Behavior

Explain the concrete problem, requirement and resulting behavior.

## Quality

- [ ] Fast local `./scripts/quality.sh` passes.
- [ ] Relevant behavioral checks performed; use `--full` for app/core changes and report results.
- [ ] DRY: one owner for each rule; GUI/CLI/MCP reuse ArcboxCore.
- [ ] KISS/YAGNI: simplest implementation for the current requirement.
- [ ] SRP: changed modules have coherent responsibilities; no metric-only fragmentation.
- [ ] Tests assert observable behavior, including relevant error/cancellation cases.
- [ ] Originals, atomic outputs, EN/RU and the Open/Create/Extract journey are preserved.
- [ ] Relevant UI waits, resizing, animation and Reduce Motion were checked.

[Quality contract](https://github.com/ai-babai/arcbox/blob/main/docs/QUALITY.md) · [Русский](https://github.com/ai-babai/arcbox/blob/main/docs/QUALITY.ru.md)

## Verification and limitations

List observable checks/results and remaining boundaries. Identify the coverage base revision.
Explain any proposed tooling/policy change; do not silently suppress violations.
