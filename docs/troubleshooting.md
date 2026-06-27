# Troubleshooting

Launch VibeGo once after installing it. It stays in the menu bar and the session hooks update it when Claude/Codex activity starts.

**The icon doesn't appear at all?**
- Make sure a Claude session is actually running. Start a new session (or restart Claude Code) and the bar appears automatically.
- A session that was already running *before* you installed gets picked up once it does something, but starting a fresh session is the reliable way to bring the bar up the first time.
- Confirm it's running with `pgrep -x vibego`: a number means it's running (it may just be hidden). If there is no output, open VibeGo again from Applications.
- If first-launch setup never took, run the installer manually: `node "/Applications/VibeGo.app/Contents/Resources/install.js"`
- Seeing 2 icons? The desktop app shows its own menu bar icon (the quick-screenshot one). To avoid two icons sitting side by side, open Claude's **Settings → General** and turn that built-in menu bar item off.

---
Back to the [README](../README.md).
