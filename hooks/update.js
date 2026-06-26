#!/usr/bin/env node
// Invoked by Claude Code hooks. Reads the hook JSON payload on stdin, maps the
// event to a status, and atomically writes ~/.claude/statusbar/state.json.
// Usage: node update.js <prompt|pre|post|notify|permreq|stop>

const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".claude", "statusbar");
const statePath = path.join(dir, "state.json");
const stateDir = path.join(dir, "states.d");
const limitsPath = path.join(dir, "limits.json");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", Edit: "Editing", Write: "Writing", MultiEdit: "Editing",
  NotebookEdit: "Editing", Read: "Reading", Grep: "Searching", Glob: "Searching",
  WebFetch: "Browsing web", WebSearch: "Searching web", Task: "Delegating",
  TodoWrite: "Planning",
};

function detectClient(p) {
  const explicit = String(p.client || p.client_type || p.entrypoint || p.source || p.app || "").toLowerCase();
  if (explicit.includes("desktop") || explicit === "app" || explicit.includes("claude.app")) return "app";
  if (explicit.includes("cli") || explicit.includes("terminal")) return "cli";

  const chain = processChain();
  if (chain.some((s) => s.includes(".app/contents/") || s.includes("claude helper") || s.includes("claude.app"))) {
    return "app";
  }
  if (process.env.TERM_PROGRAM || process.env.TERM_SESSION_ID || process.env.SSH_TTY ||
      chain.some((s) => /(^|\/)(terminal|iterm2?|ghostty|wezterm|alacritty|kitty|warp)(\.app)?(\s|\/|$)/.test(s))) {
    return "cli";
  }
  return "";
}

function processChain() {
  const out = [];
  let pid = process.ppid;
  for (let i = 0; i < 8 && pid > 1; i++) {
    try {
      const text = require("child_process")
        .execFileSync("ps", ["-p", String(pid), "-o", "ppid=", "-o", "command="], { encoding: "utf8", timeout: 300 })
        .trim();
      if (!text) break;
      const match = text.match(/^(\d+)\s+(.+)$/);
      if (!match) break;
      pid = Number(match[1]);
      out.push(match[2].toLowerCase());
    } catch {
      break;
    }
  }
  return out;
}

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}
  writeLimitsFromPayload(p);

  // Off by default; CLAUDE_STATUSBAR_DEBUG=1 logs every hook invocation to hooks.log.
  if (process.env.CLAUDE_STATUSBAR_DEBUG === "1") {
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.appendFileSync(path.join(dir, "hooks.log"),
        `${new Date().toISOString()} [${event}] tool=${p.tool_name || "-"} mode=${p.permission_mode || "-"} msg=${JSON.stringify(p.message || "").slice(0, 160)} keys=${Object.keys(p).join(",")}\n`);
    } catch {}
  }

  // Register the session here too, so a session that predates the hook install (never
  // fired SessionStart) still gets tracked once it does anything. See CLAUDE.md gotcha.
  const sid = String(p.session_id || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64);
  if (sid) {
    try {
      const sessDir = path.join(dir, "sessions.d");
      fs.mkdirSync(sessDir, { recursive: true });
      fs.writeFileSync(path.join(sessDir, sid), "");
    } catch {}
  }

  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}

  const project = p.cwd ? path.basename(p.cwd) : prev.project || "";
  const ts = Math.floor(Date.now() / 1000);
  let state = "idle", label = "", startedAt = prev.startedAt || 0;

  switch (event) {
    case "prompt":
      state = "thinking"; label = "Thinking…"; startedAt = ts; break;
    case "pre": {
      const t = p.tool_name || "";
      // Known tools get a friendly verb; everything else (incl. long mcp__server__method
      // names) collapses to a generic "Using tool".
      state = "tool"; label = TOOL_LABELS[t] || "Using tool";
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "notify": {
      // Only a permission prompt drives the icon here (CLI path; desktop uses permreq). Ignore
      // every other Notification (esp. the idle_prompt "Claude is waiting for your input") so the
      // icon rests instead of parking on a confusing "Waiting for you". See CLAUDE.md.
      const m = (p.message || "").toLowerCase();
      const isPerm = p.notification_type === "permission_prompt" ||
        m.includes("permission") || m.includes("approve") || m.includes("allow");
      if (!isPerm) return;
      state = "permission"; label = "Awaiting permission"; startedAt = 0;
      break;
    }
    case "permreq":
      // Desktop-app permission signal; not redundant with notify (that's CLI-only). See CLAUDE.md.
      state = "permission"; label = "Awaiting permission"; startedAt = 0; break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    default:
      return;
  }

  const out = { state, label, tool: p.tool_name || "", project, sessionId: p.session_id || "", transcript: p.transcript_path || prev.transcript || "", client: detectClient(p) || prev.client || "", startedAt, ts };
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.mkdirSync(stateDir, { recursive: true });
    const tmp = statePath + "." + process.pid + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, statePath);
    if (sid) {
      const sessionPath = path.join(stateDir, sid + ".json");
      const sessionTmp = sessionPath + "." + process.pid + ".tmp";
      fs.writeFileSync(sessionTmp, JSON.stringify(out));
      fs.renameSync(sessionTmp, sessionPath);
    }
  } catch {}
});

function writeLimitsFromPayload(p) {
  const rate = p.rate_limits || {};
  const five = rate.five_hour || {};
  const seven = rate.seven_day || {};
  const fiveUsed = number(five.used_percentage);
  const sevenUsed = number(seven.used_percentage);
  if (fiveUsed == null && sevenUsed == null) return;

  const out = {
    source: "claude",
    planType: string(p.plan?.name || p.account?.plan || ""),
    modelContextWindow: number(p.context_window?.max_tokens) || 0,
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
