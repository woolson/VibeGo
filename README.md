## VibeGo

[中文](README.zh-CN.md)

<p>
  <img src="assets/vibego-icon-concept.png" alt="VibeGo app icon" width="96" align="right">
</p>

A tiny macOS menu bar app that shows **Claude Code and Codex live status**: animated icons while agents are thinking or running tools, a yellow permission state when they need you, elapsed timers for active turns, completion feedback, and Codex quota details. Lightweight, no window, no dock icon, no dashboards.

Built so you can tab away during a long run and still see, at a glance, whether Claude or Codex is working, waiting on you, or done.

<a href="https://github.com/woolson/VibeGo/releases/latest/download/VibeGo.dmg"><img src="assets/download.png" alt="Download VibeGo.dmg for macOS" width="260"></a>
<br>

## Demo

![VibeGo demo](screenshots/demo.gif)

[Watch the MP4 demo](screenshots/demo.mp4)

---

## Preview

**Status bar**

| Idle | Thinking | Tool |
|---|---|---|
| ![Idle status bar](screenshots/preview-idle.png) | ![Thinking status bar with timer](screenshots/preview-thinking.png) | ![Tool status bar](screenshots/preview-tool.png) |

| Permission | Claude + Codex |
|---|---|
| ![Permission status bar](screenshots/preview-permission.png) | ![Combined Claude and Codex status bar](screenshots/preview-combined.png) |

**Task complete**

![Task complete status bar](screenshots/preview-done.png)

**Completion popup**

![Completion popup](screenshots/preview-completion-popup.png)

## What it shows

- **Thinking / working** — the status icon animates with a live `1m 12s` timer.
- **Running a tool** — a short label such as `Editing`, `Reading`, `Running command`, or `Using tool`.
- **Awaiting permission** — a paused yellow state when Claude Code or Codex needs approval.
- **Task complete** — returns to the resting VibeGo icon, with optional completion sound and popup.
- **Claude + Codex together** — tracks both agents from their hook state files and combines active sessions into one menu-bar readout when needed.
- **Session menu** — shows recent Claude and Codex sessions, including project/title and status, with overflow when there are many sessions.
- **Open the right place** — clicking a session opens its conversation, or jumps to the exact terminal tab it runs in (Terminal, iTerm, Ghostty, or a VS Code / Cursor / Qoder pane). See [Clicking a session](#clicking-a-session).
- **Codex limits** — shows two vertical 5-block meters: the left column is the 5-hour window remaining, the right column is the 7-day window remaining. Click it for plan, context, reset, and update details.

Everything is controlled from the menu:

- **Show timer:** toggle the elapsed `1m 1s` clock.
- **Play completion sound:** a soft chime when a turn longer than a minute finishes.
- **Show completion popup:** a small transient popup below the menu-bar icon when a turn finishes.
- **Version and update:** the menu shows your current version, with a one-click "Update available" when a newer release exists.

## Where it works

| Surface | Tracked? |
|---|---|
| Claude Code CLI (terminal) | ✅ |
| Claude Code Desktop — **Code** tab | ✅ |
| Cursor (Claude Code extension) | ✅ |
| Claude Desktop — **Chat** tab | ❌ |
| **Cowork** | ❌ |
| Codex CLI / app hooks | ✅ |

## Clicking a session

Click any session in the menu to jump back to where it runs. What opens depends on where the session lives:

| Session runs in | Tracked? | Click opens |
|---|---|---|
| Claude Code / Codex CLI in **Terminal.app** | ✅ | The exact Terminal tab |
| Claude Code / Codex CLI in **iTerm2** | ✅ | The exact iTerm tab |
| Claude Code / Codex CLI in **Ghostty** | ✅ | The exact Ghostty tab |
| CLI in **VS Code / Cursor / Qoder** integrated terminal | ✅ | The exact editor pane ¹ |
| CLI in **Warp / WezTerm / kitty / Alacritty** | ✅ | The terminal app (a specific tab isn't addressable) |
| Claude Code Desktop — **Code** tab | ✅ | The conversation in Claude Desktop |
| **Codex** app | ✅ | The conversation in Codex |
| Claude Desktop — **Chat** tab | ❌ | — |
| **Cowork** | ❌ | — |

¹ Needs the bundled **VibeGo Bridge** extension in that editor. It's installed into VS Code, Cursor, and Qoder automatically on first launch. Covered or minimized editor windows are also raised to the front — grant VibeGo Accessibility once when prompted. If a terminal tab can't be matched, the click falls back to opening the session's transcript file.

## Requirements

- macOS 12+
- [Claude Code](https://claude.com/claude-code) (CLI or the Desktop app)
- Node.js

## Install

### Option A — DMG (recommended)

Open it, drag the app to Applications, launch once. Builds made without an Apple
Developer ID may require right-click Open or approval in System Settings on first
launch.

1. Download the latest `VibeGo.dmg` from [Releases](../../releases).
2. Open it and drag **VibeGo** into Applications.
3. Launch it once. On first launch it wires up the Claude Code and Codex hooks for you automatically.
4. Start a new Claude Code or Codex session, the icon updates whenever an agent is active.

### Updating

VibeGo uses Sparkle for automatic updates. Open **About** from the menu bar item,
then choose **Check for Updates…** to check, download, and replace the app.

Updates are verified with Sparkle EdDSA signatures even when the app is not
Developer ID signed. macOS may still show unsigned/unnotarized-app warnings for
fresh installs. Launch the new version once, it refreshes its hooks on a version
change, then restart Claude Code to pick them up.

### Option B — Claude Code plugin

Installs the hooks (status + open/close lifecycle) automatically from inside Claude Code:

```
/plugin marketplace add woolson/VibeGo
/plugin install vibego@VibeGo
```

The plugin installs the hooks but not the app itself, so drag **VibeGo** into Applications once (from the DMG). The plugin launches it automatically on session start unless you explicitly quit the app.

## How it works

The app is stateless. Claude Code hooks write the current status to `~/.claude/statusbar/state.json`; Codex hooks write to `~/.codex/statusbar/state.json`. Per-session files live under each agent's `sessions.d` directory, so the menu can show multiple recent sessions while the menu bar stays compact. The app polls those files every 0.4s and renders the current active agent or a combined Claude + Codex readout.

Codex rate-limit data is read from the latest `token_count` event under `~/.codex/sessions/`, using the 300-minute primary window and 10080-minute secondary window. CLI hooks also record terminal metadata, including app bundle id and TTY, so clicking a CLI session can jump back to the matching tab in Terminal, iTerm, or Ghostty, or the matching pane in VS Code / Cursor / Qoder (via the VibeGo Bridge extension).

The installer merges its hooks into `~/.claude/settings.json` (backing it up first), and the app's only network call is a once-a-day GitHub release check ([details](docs/privacy.md)).

## Acknowledgements

VibeGo is built on top of the ideas and groundwork from the original [claude-statusbar](https://github.com/m1ckc3s/claude-status-bar) project. Thank you to the original author for making a small, useful menu-bar status idea open and hackable.

## Uninstall

```bash
node "/Applications/VibeGo.app/Contents/Resources/uninstall.js"   # removes only our hooks
```
Then drag the app to the Trash.

## Trademark / Not Affiliated

This is an unofficial, open-source side project. **It is not affiliated with, endorsed by, or sponsored by Anthropic.** "Claude" and the Claude spark logo are trademarks of Anthropic, used here nominatively. This project is MIT licensed, but that covers the source code only and conveys no rights to Anthropic's trademarks or brand.

If I'm violating or impeding your trademark, Contact me on X Chat ([@mickces](https://x.com/mickces))
This is a free side project; I'm not monetizing it.

## License

MIT
