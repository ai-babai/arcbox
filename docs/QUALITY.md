---
type: Quality Policy
description: Local quality checks and a separate full verification for Arcbox; principles and metric scope for contributors.
created: "2026-11-07"
---
# Quality contract

[Русский](QUALITY.ru.md) · [Contributing](../CONTRIBUTING.md)

## Everyday work

```sh
./scripts/setup-quality.sh  # once
./scripts/quality.sh        # also runs automatically before a commit
```

The default is a fast local check: formatting, lint, Swift complexity, module boundaries, EN/RU catalogs and tooling behavior tests. It does not build the application, download its engine or run mutation tests. Failures block the commit. The hook verifies that the staged tree matches the source checked, including edits made during validation.

GitHub Actions and mandatory PR/status requirements were removed at the owner's request on 2026-11-07. Maintainers can push validated changes directly to main. Contributors may use PRs for review; GitHub does not run this gate. Main retains protection against force-push and deletion.

## Full verification

For archive behavior, core/UI changes and releases, run locally:

```sh
./scripts/setup-quality.sh --full  # additionally installs Muter
./scripts/quality.sh --full --base origin/main
```

This adds the application build, XCTest/SwiftCheck, CLI/MCP contract cases, LLVM coverage, CRAP(line), diff coverage and scoped mutation testing. It is a deliberate verification step, not a prerequisite for every script/documentation commit. Use the relevant behavioral checks for the change; record the commands and results.

## Rules and tools

| Check | Limit | Scope/tool |
| --- | --- | --- |
| Formatting and lint | No diagnostics or differences | Swift-format (Xcode 16.4), SwiftLint 0.65.1; Sources, Tests, Package.swift |
| Source size | File ≤500, function ≤80, type ≤450 lines | SwiftLint; body counts exclude blank/comment lines |
| Swift complexity | Cyclomatic ≤10, cognitive ≤15 per function/accessor | swift-complexity 1.6.0 / SwiftSyntax; all production Swift |
| Shell | No diagnostics or formatting differences | ShellCheck 0.11.0, shfmt 3.14.1; scripts/**/*.sh and Git hook |
| Python | Lint/format pass; McCabe ≤10 | Ruff 0.14.4; all Python tooling/tests |
| Modules and translations | Zero module cycles; core independent of adapters; matching EN/RU keys/placeholders | SwiftPM graph/compiler, catalog checker |
| Full: CRAP(line) | Mean <5, maximum ≤30 | ArcboxCore; complexity + LLVM executable-line coverage |
| Full: diff coverage | ≥80% changed executable lines against the supplied base | ArcboxCore; LLVM → diff-cover 9.7.0 |
| Full: behavior | All cases pass | XCTest, SwiftCheck (100 generated cases/property), compiled CLI/MCP |
| Full: mutations | Nonempty run; all scoped mutants killed | Muter 16; ArchivePathPolicy/PartStream; relational/logical replacements |

Use macOS with Xcode 16.4 / Swift 6.1.2. Python tools are hash-locked in an ignored environment. Tool versions and policies change together. Do not bypass hooks or silently suppress violations.

CRAP(line) = `C² × (1 − coverage)³ + C`. This uses **line coverage**, not basis-path coverage. The adapter matches SwiftSyntax functions to LLVM code regions; unmatched functions get zero coverage. Reports live in `.build/quality/`. A diff without executable core lines has no coverage denominator. UI/CLI do not have numeric coverage gates; relevant UI journeys still require verification.

Mutation results cover two critical policies, not the whole project. Compilation errors, timeouts, survivors and empty reports fail. Muter 16 has non-ASCII mutation-placement issues; the selected policy/streaming files are ASCII. Shell lint does not measure cognitive complexity or coverage.

## Design and review

- **DRY:** one owner for archive behavior in ArcboxCore; adapters call it. Share proven rules, not superficial similarities.
- **KISS:** direct value types and native tools. Helpers name real responsibilities; no fragmentation merely to satisfy metrics.
- **YAGNI:** current Open/Create/Extract requirements; no speculative configuration/frameworks.
- **SOLID / SRP:** separate orchestration, processes, metadata, validation and streaming. Tooling follows the same rule: thin shell entry, named Python phases, standalone Python modules checked by Ruff.
- Review originals/atomic outputs, failure/cancel paths, meaningful behavioral tests, EN/RU, truthful animated waits and Reduce Motion.

Tools support this review; they cannot certify the design principles.
