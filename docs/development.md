# Development

## Local testing restart loop

VibeGo is a menu bar app (`LSUIElement` — no Dock icon), so a rebuilt binary isn't
picked up until you quit the running instance and relaunch the fresh build. After
every code change:

```bash
./build.sh              # rebuild build/VibeGo.app
killall VibeGo          # quit the running instance (menu bar icon → Quit works too)
open build/VibeGo.app   # launch the freshly built copy
```

`killall VibeGo` stops whichever copy is running (the `build/` one or an installed
`/Applications/VibeGo.app`), so the new build is what comes back up.

If you changed hook or editor-bridge code, also refresh the installed hooks before
relaunching — the app only self-installs them on first launch:

```bash
node build/VibeGo.app/Contents/Resources/install.js
```

## Beta version policy

A `-betaN` version suffix (currently `0.1.2-beta1`) is for **local testing only**.
It is **never used for an official release** — beta builds are not signed/notarized
for distribution and the `-betaN` tag is not a valid public release number.

- Where the version is set (keep both in sync):
  - `build.sh` — `CFBundleVersion` and `CFBundleShortVersionString` in the `Info.plist` heredoc.
  - `editor-bridge/package.json` — `version`.
- For an official release: drop the `-betaN` suffix and set the real release version
  in both places first, then run `./build.sh --dmg` (which signs + notarizes). Do not
  ship a `-beta` version.

---
Back to the [README](../README.md).
