---
type: Asset Provenance
description: Origin of the application icon and repository screenshots; read when replacing or redistributing visual assets.
created: "2026-11-07"
---
# Visual assets

## Application icon

`Resources/AppIcon.svg` is the production vector artwork. It uses two solid fills with transparent outside padding, without generated texture. `scripts/make-icon.swift` renders it through AppKit into every macOS icon size and builds Arcbox.icns. `docs/assets/icon.png` is the rendered README copy.

The initial concept was generated on 2026-11-07 with the built-in OpenAI image generation tool at the owner's request for a recognizable, minimalist archive icon. The generated raster contained unwanted mottling; attempts to remove it did not meet the flat-color requirement. For 0.2.1 the archive case, two files and compression strap were redrawn as SVG geometry. The final shipped artwork is the SVG, not the discarded generated raster. No Apple SF Symbol or WinRAR logo is used as application artwork.

Original concept prompt (historical):

> Use case: logo-brand. Asset type: final macOS application icon for Arcbox, an archive manager. Create ONE finished icon, not a concept sheet. Minimalist, instantly recognizable archive / compressed files symbol. A bold warm-white geometric archive case holding two simple layered file sheets, unified by a single narrow deep-green compression band; few large shapes, strong silhouette, no tiny zipper teeth. Original distinctive design, not a copy of WinRAR, Keka, Apple's Archive Utility or any existing icon. Restrained forest/teal green rounded-square macOS tile, with the warm-white archive mark centered; mostly flat, with only a very subtle tactile edge, no glossy 3D rendering, no gradients or glow. Standard macOS icon proportions: tile occupies about 84% of a 1024x1024 square canvas with even transparent outside padding and soft continuous corners. Main symbol should remain clear at 16 and 32 pixels. No letters, no A monogram, no text, no labels, no watermark, no surrounding scene, no mockup. Actual transparent background outside the green tile. Quiet, precise, beautiful utility icon.

## Screenshots

Repository screenshots show the actual Arcbox application, captured through the computer-use screenshot tool using synthetic demonstration files. They are not UI mockups and contain no personal archives. Screenshots are copied from the tool's recorded image output without modifying application content.
