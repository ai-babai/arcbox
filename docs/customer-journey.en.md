---
type: Product Journey
description: Arcbox customer journeys for ordinary and multipart archives, recovery from errors, and agent parity.
created: "2026-11-07"
---
# One archive, however many parts

**English** · [Русский](customer-journey.md)

People want to send files or recover files they received. Splitting and joining belong inside those actions. The toolbar has three primary commands: **Open**, **Create**, **Extract**. The sidebar slides away when hidden, remembers its state, and respects Reduced Motion.

## Receive files

| Step | Person | Arcbox |
| :--- | :--- | :--- |
| Open | Chooses an archive or any of its volumes, or drops it into the window | Finds the first volume and its siblings. A selection of volumes from the same set opens that set. |
| Understand | Browses the contents | Shows one logical archive, its total size and part count. Recents contain one entry for the set. |
| Choose | Extracts everything or selects entries | Asks for the destination. No intermediate manual join is needed. |
| Run | Waits or cancels | Reads the complete set, verifies an adjacent manifest, and extracts into staging. |
| Finish | Opens the result in Finder | Publishes a new folder only after success. Source parts remain intact. |

Inputs include numeric `.001/.002`, `.partNN.rar`, legacy `.rar/.r00`, split ZIP `.z01/.zip`, and Arcbox manifests. Raw file parts show one original file; Extract restores it inside the new destination folder.

## Send files

| Step | Person | Arcbox |
| :--- | :--- | :--- |
| Create | Chooses files or drops source files | Opens one creation sheet. |
| Configure | Chooses ZIP, 7z or TAR | Offers compression and password controls where supported. |
| Fit the transfer | Enables Split into parts | Offers six size presets through a snapping slider, plus a custom size. The last part may be smaller. |
| Save | Chooses a name and location | Saves one archive file, or a new folder containing the complete part set. |
| Finish | Sends the set folder | Includes numeric parts and a SHA-256 manifest. Opens the completed set in Arcbox. |

To split an existing file without archiving, choose **Original file parts (.001)**. It accepts one file. Open → Extract restores the original bytes.

The creation sheet grows only for enabled options, within the available screen height. Format and compression share a row, password protection is optional, and a custom part size appears inline. Sources show two names and a remaining count; Choose reopens the full selection dialog. Cancel/Create stay outside the scroll area. Password protection requires a nonempty password before Create becomes available. Small screens scroll the form body while keeping its actions visible.

The empty archive browser centers its icon, message and Open action within the available content area. Hiding the sidebar recenters the group; the format notes remain a separate compact footer.

## Recover from errors

| Situation | Response |
| :--- | :--- |
| First or middle volume missing | Names the exact expected file. Add it beside the others and choose Retry. |
| Final volume missing from a manifest | Names the missing file before extraction. |
| Wrong part size | Explains that the download may be incomplete. |
| SHA-256 mismatch | Identifies the damaged part; no partial result is published. |
| Password required | Prompts within the current operation and resumes it. |
| Destination exists | Preserves existing data. The GUI suggests an unused folder name. |
| Cancellation or operation failure | Cleans unfinished output and preserves the sources. |

Without a manifest, an arbitrary binary set cannot prove that its final part exists. Restoration reports that completeness is unverified. Archive formats also have their own structure and integrity checks; a read error does not count as success. Checksums prove integrity, not the sender's identity.

## Agents follow the same journeys

- `list` accepts any volume and returns contents, `volumes` and `isFileParts`.
- `create` accepts optional `partBytes`; with it, `output` means a new set folder. The result includes `firstPart` and `parts`.
- `extract` accepts any volume and reads the complete set.
- MCP uses the same core contracts. Low-level `split` and `join` remain available to scripts without adding another human-facing workspace.
