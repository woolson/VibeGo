#!/usr/bin/env node
// Installs the status-bar hooks into ~/.claude/settings.json (merging, never
// clobbering existing hooks) and copies update.js to ~/.claude/statusbar/.
// Re-runnable: existing status-bar hooks are stripped before re-adding.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const home = os.homedir();
const sbDir = path.join(home, ".claude", "statusbar");
const MARKER = sbDir; // every hook command we add points inside this dir
const updateDest = path.join(sbDir, "update.js");
const lifecycleDest = path.join(sbDir, "lifecycle.js");
const statuslineProxyDest = path.join(sbDir, "statusline-proxy.js");
const statuslineOriginalDest = path.join(sbDir, "statusline-original.json");
const codexDir = path.join(home, ".codex", "statusbar");
const codexUpdateDest = path.join(codexDir, "codex-update.js");
const codexLifecycleDest = path.join(codexDir, "codex-lifecycle.js");
const settingsPath = path.join(home, ".claude", "settings.json");
const codexSettingsPath = path.join(home, ".codex", "hooks.json");
const node = process.execPath;

fs.mkdirSync(sbDir, { recursive: true });
fs.rmSync(path.join(sbDir, "watcher.sh"), { force: true });
fs.copyFileSync(path.join(__dirname, "update.js"), updateDest);
fs.copyFileSync(path.join(__dirname, "lifecycle.js"), lifecycleDest);
fs.copyFileSync(path.join(__dirname, "statusline-proxy.js"), statuslineProxyDest);
fs.mkdirSync(codexDir, { recursive: true });
fs.copyFileSync(path.join(__dirname, "codex-update.js"), codexUpdateDest);
fs.copyFileSync(path.join(__dirname, "codex-lifecycle.js"), codexLifecycleDest);

const cmd = (evt) => `${node} ${updateDest} ${evt}`;
const life = (evt) => `${node} ${lifecycleDest} ${evt}`;

let settings = {};
if (fs.existsSync(settingsPath)) {
  settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  const bak = settingsPath + ".bak-statusbar";
  if (!fs.existsSync(bak)) fs.copyFileSync(settingsPath, bak);
}
settings.hooks = settings.hooks || {};

const currentStatusLine = settings.statusLine || settings.statusline || settings.status_line;
if (currentStatusLine && !(currentStatusLine.command || "").includes(statuslineProxyDest)) {
  fs.writeFileSync(statuslineOriginalDest, JSON.stringify(currentStatusLine, null, 2) + "\n");
} else if (!fs.existsSync(statuslineOriginalDest)) {
  fs.writeFileSync(statuslineOriginalDest, JSON.stringify(null) + "\n");
}
settings.statusLine = { type: "command", command: `${node} ${statuslineProxyDest}` };

const stripOurs = (arr) =>
  (arr || [])
    .map((entry) => ({
      ...entry,
      hooks: (entry.hooks || []).filter((h) => !(h.command || "").includes(MARKER)),
    }))
    .filter((entry) => (entry.hooks || []).length > 0);

const addUnmatched = (evt, command) => {
  settings.hooks[evt] = stripOurs(settings.hooks[evt]);
  settings.hooks[evt].push({ hooks: [{ type: "command", command }] });
};
const addMatched = (evt, command) => {
  settings.hooks[evt] = stripOurs(settings.hooks[evt]);
  settings.hooks[evt].push({ matcher: "*", hooks: [{ type: "command", command }] });
};

// Status hooks (drive the animation/label)
addUnmatched("UserPromptSubmit", cmd("prompt"));
addMatched("PreToolUse", cmd("pre"));
addMatched("PostToolUse", cmd("post"));
addUnmatched("Notification", cmd("notify"));
addMatched("PermissionRequest", cmd("permreq"));
addUnmatched("Stop", cmd("stop"));
// Lifecycle hooks (launch the app on open; the app stays resident until the user quits it)
addUnmatched("SessionStart", life("start"));
addUnmatched("SessionEnd", life("end"));

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
console.log("Installed status-bar hooks into", settingsPath);
console.log("Scripts:", updateDest, "and", lifecycleDest);
console.log("Backup (first run only):", settingsPath + ".bak-statusbar");

let codexSettings = { hooks: {} };
if (fs.existsSync(codexSettingsPath)) {
  codexSettings = JSON.parse(fs.readFileSync(codexSettingsPath, "utf8"));
  const bak = codexSettingsPath + ".bak-statusbar";
  if (!fs.existsSync(bak)) fs.copyFileSync(codexSettingsPath, bak);
}
codexSettings.hooks = codexSettings.hooks || {};

const codexStripOurs = (arr) =>
  (arr || [])
    .map((entry) => ({
      ...entry,
      hooks: (entry.hooks || []).filter((h) => !(h.command || "").includes(codexDir)),
    }))
    .filter((entry) => (entry.hooks || []).length > 0);

const addCodex = (evt, command, matcher) => {
  codexSettings.hooks[evt] = codexStripOurs(codexSettings.hooks[evt]);
  const entry = { hooks: [{ type: "command", command, timeout: 5 }] };
  if (matcher !== undefined) entry.matcher = matcher;
  codexSettings.hooks[evt].push(entry);
};

const codexCmd = (evt) => `${node} ${codexUpdateDest} ${evt}`;
const codexLife = (evt) => `${node} ${codexLifecycleDest} ${evt}`;

addCodex("SessionStart", codexLife("start"));
addCodex("SessionEnd", codexLife("end"));
addCodex("UserPromptSubmit", codexCmd("prompt"));
addCodex("PreToolUse", codexCmd("pre"), "");
addCodex("PostToolUse", codexCmd("post"), "");
addCodex("PostToolUseFailure", codexCmd("post"), "");
addCodex("Notification", codexCmd("notify"));
addCodex("PermissionRequest", codexCmd("permreq"));
addCodex("Stop", codexCmd("stop"));

fs.writeFileSync(codexSettingsPath, JSON.stringify(codexSettings, null, 2) + "\n");
console.log("Installed Codex status-bar hooks into", codexSettingsPath);
console.log("Codex scripts:", codexUpdateDest, "and", codexLifecycleDest);
console.log("Codex backup (first run only):", codexSettingsPath + ".bak-statusbar");

// --- VibeGo Bridge editor extension (VSCode / Cursor / Qoder) ---
// Install the bundled .vsix so VibeGo can focus the exact integrated terminal a CLI session runs
// in. VSCode-fork editors manage their extensions dir and garbage-collect folders they didn't
// install themselves, so install through each editor's own CLI (`--install-extension` registers
// the extension in the editor's DB and survives later scans). Fall back to a raw folder copy for
// editors whose CLI isn't on PATH.
function whichCli(cmd) {
  try {
    return cp.execFileSync("which", [cmd], { encoding: "utf8", timeout: 2000 }).trim() || "";
  } catch { return ""; }
}

function installEditorBridge() {
  const vsix = path.join(__dirname, "editor-bridge.vsix");
  const folderSrc = path.join(__dirname, "editor-bridge");
  if (!fs.existsSync(vsix)) {
    console.log("editor-bridge.vsix not bundled; skipping editor extension.");
    return;
  }
  let version = "0.0.0";
  try {
    version = JSON.parse(fs.readFileSync(path.join(folderSrc, "package.json"), "utf8")).version || version;
  } catch {}
  const editors = [
    { cli: "code", dir: path.join(home, ".vscode", "extensions") },
    { cli: "cursor", dir: path.join(home, ".cursor", "extensions") },
    { cli: "qoder", dir: path.join(home, ".qoder", "extensions") },
  ];
  for (const e of editors) {
    const bin = whichCli(e.cli);
    if (bin) {
      try {
        cp.execFileSync(bin, ["--install-extension", vsix, "--force"], { stdio: "ignore", timeout: 30000 });
        console.log("Installed VibeGo Bridge via", e.cli);
        continue;
      } catch (err) {
        console.log(e.cli, "CLI install failed:", err.message, "— trying folder copy");
      }
    }
    // Fallback: direct folder copy (editors without the CLI on PATH; may be GC'd on a later scan).
    if (fs.existsSync(e.dir) && fs.existsSync(folderSrc)) {
      try {
        for (const entry of fs.readdirSync(e.dir)) {
          // Clean any prior install, including the "vibogo" typo from older builds.
          if (entry.startsWith("vibego.bridge-") || entry.startsWith("vibogo.bridge-")) {
            fs.rmSync(path.join(e.dir, entry), { recursive: true, force: true });
          }
        }
        cp.execFileSync("cp", ["-R", folderSrc, path.join(e.dir, "vibego.bridge-" + version)]);
        console.log("Installed VibeGo Bridge (folder fallback) into", e.dir);
      } catch (err2) {
        console.log("Skipped", e.cli, ":", err2.message);
      }
    } else if (!bin) {
      console.log("Skipped", e.cli, "(no CLI on PATH and no extensions dir)");
    }
  }
}
installEditorBridge();
