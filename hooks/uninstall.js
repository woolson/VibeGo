#!/usr/bin/env node
// Removes the status-bar hooks from Claude and Codex settings. Leaves all other hooks intact.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const home = os.homedir();
// Match the dir, not "update.js": the narrower marker used to orphan the lifecycle hooks.
const MARKER = path.join(home, ".claude", "statusbar");
const CODEX_MARKER = path.join(home, ".codex", "statusbar");
const settingsPath = path.join(home, ".claude", "settings.json");
const codexSettingsPath = path.join(home, ".codex", "hooks.json");
const statuslineOriginalPath = path.join(MARKER, "statusline-original.json");

// Tear down the desktop watcher LaunchAgent (best-effort; safe if absent).
const NEW_AGENT_LABEL = "com.local.vibego.watcher";
const newAgentPlist = path.join(home, "Library", "LaunchAgents", NEW_AGENT_LABEL + ".plist");
try { cp.execSync(`launchctl bootout gui/${process.getuid()}/${NEW_AGENT_LABEL}`, { stdio: "ignore" }); } catch {}
if (fs.existsSync(newAgentPlist)) { fs.rmSync(newAgentPlist); console.log("Removed vibego watcher LaunchAgent."); }
try { cp.execSync("pkill -x vibego", { stdio: "ignore" }); } catch {}

if (fs.existsSync(settingsPath)) {
  const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
  for (const evt of Object.keys(settings.hooks || {})) {
    settings.hooks[evt] = (settings.hooks[evt] || [])
      .map((e) => ({ ...e, hooks: (e.hooks || []).filter((h) => !(h.command || "").includes(MARKER)) }))
      .filter((e) => (e.hooks || []).length > 0);
    if (settings.hooks[evt].length === 0) delete settings.hooks[evt];
  }
  if ((settings.statusLine?.command || "").includes(MARKER)) {
    let original = null;
    try { original = JSON.parse(fs.readFileSync(statuslineOriginalPath, "utf8")); } catch {}
    if (original) settings.statusLine = original;
    else delete settings.statusLine;
  }
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  console.log("Removed status-bar hooks from", settingsPath);
} else {
  console.log("No Claude settings.json; skipping Claude hooks.");
}

if (fs.existsSync(codexSettingsPath)) {
  const codexSettings = JSON.parse(fs.readFileSync(codexSettingsPath, "utf8"));
  for (const evt of Object.keys(codexSettings.hooks || {})) {
    codexSettings.hooks[evt] = (codexSettings.hooks[evt] || [])
      .map((e) => ({ ...e, hooks: (e.hooks || []).filter((h) => !(h.command || "").includes(CODEX_MARKER)) }))
      .filter((e) => (e.hooks || []).length > 0);
    if (codexSettings.hooks[evt].length === 0) delete codexSettings.hooks[evt];
  }
  fs.writeFileSync(codexSettingsPath, JSON.stringify(codexSettings, null, 2) + "\n");
  console.log("Removed Codex status-bar hooks from", codexSettingsPath);
}

// --- Remove the VibeGo Bridge editor extension (CLI uninstall, then folder sweep) ---
function whichCli(cmd) {
  try { return cp.execFileSync("which", [cmd], { encoding: "utf8", timeout: 2000 }).trim() || ""; } catch { return ""; }
}
(function removeEditorBridge() {
  for (const cmd of ["code", "cursor", "qoder"]) {
    const bin = whichCli(cmd);
    if (!bin) continue;
    try {
      cp.execFileSync(bin, ["--uninstall-extension", "vibego.bridge"], { stdio: "ignore", timeout: 15000 });
      console.log("Uninstalled VibeGo Bridge via", cmd);
    } catch {}
  }
  // Folder sweep for any installed via the folder fallback.
  for (const extDir of [".vscode", ".vscode-insiders", ".cursor", ".qoder"].map((p) => path.join(home, p, "extensions"))) {
    if (!fs.existsSync(extDir)) continue;
    try {
      for (const entry of fs.readdirSync(extDir)) {
        if (entry.startsWith("vibego.bridge-")) {
          fs.rmSync(path.join(extDir, entry), { recursive: true, force: true });
          console.log("Removed", path.join(extDir, entry));
        }
      }
    } catch {}
  }
})();
