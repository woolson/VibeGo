// VibeGo Bridge — runs inside VSCode-family editors (VSCode, Cursor, Qoder, …).
//
// Why this exists: VibeGo's status bar can switch to the exact terminal tab a Claude/Codex
// CLI session lives in for Apple Terminal and iTerm (their tabs expose a tty via AppleScript).
// Editor-integrated terminals don't — they're panes inside one app, addressable only through
// the editor's own API. So this extension owns the only tty→terminal map that exists, and
// exposes a localhost HTTP endpoint VibeGo calls to focus the matching pane.
//
// Plain CommonJS, no build step: `vscode`, `http`, `fs`, … are provided by the host at runtime.

const vscode = require("vscode");
const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const crypto = require("crypto");
const { execFileSync } = require("child_process");

const DISCOVERY_DIR = path.join(os.homedir(), ".vibego", "editor-bridges");
// Per-instance secret. Only VibeGo can read it (from the discovery file), so only VibeGo can
// drive the editor's terminals — any other local process gets a 403.
const TOKEN = crypto.randomBytes(24).toString("hex");
// Distinguish multiple extension-host processes (e.g. several editor windows) and survive pid reuse.
const INSTANCE_ID = crypto.randomBytes(4).toString("hex");

let server = null;
let port = 0;
let ttyMap = new Map(); // normalized tty -> vscode.Terminal
let rebuildTimer = null;
let refreshTimer = null;
let output = null;

function discoveryFile() {
  return path.join(DISCOVERY_DIR, process.pid + "-" + INSTANCE_ID + ".json");
}

function log(msg) {
  try {
    output = output || vscode.window.createOutputChannel("VibeGo Bridge");
    output.appendLine(msg);
  } catch {}
}

// Match the hooks' normalizedTTY: "ttys007" and "/dev/ttys007" compare equal.
function normalizedTTY(v) {
  const s = String(v || "").trim();
  if (s.startsWith("/dev/") && s.length > 5) return s.slice(5);
  return s;
}

function ttyOfPid(pid) {
  try {
    const t = execFileSync("ps", ["-p", String(pid), "-o", "tty="], {
      encoding: "utf8",
      timeout: 300,
    }).trim();
    if (t && t !== "??" && t !== "?") return t.startsWith("/dev/") ? t.slice(5) : t;
  } catch {}
  return "";
}

// System Events identifies a process by its EXECUTABLE name, not the display name — VSCode reports
// "Visual Studio Code" (vscode.env.appName) but its process is "Code". Resolve the real name from our
// own pid once (the host pid is stable for the editor's lifetime).
function editorProcessName() {
  try {
    const c = execFileSync("ps", ["-p", String(process.pid), "-o", "comm="], {
      encoding: "utf8",
      timeout: 300,
    }).trim();
    return c.split("/").pop() || "";
  } catch {}
  return "";
}
const PROCESS_NAME = editorProcessName();

// Bring the editor window forward AND restore it if it's Dock-minimized. `open`/`activate` alone
// handle a merely-covered window, but Electron editors don't deminimize on activate, so we also flip
// AXMinimized through System Events — using the real process name so the lookup succeeds. (The VibeGo
// app does the same as a backup; whichever holds Accessibility permission wins.)
function raiseEditorWindow() {
  const root = vscode.env.appRoot || "";
  const idx = root.toLowerCase().indexOf(".app/");
  if (idx >= 0) {
    try { execFileSync("open", [root.slice(0, idx + 4)], { stdio: "ignore", timeout: 1000 }); } catch {}
  }
  if (PROCESS_NAME) {
    const lines = [
      'tell application "System Events"',
      `set frontmost of process "${PROCESS_NAME}" to true`,
      "try",
      `set value of attribute "AXMinimized" of every window of process "${PROCESS_NAME}" to false`,
      "end try",
      "end tell",
    ];
    try {
      execFileSync("osascript", ["-e", lines.join("\n")], { stdio: "ignore", timeout: 1500 });
    } catch {}
  }
  const appName = vscode.env.appName || "";
  if (appName) {
    try { execFileSync("osascript", ["-e", `tell application "${appName}" to activate`], { stdio: "ignore", timeout: 1000 }); } catch {}
  }
}

function writeDiscovery() {
  try {
    fs.mkdirSync(DISCOVERY_DIR, { recursive: true });
    fs.writeFileSync(
      discoveryFile(),
      JSON.stringify({
        port,
        pid: process.pid,
        token: TOKEN,
        app: vscode.env.appName || "vscode",
        proc: PROCESS_NAME, // real System Events process name (e.g. "Code", not "Visual Studio Code")
        ts: Math.floor(Date.now() / 1000),
      })
    );
  } catch (e) {
    log("writeDiscovery error: " + e.message);
  }
}

function removeDiscovery() {
  try {
    fs.rmSync(discoveryFile(), { force: true });
  } catch {}
}

// processId resolves async and may be briefly unavailable right after a terminal opens, so we
// rebuild the whole map on open/close events and on a short interval rather than trusting a snapshot.
async function rebuildMap() {
  const next = new Map();
  await Promise.all(
    vscode.window.terminals.map(async (t) => {
      try {
        const pid = await t.processId;
        const tty = pid ? ttyOfPid(pid) : "";
        if (tty) next.set(tty, t);
      } catch {}
    })
  );
  ttyMap = next;
}

function activate(context) {
  server = http.createServer((req, res) => {
    if ((req.headers["authorization"] || "") !== "Bearer " + TOKEN) {
      res.writeHead(403);
      return res.end("forbidden");
    }

    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 8192) req.destroy();
    });
    req.on("end", () => {
      let json = {};
      try {
        json = body ? JSON.parse(body) : {};
      } catch {
        res.writeHead(400);
        return res.end("bad json");
      }
      const tty = normalizedTTY(json.tty);
      const terminal = tty ? ttyMap.get(tty) : null;
      if (!terminal) {
        res.writeHead(404);
        return res.end("no terminal");
      }
      try {
        terminal.show(false); // reveal + focus this pane (preserveFocus = false)
        res.writeHead(200);
        res.end("ok");
      } catch (e) {
        log("handle error: " + e.message);
        res.writeHead(500);
        res.end("error");
        return;
      }
      // Raise/un-minimize the editor window AFTER responding, so the HTTP call (VibeGo waits <1s)
      // isn't blocked by the osascript AX call that restores a Dock-minimized window.
      setImmediate(raiseEditorWindow);
    });
  });

  server.on("error", (e) => log("server error: " + e.message));
  server.listen(0, "127.0.0.1", () => {
    port = server.address().port;
    writeDiscovery();
    log("VibeGo Bridge on 127.0.0.1:" + port + " (" + (vscode.env.appName || "vscode") + ")");
  });

  rebuildMap();
  rebuildTimer = setInterval(rebuildMap, 3000);
  refreshTimer = setInterval(() => {
    if (port) writeDiscovery(); // keep ts fresh; recreate if another process removed it
  }, 10000);

  context.subscriptions.push(vscode.window.onDidOpenTerminal(() => rebuildMap()));
  context.subscriptions.push(vscode.window.onDidCloseTerminal(() => rebuildMap()));
  context.subscriptions.push(
    vscode.commands.registerCommand("vibego.bridge.revealLog", () => {
      (output = output || vscode.window.createOutputChannel("VibeGo Bridge")).show(true);
    })
  );
}

function deactivate() {
  try { if (rebuildTimer) clearInterval(rebuildTimer); } catch {}
  try { if (refreshTimer) clearInterval(refreshTimer); } catch {}
  try { removeDiscovery(); } catch {}
  try { if (server) server.close(); } catch {}
}

module.exports = { activate, deactivate };
