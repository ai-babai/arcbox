---
type: Development Guide
description: Architecture, localization, build and release procedures for Arcbox contributors.
created: "2026-11-07"
---
# Development

## Structure

`ArcboxCore` owns archive operations, transactional output, volume discovery, checksums and messages. `ArcboxApp` presents them with SwiftUI/AppKit. `ArcboxCLI` exposes the same operations as JSON CLI and MCP tools. Keep operation behavior in the core.

The 7-Zip process is invoked with argument arrays. Passwords go through stdin. Extraction is confined to a new staging directory with macOS Seatbelt, then validated before publication. Multipart creation produces a complete volume directory atomically. Never replace user data silently.

## Build

```sh
./scripts/build.sh
open dist/Arcbox.app
./dist/arcbox --help
```

`./scripts/build.sh --universal` builds `arm64` and `x86_64` for macOS 14+, merges both app executables, copies the universal upstream engine and localization bundle, and signs the app ad hoc.

The pinned engine download is checked against SHA-256 in the build script. `vendor/`, `.build/` and `dist/` are generated and ignored. No package manager or runtime installation is needed on the receiving Mac.

The app bundle is assembled and signature-verified in staging before replacing the previous build. Executables inside an open build are not overwritten in place. Relaunch after building to load the new code.

## Localization

English is the default app and documentation language. The toolbar offers a visible EN/RU switch; View → Language also offers an explicit system-language option. The preference is stored locally.

Messages use `L(key, arguments...)` and matching catalogs in `Sources/ArcboxCore/Resources/{en,ru}.lproj/Localizable.strings`. Keys are the original Russian source phrases. Both translations must keep identical printf placeholders. The resource bundle must be copied into the application's Resources directory; do not rely on a local SwiftPM build path.

System-provided dialog chrome follows macOS language. App labels, prompts, statuses and core errors are localized. CLI/MCP error codes remain language-independent.

## Verification

Use temporary directories and disposable files to verify observable behavior: archive round trips, multipart creation/opening/extraction, missing or corrupt volumes, passwords, cancellation, unsafe paths, and EN/RU UI. Do not use personal archives as fixtures. Persistent tests/fixtures/CI checks require maintainer approval.

For packaging, verify each Mach-O architecture, ad-hoc signatures, the detached app's CLI from outside the repository, localization resources, DMG mount contents, and ZIP extraction. Verify SHA256SUMS after packaging.

## Release

1. Finish changes and update both READMEs and CHANGELOG.
2. Review the source tree for credentials, personal data and machine-specific paths.
3. Commit the exact source revision.
4. Run `./scripts/package-release.sh`.
5. Review `dist/release/` and its `release-info.json`; verify the assets.
6. Tag the source and attach DMG, ZIP, release-info and SHA256SUMS to the GitHub release.

Current packages are ad-hoc signed, not Apple-notarized. Do not describe them as Developer ID signed. Developer ID signing/notarization would require an Apple Developer certificate, hardened runtime signing and a notarization submission, followed by stapling and re-packaging. Never put those credentials in the repository.
