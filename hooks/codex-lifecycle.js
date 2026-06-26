#!/usr/bin/env node
// SessionStart/SessionEnd bridge for Codex.
// Usage: node codex-lifecycle.js <start|end>

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const BUNDLE_ID = "com.local.vibego";
const OLD_BUNDLE_ID = "com.local.claudestatusbar";
const dir = path.join(os.homedir(), ".codex", "statusbar");
const sessDir = path.join(dir, "sessions.d");
const stateDir = path.join(dir, "states.d");
const statePath = path.join(dir, "state.json");
const event = process.argv[2];

fs.mkdirSync(sessDir, { recursive: true });

let raw = "", done = false;
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => run());
process.stdin.on("error", () => run());
setTimeout(run, 1000);

function run() {
  if (done) return;
  done = true;
  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}
  const id = safeId(p.session_id || p.sessionId || p.conversation_id || p.thread_id || "codex");

  if (event === "start") {
    try { fs.writeFileSync(path.join(sessDir, id), ""); } catch {}
    clearStaleState(id);
    launchApp();
  } else if (event === "end") {
    try { fs.rmSync(path.join(sessDir, id), { force: true }); } catch {}
    try { fs.rmSync(path.join(stateDir, id + ".json"), { force: true }); } catch {}
    clearStaleState(id);
  }
  process.exit(0);
}

function launchApp() {
  const child = cp.spawn("open", ["-g", "-b", BUNDLE_ID], { stdio: "ignore", detached: true });
  child.on("error", () => {
    cp.spawn("open", ["-g", "-b", OLD_BUNDLE_ID], { stdio: "ignore", detached: true }).unref();
  });
  child.unref();
}

function clearStaleState(id) {
  try {
    const prev = JSON.parse(fs.readFileSync(statePath, "utf8"));
    const prevId = safeId(prev.sessionId);
    if (prevId && prevId !== id) return;
    if (!["thinking", "tool", "permission"].includes(prev.state)) return;
    const out = { ...prev, state: "idle", label: "", startedAt: 0, ts: Math.floor(Date.now() / 1000) };
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
  } catch {}
}

function safeId(s) {
  return String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "unknown";
}
