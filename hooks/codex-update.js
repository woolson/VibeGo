#!/usr/bin/env node
// Invoked by Codex hooks. Reads hook JSON from stdin and writes
// ~/.codex/statusbar/state.json using the same shape as the Claude state file.
// Usage: node codex-update.js <prompt|pre|post|notify|permreq|stop>

const fs = require("fs");
const os = require("os");
const path = require("path");

const dir = path.join(os.homedir(), ".codex", "statusbar");
const statePath = path.join(dir, "state.json");
const stateDir = path.join(dir, "states.d");
const event = process.argv[2] || "";

const TOOL_LABELS = {
  Bash: "Running command", bash: "Running command",
  Edit: "Editing", Write: "Writing", MultiEdit: "Editing",
  Read: "Reading", Grep: "Searching", Glob: "Searching",
  web: "Browsing web", WebFetch: "Browsing web", WebSearch: "Searching web",
  TodoWrite: "Planning", update_plan: "Planning",
};

function detectClient(p) {
  const explicit = String(p.client || p.client_type || p.entrypoint || p.source || p.app || "").toLowerCase();
  if (explicit.includes("desktop") || explicit === "app" || explicit.includes("codex.app")) return "app";
  if (explicit.includes("cli") || explicit.includes("terminal")) return "cli";

  const chain = processChain();
  if (chain.some((s) => s.includes(".app/contents/") || s.includes("codex helper") || s.includes("codex.app"))) {
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
process.stdin.on("end", () => run());
process.stdin.on("error", () => run());
setTimeout(run, 1000);

let done = false;
function run() {
  if (done) return;
  done = true;

  let p = {};
  try { p = JSON.parse(raw || "{}"); } catch {}

  const sid = safeId(p.session_id || p.sessionId || p.conversation_id || p.thread_id || "");
  if (sid) {
    try {
      const sessDir = path.join(dir, "sessions.d");
      fs.mkdirSync(sessDir, { recursive: true });
      fs.writeFileSync(path.join(sessDir, sid), "");
    } catch {}
  }

  let prev = {};
  try { prev = JSON.parse(fs.readFileSync(statePath, "utf8")); } catch {}

  const project = path.basename(p.cwd || p.working_dir || process.cwd());
  const ts = Math.floor(Date.now() / 1000);
  let state = "idle", label = "", startedAt = prev.startedAt || 0;

  switch (event) {
    case "prompt":
      state = "thinking"; label = "Thinking…"; startedAt = ts; break;
    case "pre": {
      const t = p.tool_name || p.tool || "";
      state = "tool"; label = TOOL_LABELS[t] || (String(t).startsWith("mcp__") ? "Using MCP" : "Using tool");
      if (!startedAt) startedAt = ts;
      break;
    }
    case "post":
      state = "thinking"; label = "Thinking…";
      if (!startedAt) startedAt = ts;
      break;
    case "notify":
    case "permreq":
      state = "permission"; label = "Awaiting permission"; startedAt = 0; break;
    case "stop":
      state = "done"; label = "Done"; startedAt = 0; break;
    default:
      process.exit(0);
  }

  const out = {
    source: "codex",
    state,
    label,
    tool: p.tool_name || p.tool || "",
    project,
    sessionId: p.session_id || p.sessionId || "",
    transcript: p.transcript_path || p.transcript || prev.transcript || "",
    client: detectClient(p) || prev.client || "",
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
  process.exit(0);
}

function safeId(s) {
  return String(s || "").replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 64) || "";
}
