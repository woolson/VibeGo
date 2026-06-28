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
  if (process.env.TERM_PROGRAM || process.env.TERM_SESSION_ID || process.env.SSH_TTY ||
      chain.some((s) => /(^|\/)(terminal|iterm2?|ghostty|wezterm|alacritty|kitty|warp)(\.app)?(\s|\/|$)/.test(s))) {
    return "cli";
  }
  if (chain.some((s) => s.includes("claude helper") || s.includes("claude.app"))) {
    return "app";
  }
  return "";
}

function terminalMetadata() {
  const termProgram = String(process.env.TERM_PROGRAM || "");
  const tty = currentTTY();
  const lowerTerm = termProgram.toLowerCase();
  let terminalApp = termProgram;
  let terminalBundleId = "";

  if (lowerTerm === "apple_terminal") {
    terminalApp = "Terminal";
    terminalBundleId = "com.apple.Terminal";
  } else if (lowerTerm.includes("iterm")) {
    terminalApp = "iTerm";
    terminalBundleId = "com.googlecode.iterm2";
  } else if (lowerTerm.includes("warp")) {
    terminalApp = "Warp";
    terminalBundleId = "dev.warp.Warp-Stable";
  } else if (lowerTerm.includes("wezterm")) {
    terminalApp = "WezTerm";
    terminalBundleId = "com.github.wez.wezterm";
  } else if (lowerTerm.includes("ghostty")) {
    terminalApp = "Ghostty";
    terminalBundleId = "com.mitchellh.ghostty";
  } else if (lowerTerm.includes("kitty")) {
    terminalApp = "kitty";
    terminalBundleId = "net.kovidgoyal.kitty";
  } else if (lowerTerm.includes("alacritty")) {
    terminalApp = "Alacritty";
    terminalBundleId = "org.alacritty";
  } else if (lowerTerm.includes("vscode") || lowerTerm.includes("cursor") || lowerTerm.includes("qoder")) {
    // Editor-integrated terminal. No dedicated bundle id — VibeGo routes these to the editor bridge
    // instead of AppleScript, so leave terminalBundleId empty.
    terminalApp = "vscode";
    terminalBundleId = "";
  }

  // Only infer from the process tree when TERM_PROGRAM was absent. Walking the full ancestor chain
  // would misclassify an editor launched from Terminal (its ancestors include Terminal.app).
  if (!terminalApp && !terminalBundleId) {
    const chain = processChain();
    const joined = chain.join("\n");
    if (joined.includes("terminal.app")) { terminalApp = "Terminal"; terminalBundleId = "com.apple.Terminal"; }
    else if (joined.includes("iterm")) { terminalApp = "iTerm"; terminalBundleId = "com.googlecode.iterm2"; }
    else if (joined.includes("warp.app")) { terminalApp = "Warp"; terminalBundleId = "dev.warp.Warp-Stable"; }
    else if (joined.includes("wezterm")) { terminalApp = "WezTerm"; terminalBundleId = "com.github.wez.wezterm"; }
    else if (joined.includes("ghostty")) { terminalApp = "Ghostty"; terminalBundleId = "com.mitchellh.ghostty"; }
    else if (joined.includes("kitty.app")) { terminalApp = "kitty"; terminalBundleId = "net.kovidgoyal.kitty"; }
    else if (joined.includes("alacritty")) { terminalApp = "Alacritty"; terminalBundleId = "org.alacritty"; }
  }

  const terminalSessionId = terminalBundleId === "com.mitchellh.ghostty" ? ghosttyTerminalId() : "";
  return { terminalApp, terminalBundleId, terminalSessionId, tty };
}

function ghosttyTerminalId() {
  try {
    return require("child_process")
      .execFileSync("osascript", [
        "-e", "tell application id \"com.mitchellh.ghostty\"",
        "-e", "if (count of windows) is 0 then return \"\"",
        "-e", "return id of focused terminal of selected tab of front window as string",
        "-e", "end tell",
      ], { encoding: "utf8", timeout: 500, stdio: ["ignore", "pipe", "ignore"] })
      .trim();
  } catch {
    return "";
  }
}

function ttyOfPid(pid) {
  try {
    const t = require("child_process")
      .execFileSync("ps", ["-p", String(pid), "-o", "tty="], { encoding: "utf8", timeout: 300 })
      .trim();
    if (t && t !== "??" && t !== "?") return t.startsWith("/") ? t : `/dev/${t}`;
  } catch {}
  return "";
}

function ppidOf(pid) {
  try {
    return Number(require("child_process")
      .execFileSync("ps", ["-p", String(pid), "-o", "ppid="], { encoding: "utf8", timeout: 300 })
      .trim());
  } catch {
    return 0;
  }
}

function currentTTY() {
  if (process.env.TTY) return String(process.env.TTY);
  // Claude Code runs hooks as a detached child with no controlling terminal, so this node
  // process's own tty is "??". Walk the parent chain up to the Claude CLI (which still owns
  // the terminal tab) and borrow its tty — that's the tab VibeGo must switch to.
  let pid = process.pid;
  for (let i = 0; i < 12 && pid > 1; i++) {
    const t = ttyOfPid(pid);
    if (t) return t;
    const ppid = ppidOf(pid);
    if (!Number.isFinite(ppid) || ppid <= 1 || ppid === pid) break;
    pid = ppid;
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

  const client = detectClient(p) || prev.client || "";
  const terminal = client === "cli" ? terminalMetadata() : {};
  const out = {
    state,
    label,
    tool: p.tool_name || "",
    project,
    sessionId: p.session_id || "",
    transcript: p.transcript_path || prev.transcript || "",
    client,
    terminalApp: terminal.terminalApp || prev.terminalApp || "",
    // terminalBundleId is intentionally empty for editor terminals (signals "use the bridge"), so
    // only fall back to prev when terminalMetadata made no determination (terminalApp empty).
    terminalBundleId: terminal.terminalApp ? terminal.terminalBundleId : (prev.terminalBundleId || ""),
    terminalSessionId: terminal.terminalSessionId || prev.terminalSessionId || "",
    tty: terminal.tty || prev.tty || "",
    startedAt,
    ts,
  };
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
