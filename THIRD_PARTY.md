---
type: Third-Party Notices
description: Bundled 7-Zip version, provenance, licenses and corresponding source links.
created: "2026-11-07"
---
# Third-party software

## 7-Zip 26.05

Arcbox bundles the unmodified official macOS `7zz` executable by Igor Pavlov. Arcbox replaces its local code signature when assembling the application; it does not modify the engine source or compression behavior.

- [Official project](https://www.7-zip.org/)
- [Pinned release and downloads](https://github.com/ip7z/7zip/releases/tag/26.05)
- [Corresponding source tree](https://github.com/ip7z/7zip/tree/26.05)
- [Upstream license](https://www.7-zip.org/license.txt)
- Download: `https://github.com/ip7z/7zip/releases/download/26.05/7z2605-mac.tar.xz`
- SHA-256: `12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570`

Most 7-Zip code is licensed under GNU LGPL 2.1 or later; some parts use BSD terms. The unRAR-derived components carry an additional restriction against recreating the proprietary RAR compression algorithm from that code. Arcbox uses the engine to read RAR; RAR creation is not implemented.

The full upstream `License.txt` and `readme.txt` are included in every app at `Contents/Resources/7zip-license/`. The separate executable can be replaced with a compatible user-built 7-Zip executable; modifying a signed bundle requires signing it again locally.

## Apple frameworks

SwiftUI, AppKit, Foundation, CryptoKit and Quick Look are supplied by macOS. No framework, font or SF Symbols asset is redistributed separately. The application icon is original SVG artwork, redrawn from an initial generated concept. Its [provenance and prompt](docs/assets/README.md) are documented; `scripts/make-icon.swift` renders the SVG into the macOS icon sizes.
