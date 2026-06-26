#!/usr/bin/env node
// Captures Claude Code statusLine rate-limit data, then delegates to the user's
// original statusLine command so terminal output keeps working.

const fs = require("fs");
const os = require("os");
const path = require("path");
const cp = require("child_process");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const limitsPath = path.join(dir, "limits.json");
const originalPath = path.join(dir, "statusline-original.json");

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", run);
process.stdin.on("error", run);
setTimeout(run, 1500);

let done = false;
function run() {
  if (done) return;
  done = true;

  let input = {};
  try { input = JSON.parse(raw || "{}"); } catch {}
  writeLimits(input);
  delegate(raw);
}

function writeLimits(input) {
  const rate = input.rate_limits || {};
  const five = rate.five_hour || {};
  const seven = rate.seven_day || {};
  const fiveUsed = number(five.used_percentage);
  const sevenUsed = number(seven.used_percentage);
  if (fiveUsed == null && sevenUsed == null) return;

  const out = {
    source: "claude",
    planType: string(input.plan?.name || input.account?.plan || ""),
    modelContextWindow: number(input.context_window?.max_tokens) || 0,
    fiveHour: limitFromUsed(fiveUsed, five.resets_at || five.reset_at),
    sevenDay: limitFromUsed(sevenUsed, seven.resets_at || seven.reset_at),
    ts: Math.floor(Date.now() / 1000),
  };
  try {
    fs.mkdirSync(dir, { recursive: true });
    const tmp = limitsPath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, limitsPath);
  } catch {}
}

function limitFromUsed(used, reset) {
  if (used == null) return null;
  return {
    remainingPercent: Math.max(0, Math.min(100, 100 - used)),
    resetsAt: resetSeconds(reset),
  };
}

function delegate(input) {
  let original = null;
  try { original = JSON.parse(fs.readFileSync(originalPath, "utf8")); } catch {}
  const command = original && typeof original.command === "string" ? original.command : "";
  if (!command.trim()) return;
  const result = cp.spawnSync("/bin/sh", ["-lc", command], {
    input,
    encoding: "utf8",
    timeout: 2500,
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
}

function number(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function string(v) {
  return typeof v === "string" ? v : "";
}

function resetSeconds(v) {
  if (v == null || v === "") return 0;
  if (typeof v === "number") return v > 100000000000 ? v / 1000 : v;
  const n = Number(v);
  if (Number.isFinite(n)) return n > 100000000000 ? n / 1000 : n;
  const d = Date.parse(String(v));
  return Number.isFinite(d) ? d / 1000 : 0;
}
