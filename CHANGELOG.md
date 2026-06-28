# Changelog

All notable changes to VibeGo are documented here.

## [0.1.7] - 2026-06-28

### Added
- Sessions that exceed an agent's three inline rows now reveal a clickable "+n more sessions" row. Clicking it expands an in-place scrollable list (up to ten rows) so every session is reachable without a second window; closing and reopening the popup restores the collapsed summary.
- Clicking a CLI session now jumps to the exact terminal tab in Ghostty (joining Terminal and iTerm).
- The status bar menu gains an **About** submenu showing the version and a "View on GitHub" link.

### Changed
- Session rows now feel like real buttons: a stronger accent tint while pressed, and dragging the pointer out before release cancels the click.
- Completion-prompt titles that don't fit on one line wrap to two before truncating.
- Renamed "Show Completion Popup" to "Show Completion Prompt" and "Quit vibego" to "Quit". Toggling the prompt off now dismisses any open prompt immediately.

## [0.1.6] - 2026-06-28

### Fixed
- The editor extension is now packaged as a `.vsix` and installed through each editor's own CLI (`code`/`cursor --install-extension`). Previously the raw folder copy was garbage-collected by the editor on its next scan, so the bridge disappeared after a restart.

## [0.1.5] - 2026-06-28

### Fixed
- Clicking a session now restores an editor window that is covered by other apps or minimized to the Dock. The VibeGo app raises the window via the Accessibility API (grant VibeGo Accessibility once when prompted).

## [0.1.4] - 2026-06-28

### Fixed
- Editor terminal sessions were still routed to Terminal.app because the hook preserved a stale `terminalBundleId` (empty editor value lost to a `|| prev` fallback). The hook now writes the authoritative value.
- Clicking a session now raises the editor window even when it's covered by other apps or minimized — the bridge activates the app and un-minimizes before focusing the pane.

## [0.1.3] - 2026-06-28

### Fixed
- Editor-integrated terminals (VSCode/Cursor/Qoder) were misdetected as Terminal.app when the editor was launched from Terminal, so clicks opened Terminal instead of focusing the editor pane. `TERM_PROGRAM` is now authoritative; the process-tree fallback only runs when it's absent.

## [0.1.2] - 2026-06-28

### Added
- Clicking a CLI session now jumps to the exact integrated-terminal pane in VSCode, Cursor, and Qoder (in addition to Terminal.app and iTerm2), via a bundled VibeGo Bridge extension that auto-installs into each editor.

## [0.1.1] - 2026-06-27

### Added
- Completion popup now shows the source app icon and an arrow pointing back to the matching status bar segment.

### Changed
- Tightened completion popup spacing and made the source arrow smaller with a rounded tip.
- Refined the status bar into a single combined item for Claude and Codex, with animated active backgrounds.

### Fixed
- Update checks now ignore releases from the previous public version line.

## [0.1.0] - 2026-06-27

### Changed
- Restarted the public version line at 0.1.0.
