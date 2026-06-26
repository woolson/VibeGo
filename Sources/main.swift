import Cocoa

final class SessionRowView: NSView {
    weak var target: AnyObject?
    var action: Selector?
    var representedTag = 0
    private var tracking: NSTrackingArea?
    private var hovering = false {
        didSet { updateHover() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        updateHover()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 6
        updateHover()
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.pop()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, hovering {
            hovering = false
            NSCursor.pop()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        guard let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    private func updateHover() {
        layer?.backgroundColor = hovering ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        let delta = drawingRect.height - textHeight
        if delta > 0 {
            drawingRect.origin.y += floor(delta / 2)
            drawingRect.size.height -= delta
        }
        return drawingRect
    }
}

final class StatusController: NSObject, NSMenuDelegate {
    let claudeStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let codexStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let statePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/state.json")
    let claudeStatesDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/states.d")
    let claudeLimitsPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/limits.json")
    let claudeHudUsagePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/plugins/claude-hud/.usage-cache.json")
    let codexStatePath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/statusbar/state.json")
    let codexStatesDir = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/statusbar/states.d")
    let sessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/sessions.d")
    let codexSessionsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/statusbar/sessions.d")
    let codexTranscriptRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/sessions")
    let codexSessionIndexPath = (NSHomeDirectory() as NSString).appendingPathComponent(".codex/session_index.jsonl")
    let claudeHistoryPath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/history.jsonl")
    let claudeProjectsRoot = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")
    let claudeDesktopBundleID = "com.anthropic.claudefordesktop"
    let codexBundleID = "com.openai.codex"

    var lastMTime: Date = .distantPast
    var lastCodexMTime: Date = .distantPast
    var lastQuotaScan: Date = .distantPast
    var lastTitleScan: Date = .distantPast
    var pollTimer: Timer?
    var animTimer: Timer?
    var frameIdx = 0

    let launchedAt = Date()
    var notNeededSince: Date?
    let launchGrace: TimeInterval = 5   // settle time after launch before we may quit
    let idleQuitDelay: TimeInterval = 3 // "not needed" must persist this long before quitting

    var claudeCurrent: [String: Any] = [:]
    var codexCurrent: [String: Any] = [:]
    var claudeQuota: RateLimitSnapshot?
    var codexQuota: RateLimitSnapshot?
    var claudeEff = AgentStatus(source: "Claude", state: "idle", label: "", project: "", tool: "", sessionId: "", title: "", startedAt: 0, ts: 0, transcript: "")
    var codexEff = AgentStatus(source: "Codex", state: "idle", label: "", project: "", tool: "", sessionId: "", title: "", startedAt: 0, ts: 0, transcript: "")
    var claudeSessionStatuses: [AgentStatus] = []
    var codexSessionStatuses: [AgentStatus] = []
    var claudeSessionTitles: [String: String] = [:]
    var codexSessionTitles: [String: String] = [:]
    var sessionDetailsByTag: [Int: AgentStatus] = [:]
    var agentSourceByTag: [Int: String] = [:]
    var nextSessionTag = 1
    var activeBase = ""        // label without the elapsed clock
    var startedAt: Double = 0  // unix seconds the current turn began (0 = no clock)
    var activeColor: NSColor? = nil

    let brand = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1) // #d97757, Anthropic's official "Orange" accent
    let amber = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1) // "awaiting permission" yellow dot
    let frames: [NSImage] = StatusController.loadFrames()
    let spriteFPS: Double = 9 // tune: 8 frames per loop -> ~0.9s/cycle
    lazy var claudeApplicationIcon: NSImage? = StatusController.applicationIcon(
        bundleID: claudeDesktopBundleID,
        fallbackPath: "/Applications/Claude.app"
    )
    lazy var codexApplicationIcon: NSImage? = StatusController.applicationIcon(
        bundleID: codexBundleID,
        fallbackPath: "/Applications/Codex.app"
    )

    enum AnimStyle: String { case web, code, crab }
    var animStyle: AnimStyle = .web
    var showTimer = false
    var iconSystem = false // false = brand Orange; true = adaptive black/white (template image)
    var playCompletionSound = false // chime when a turn longer than ~1 min finishes
    lazy var completionSound: NSSound? = {
        guard let p = Bundle.main.path(forResource: "completion", ofType: "mp3"),
              let s = NSSound(contentsOfFile: p, byReference: true) else { return nil }
        s.volume = 0.7 // the clip is loud at full system volume; play it a bit softer
        return s
    }()
    var prevEff = ""               // last effective state, for detecting turn completion
    var lastTurnStart: Double = 0  // active turn's start time, for the 1-minute gate
    var iconColor: NSColor? { iconSystem ? nil : brand } // nil => render as an adaptive template
    let codeGlyphs = ["✻", "✽", "✶", "✳", "✢"]
    let codePeaks: [CGFloat] = [1.0, 1.0, 1.0, 1.0, 1.0]
    let codeDip: CGFloat = 0.14 // glyph shrinks to this at each swap
    let codeSub = 18            // sub-frames per glyph (tween smoothness)
    let codeCycle: Double = 3.8 // seconds for the full loop (lower = faster)
    lazy var codeGlyphMasks: [NSImage] = codeGlyphs.map { StatusController.glyphMask($0) }
    let crabFPS: Double = 12.5 // matches the source GIF's 0.08s frame delay
    lazy var crabFrames: [NSImage] = StatusController.decodePNGs(clawdCrabFramePNGs)
    var fps: Double {
        switch animStyle {
        case .web: return spriteFPS
        case .code: return Double(codeGlyphs.count * codeSub) / codeCycle
        case .crab: return crabFPS
        }
    }
    var frameCount: Int {
        switch animStyle {
        case .web: return max(1, frames.count)
        case .code: return codeGlyphs.count * codeSub
        case .crab: return max(1, crabFrames.count)
        }
    }
    struct LimitWindow {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Double
        var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    }
    struct RateLimitSnapshot {
        let primary: LimitWindow?
        let secondary: LimitWindow?
        let planType: String
        let modelContextWindow: Int
        let updatedAt: Date
    }
    struct AgentStatus {
        var source: String
        var state: String
        var label: String
        var project: String
        var tool: String
        var sessionId: String
        var title: String
        var startedAt: Double
        var ts: Double
        var transcript: String
        var client: String = ""
        var isActive: Bool { state == "thinking" || state == "tool" || state == "permission" || state == "waiting" }
        var isAnimating: Bool { state == "thinking" || state == "tool" }
    }

    override init() {
        super.init()
        let d = UserDefaults.standard
        if d.object(forKey: "showTimer") != nil { showTimer = d.bool(forKey: "showTimer") }
        if d.object(forKey: "iconSystem") != nil { iconSystem = d.bool(forKey: "iconSystem") }
        if d.object(forKey: "completionSound") != nil { playCompletionSound = d.bool(forKey: "completionSound") }
        if let s = d.string(forKey: "animStyle"), let st = AnimStyle(rawValue: s) { animStyle = st }
        configureStatusItem(claudeStatusItem)
        configureStatusItem(codexStatusItem)
        setStatusItem(codexStatusItem, icon: appIcon(for: "Codex"), label: "", startedAt: 0, hidden: true)
        setStatusItem(claudeStatusItem, icon: appIcon(for: "Claude"), label: "", startedAt: 0)
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        tick()
        ensureHooksInstalled()
        checkForUpdate()
    }

    func configureStatusItem(_ item: NSStatusItem) {
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.imageScaling = .scaleProportionallyDown
    }

    // Re-runs on first install AND on every version change, so upgrades pick up hook
    // changes and retire old artifacts. See CLAUDE.md "ensureHooksInstalled" for why.
    func ensureHooksInstalled() {
        let d = UserDefaults.standard
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        guard d.string(forKey: "installedVersion") != current,
              let installer = Bundle.main.path(forResource: "install", ofType: "js") else { return }
        DispatchQueue.global().async {
            guard let node = Self.locateNode() else {
                NSLog("VibeGo: could not find node; hooks not installed (will retry next launch)")
                return
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: node)
            task.arguments = [installer]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { UserDefaults.standard.set(current, forKey: "installedVersion") }
        }
    }

    // `/bin/zsh -lc node` saw only the login PATH, missing nvm/fnm set in .zshrc.
    static func locateNode() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "\(home)/.volta/bin/node",
            "\(home)/.asdf/shims/node",
        ]
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted(by: >) { candidates.append("\(nvmDir)/\(v)/bin/node") }
        }
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        for args in [["-ilc", "command -v node"], ["-lc", "command -v node"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !path.isEmpty, fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: update check

    var currentVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0" }
    let releaseAPIURL = "https://api.github.com/repos/m1ckc3s/claude-status-bar/releases/latest"
    let releasePageURL = "https://github.com/m1ckc3s/claude-status-bar/releases/latest"

    // Once/day: cache GitHub's latest release tag in UserDefaults. Nothing sent to us.
    // See CLAUDE.md "Update check" for the privacy/behavior notes.
    func checkForUpdate() {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if now - d.double(forKey: "lastUpdateCheck") < 86400 { return }
        guard let url = URL(string: releaseAPIURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("VibeGo", forHTTPHeaderField: "User-Agent") // GitHub API requires a UA
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            UserDefaults.standard.set(ver, forKey: "latestVersion")
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
        }.resume()
    }

    // Numeric component-wise compare so "0.0.10" > "0.0.9".
    func versionIsNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @objc func openLatestRelease() {
        if let url = URL(string: releasePageURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        checkForUpdate() // refreshes the update cache for next open (gated to once a day)

        menu.addItem(usageOverviewItem())
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu()
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Version \(currentVersion)", action: nil, keyEquivalent: ""))
        if let latest = UserDefaults.standard.string(forKey: "latestVersion"), versionIsNewer(latest, than: currentVersion) {
            let up = NSMenuItem(title: "Update available", action: #selector(openLatestRelease), keyEquivalent: "")
            up.target = self
            menu.addItem(up)
        }
        let q = NSMenuItem(title: "Quit VibeGo", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        let timerItem = NSMenuItem(title: "Show timer", action: #selector(toggleTimer), keyEquivalent: "")
        timerItem.target = self
        timerItem.state = showTimer ? .on : .off
        menu.addItem(timerItem)

        let soundItem = NSMenuItem(title: "Play Completion Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = playCompletionSound ? .on : .off
        if #available(macOS 14.0, *) { soundItem.badge = NSMenuItemBadge(string: "1m+") }
        menu.addItem(soundItem)

        menu.addItem(.separator())
        menu.addItem(header("Animation"))
        for (style, name) in [(AnimStyle.web, "Claude Spark"), (AnimStyle.code, "Claude Code"), (AnimStyle.crab, "Crab Walking")] {
            let it = NSMenuItem(title: name, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = style.rawValue
            it.state = animStyle == style ? .on : .off
            menu.addItem(it)
        }

        menu.addItem(.separator())
        menu.addItem(header("Color"))
        for (sys, name) in [(false, "Orange"), (true, "System")] {
            let it = NSMenuItem(title: name, action: #selector(chooseColor(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sys
            it.state = iconSystem == sys ? .on : .off
            menu.addItem(it)
        }
        return menu
    }

    func usageOverviewItem() -> NSMenuItem {
        let item = NSMenuItem()
        sessionDetailsByTag.removeAll()
        agentSourceByTag.removeAll()
        nextSessionTag = 1
        let claudeRows = displaySessions(claudeSessionStatuses, fallback: claudeEff)
        let codexRows = displaySessions(codexSessionStatuses, fallback: codexEff)
        let claudeHeight = sectionHeight(rowCount: claudeRows.count)
        let codexHeight = sectionHeight(rowCount: codexRows.count)
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 8
        let sectionGap: CGFloat = 22
        let totalHeight = topPadding + claudeHeight + sectionGap + codexHeight + bottomPadding
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: totalHeight))
        let codexY = bottomPadding
        let dividerY = codexY + codexHeight + (sectionGap / 2)
        let claudeY = codexY + codexHeight + sectionGap
        addAgentSection(to: view, y: claudeY, height: claudeHeight, title: "Claude", quota: claudeQuota, sessions: claudeRows)
        addDivider(to: view, y: dividerY)
        addAgentSection(to: view, y: codexY, height: codexHeight, title: "Codex", quota: codexQuota, sessions: codexRows)
        item.view = view
        return item
    }

    func addAgentSection(to parent: NSView, y: CGFloat, height: CGFloat, title: String, quota: RateLimitSnapshot?, sessions: [AgentStatus]) {
        let width: CGFloat = 390
        let headerY = y + height - 23
        let header = SessionRowView(frame: NSRect(x: 10, y: headerY - 5, width: 104, height: 26))
        header.target = self
        header.action = #selector(openAgentFromHeader(_:))
        header.representedTag = nextSessionTag
        agentSourceByTag[nextSessionTag] = title
        nextSessionTag += 1
        parent.addSubview(header)

        let icon = NSImageView(frame: NSRect(x: 4, y: 5, width: 18, height: 18))
        icon.imageScaling = .scaleProportionallyDown
        icon.image = agentIcon(sessions.first ?? AgentStatus(source: title, state: "idle", label: "", project: "", tool: "", sessionId: "", title: "", startedAt: 0, ts: 0, transcript: ""), frame: frameIdx)
        header.addSubview(icon)
        header.addSubview(menuLabel(title, x: 28, y: 4, width: 70, height: 18, bold: true, size: 13, color: .labelColor))

        let clickArea = NSButton(frame: header.bounds)
        clickArea.title = ""
        clickArea.isBordered = false
        clickArea.target = self
        clickArea.action = #selector(openAgentFromHeader(_:))
        clickArea.tag = header.representedTag
        header.addSubview(clickArea)

        parent.addSubview(quotaOverviewView(quota, x: 234, y: headerY - 6, width: width - 248))

        var rowY = headerY - 25
        if sessions.isEmpty {
            parent.addSubview(menuLabel("No active sessions", x: 38, y: rowY, width: width - 52, size: 11, color: .tertiaryLabelColor))
            return
        }
        let visibleSessionLimit = 3
        for status in sessions.prefix(visibleSessionLimit) {
            addSessionRow(to: parent, status: status, y: rowY)
            rowY -= 22
        }
        if sessions.count > visibleSessionLimit {
            parent.addSubview(menuLabel("+\(sessions.count - visibleSessionLimit) more sessions", x: 38, y: rowY, width: width - 52, size: 11, color: .tertiaryLabelColor))
        }
    }

    func addSessionRow(to parent: NSView, status: AgentStatus, y: CGFloat) {
        let row = SessionRowView(frame: NSRect(x: 10, y: y - 3, width: 370, height: 22))
        row.target = self
        row.action = #selector(openSessionConversation(_:))
        row.representedTag = nextSessionTag
        sessionDetailsByTag[nextSessionTag] = status
        nextSessionTag += 1
        parent.addSubview(row)

        let dotSize: CGFloat = 6
        let dot = NSView(frame: NSRect(x: 9, y: 8, width: dotSize, height: dotSize))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        dot.layer?.backgroundColor = statusColor(status).cgColor
        if status.isAnimating {
            // Running sessions get a breathing pulse. CoreAnimation runs on the render
            // server, so it keeps animating even while the menu owns the run loop.
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.25
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.layer?.add(pulse, forKey: "breath")
        }
        row.addSubview(dot)
        row.addSubview(menuLabel(sessionTitle(status), x: 28, y: 2, width: 148, height: 18, size: 11, color: .labelColor, centerVertically: true))
        row.addSubview(menuLabel(clientText(status), x: 180, y: 2, width: 24, height: 18, size: 10, color: .tertiaryLabelColor, centerVertically: true))
        row.addSubview(menuLabel(statusText(status), x: 208, y: 2, width: 88, height: 18, size: 11, color: .secondaryLabelColor, centerVertically: true))
        row.addSubview(menuLabel(projectText(status), x: 300, y: 2, width: 64, height: 18, size: 11, color: .tertiaryLabelColor, alignRight: true, centerVertically: true))

        let clickArea = NSButton(frame: row.bounds)
        clickArea.title = ""
        clickArea.isBordered = false
        clickArea.target = self
        clickArea.action = #selector(openSessionConversation(_:))
        clickArea.tag = row.representedTag
        row.addSubview(clickArea)
    }

    @objc func openSessionConversation(_ sender: AnyObject) {
        let tag = (sender as? SessionRowView)?.representedTag ?? (sender as? NSButton)?.tag ?? 0
        guard let status = sessionDetailsByTag[tag] else { return }
        openConversation(status)
    }

    @objc func openAgentFromHeader(_ sender: AnyObject) {
        let tag = (sender as? SessionRowView)?.representedTag ?? (sender as? NSButton)?.tag ?? 0
        guard let source = agentSourceByTag[tag] else { return }
        openAgentApp(source)
    }

    func addDivider(to parent: NSView, y: CGFloat) {
        let line = NSBox(frame: NSRect(x: 16, y: y, width: parent.bounds.width - 32, height: 1))
        line.boxType = .separator
        parent.addSubview(line)
    }

    func displaySessions(_ sessions: [AgentStatus], fallback: AgentStatus) -> [AgentStatus] {
        let active = sessions.filter { $0.isActive }
        let done = sessions
            .filter { !$0.isActive && $0.state == "done" }
            .sorted { $0.ts > $1.ts }
        // Running tasks present: show all of them, plus any just-finished ones alongside.
        if !active.isEmpty {
            return (active + done).sorted {
                if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                return $0.ts > $1.ts
            }
        }
        // Idle: keep the 3 most recent finished tasks visible (they survive as long as the
        // session is open; SessionEnd deletes the state file and removes them).
        if !done.isEmpty { return Array(done.prefix(3)) }
        return fallback.isActive ? [fallback] : []
    }

    func sectionHeight(rowCount: Int) -> CGFloat {
        let rows = rowCount > 3 ? 4 : max(1, rowCount)
        return CGFloat(44 + rows * 22)
    }

    enum ResetStyle {
        case hoursMinutes
        case daysHours
    }

    func quotaOverviewView(_ quota: RateLimitSnapshot?, x: CGFloat, y: CGFloat, width: CGFloat) -> NSView {
        let textHeight: CGFloat = 14
        let textBarGap: CGFloat = 2
        let bladeHeight: CGFloat = 7
        let bladeY = textHeight + textBarGap
        let view = NSView(frame: NSRect(x: x, y: y, width: width, height: bladeY + bladeHeight))
        let blade = NSImageView(frame: NSRect(x: 0, y: bladeY, width: width, height: bladeHeight))
        blade.image = quotaBladeImage(primary: quota?.primary, secondary: quota?.secondary, size: blade.frame.size)
        view.addSubview(blade)
        let centerX = floor(width / 2)
        let leftTime = menuLabel(resetText(quota?.primary, style: .hoursMinutes), x: 0, y: 0, width: centerX - 5, height: textHeight, size: 9, color: .secondaryLabelColor, alignRight: true)
        let divider = menuLabel("|", x: centerX - 2, y: 0, width: 4, height: textHeight, size: 9, color: .tertiaryLabelColor, alignRight: false)
        let rightTime = menuLabel(resetText(quota?.secondary, style: .daysHours), x: centerX + 5, y: 0, width: width - centerX - 5, height: textHeight, size: 9, color: .secondaryLabelColor)
        leftTime.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        divider.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        rightTime.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        view.addSubview(leftTime)
        view.addSubview(divider)
        view.addSubview(rightTime)
        return view
    }

    func quotaBladeImage(primary: LimitWindow?, secondary: LimitWindow?, size: NSSize) -> NSImage {
        let dividerWidth: CGFloat = 1
        let barHeight: CGFloat = 5
        let centerX = floor(size.width / 2)
        let leftX: CGFloat = 0
        let leftWidth = centerX
        let rightX = centerX
        let rightWidth = size.width - rightX
        let y = floor((size.height - barHeight) / 2)
        let leftRemaining = max(0, min(100, primary?.remainingPercent ?? 0))
        let rightRemaining = max(0, min(100, secondary?.remainingPercent ?? 0))
        let empty = NSColor.tertiaryLabelColor.withAlphaComponent(0.22)

        let img = NSImage(size: size, flipped: false) { _ in
            empty.setFill()
            self.oneSidedRoundedPath(NSRect(x: leftX, y: y, width: leftWidth, height: barHeight), roundedSide: .left).fill()
            self.oneSidedRoundedPath(NSRect(x: rightX, y: y, width: rightWidth, height: barHeight), roundedSide: .right).fill()

            let leftFill = leftWidth * CGFloat(leftRemaining / 100)
            if leftFill > 0 {
                self.quotaColor(leftRemaining).setFill()
                let rect = NSRect(x: leftWidth - leftFill, y: y, width: leftFill, height: barHeight)
                self.oneSidedRoundedPath(rect, roundedSide: leftFill >= leftWidth ? .left : .none).fill()
            }

            let rightFill = rightWidth * CGFloat(rightRemaining / 100)
            if rightFill > 0 {
                self.quotaColor(rightRemaining).setFill()
                let rect = NSRect(x: rightX, y: y, width: rightFill, height: barHeight)
                self.oneSidedRoundedPath(rect, roundedSide: rightFill >= rightWidth ? .right : .none).fill()
            }

            NSColor.tertiaryLabelColor.withAlphaComponent(0.55).setFill()
            NSRect(x: centerX - dividerWidth / 2, y: y - 1, width: dividerWidth, height: barHeight + 2).fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    enum RoundedSide {
        case none
        case left
        case right
    }

    func oneSidedRoundedPath(_ rect: NSRect, roundedSide: RoundedSide) -> NSBezierPath {
        let radius = min(rect.height / 2, rect.width / 2)
        guard radius > 0, roundedSide != .none else { return NSBezierPath(rect: rect) }
        let path = NSBezierPath()
        switch roundedSide {
        case .left:
            path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
            path.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: 270, endAngle: 90, clockwise: true)
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        case .right:
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: 270, endAngle: 90, clockwise: false)
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        case .none:
            break
        }
        path.close()
        return path
    }

    func resetText(_ limit: LimitWindow?, style: ResetStyle) -> String {
        guard let limit, limit.resetsAt > 0 else { return "--" }
        return resetCountdown(until: limit.resetsAt, style: style)
    }

    func resetCountdown(until timestamp: Double, style: ResetStyle) -> String {
        let seconds = max(0, Int(timestamp - Date().timeIntervalSince1970))
        switch style {
        case .hoursMinutes:
            let minutes = Int(ceil(Double(seconds) / 60.0))
            return "\(minutes / 60)h\(minutes % 60)m"
        case .daysHours:
            let hours = Int(ceil(Double(seconds) / 3600.0))
            return "\(hours / 24)d\(hours % 24)h"
        }
    }

    func statusColor(_ status: AgentStatus) -> NSColor {
        switch status.state {
        case "permission": return amber
        case "thinking", "tool": return NSColor.systemBlue
        case "done": return NSColor.systemGreen
        default: return NSColor.tertiaryLabelColor
        }
    }

    func menuLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 16, bold: Bool = false, size: CGFloat = 11, color: NSColor? = nil, alignRight: Bool = false, centerVertically: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: height)
        label.lineBreakMode = .byTruncatingTail
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color ?? (bold ? NSColor.labelColor : NSColor.secondaryLabelColor)
        label.alignment = alignRight ? .right : .left
        if centerVertically {
            let cell = VerticallyCenteredTextFieldCell(textCell: text)
            cell.font = label.font
            cell.textColor = label.textColor
            cell.alignment = label.alignment
            cell.lineBreakMode = label.lineBreakMode
            cell.usesSingleLineMode = true
            label.cell = cell
        }
        return label
    }

    func sessionTitle(_ status: AgentStatus) -> String {
        let title = status.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let project = status.project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty { return project }
        if status.sessionId.isEmpty { return "-" }
        if status.sessionId.count <= 10 { return status.sessionId }
        return String(status.sessionId.prefix(8)) + "..."
    }

    func projectText(_ status: AgentStatus) -> String {
        if status.label == "Running command" { return status.startedAt > 0 ? elapsedText(status.startedAt) : "" }
        return status.startedAt > 0 ? elapsedText(status.startedAt) : ""
    }

    func clientText(_ status: AgentStatus) -> String {
        switch status.client.lowercased() {
        case "app": return "App"
        case "cli": return "CLI"
        default: return ""
        }
    }

    func elapsedText(_ startedAt: Double) -> String {
        let secs = max(0, Int(Date().timeIntervalSince1970 - startedAt))
        let m = secs / 60, s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    func statusText(_ status: AgentStatus) -> String {
        switch status.state {
        case "thinking": return status.label.isEmpty ? "Thinking" : status.label
        case "tool": return status.label.isEmpty ? "Working" : status.label
        case "permission": return "Awaiting permission"
        case "waiting": return status.label.isEmpty ? "Waiting" : status.label
        case "done": return "Done"
        default: return "Idle"
        }
    }

    func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    @objc func quit() { NSApp.terminate(nil) }

    func openConversation(_ status: AgentStatus) {
        let ws = NSWorkspace.shared
        if status.client.lowercased() == "cli", let transcript = transcriptPath(for: status) {
            ws.open(URL(fileURLWithPath: transcript))
            return
        }
        if let url = conversationURL(for: status) {
            ws.open(url)
            return
        }
        if let transcript = transcriptPath(for: status) {
            ws.open(URL(fileURLWithPath: transcript))
            return
        }
        openAgentApp(status.source)
    }

    func conversationURL(for status: AgentStatus) -> URL? {
        guard !status.sessionId.isEmpty else { return nil }
        if status.client.lowercased() == "cli" { return nil }
        if status.source == "Codex" {
            guard let encoded = status.sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
            return URL(string: "codex://threads/\(encoded)")
        }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "resume"
        components.queryItems = [URLQueryItem(name: "session", value: status.sessionId)]
        return components.url
    }

    func transcriptPath(for status: AgentStatus) -> String? {
        let fm = FileManager.default
        if !status.transcript.isEmpty, fm.fileExists(atPath: status.transcript) { return status.transcript }
        guard !status.sessionId.isEmpty else { return nil }
        let root = status.source == "Codex" ? codexTranscriptRoot : claudeProjectsRoot
        guard let en = fm.enumerator(atPath: root) else { return nil }
        for case let rel as String in en where rel.hasSuffix(".jsonl") && rel.contains(status.sessionId) {
            let path = (root as NSString).appendingPathComponent(rel)
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    func openAgentApp(_ source: String) {
        let bundleID = source == "Codex" ? codexBundleID : claudeDesktopBundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc func toggleTimer() {
        showTimer.toggle()
        UserDefaults.standard.set(showTimer, forKey: "showTimer")
        renderAgents()
    }

    @objc func toggleSound() {
        playCompletionSound.toggle()
        UserDefaults.standard.set(playCompletionSound, forKey: "completionSound")
    }

    @objc func chooseColor(_ sender: NSMenuItem) {
        guard let sys = sender.representedObject as? Bool else { return }
        iconSystem = sys
        UserDefaults.standard.set(iconSystem, forKey: "iconSystem")
        evaluate() // re-render the current state in the new color
    }

    @objc func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = AnimStyle(rawValue: raw) else { return }
        animStyle = st
        UserDefaults.standard.set(raw, forKey: "animStyle")
        animTimer?.invalidate(); animTimer = nil // recreate at the new style's fps
        frameIdx = 0
        evaluate()
    }

    // MARK: state polling

    func tick() {
        checkLifecycle()
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: statePath),
           let m = attrs[.modificationDate] as? Date,
           m != lastMTime {
            lastMTime = m
            if let data = fm.contents(atPath: statePath),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                claudeCurrent = obj.merging(["source": "claude"]) { old, _ in old }
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: codexStatePath),
           let m = attrs[.modificationDate] as? Date,
           m != lastCodexMTime {
            lastCodexMTime = m
            if let data = fm.contents(atPath: codexStatePath),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                codexCurrent = obj.merging(["source": "codex"]) { old, _ in old }
            }
        }

        if Date().timeIntervalSince(lastQuotaScan) >= 3 {
            lastQuotaScan = Date()
            claudeQuota = readClaudeRateLimits()
            codexQuota = readLatestCodexRateLimits()
        }
        if Date().timeIntervalSince(lastTitleScan) >= 5 {
            lastTitleScan = Date()
            refreshSessionTitles()
        }
        claudeSessionStatuses = readSessionStatuses(in: claudeStatesDir, source: "Claude")
        codexSessionStatuses = readSessionStatuses(in: codexStatesDir, source: "Codex")
        evaluate()
    }

    func evaluate() {
        claudeEff = effectiveStatus(from: claudeCurrent, source: "Claude")
        codexEff = effectiveStatus(from: codexCurrent, source: "Codex")

        // Chime once when a turn that ran >= 1 min transitions to "done".
        let combinedEff = [claudeEff, codexEff].map(\.state).joined(separator: "+")
        let activeStarted = [claudeEff, codexEff].filter { $0.isAnimating && $0.startedAt > 0 }.map(\.startedAt).min() ?? 0
        if activeStarted > 0 { lastTurnStart = activeStarted }
        if combinedEff.contains("done"), !prevEff.contains("done"), playCompletionSound,
           lastTurnStart > 0, Date().timeIntervalSince1970 - lastTurnStart >= 60 {
            completionSound?.play()
        }
        if !claudeEff.isAnimating && !codexEff.isAnimating { lastTurnStart = 0 }
        prevEff = combinedEff

        renderAgents()
    }

    func effectiveStatus(from current: [String: Any], source: String) -> AgentStatus {
        let rawState = current["state"] as? String ?? "idle"
        var label = current["label"] as? String ?? ""
        let project = current["project"] as? String ?? ""
        let tool = current["tool"] as? String ?? ""
        let sessionId = current["sessionId"] as? String ?? ""
        let explicitTitle = current["title"] as? String ?? ""
        let ts = (current["ts"] as? NSNumber)?.doubleValue ?? 0
        var started = (current["startedAt"] as? NSNumber)?.doubleValue ?? 0
        let transcript = current["transcript"] as? String ?? ""
        let client = current["client"] as? String ?? ""
        let age = Date().timeIntervalSince1970 - ts

        var state = rawState
        if source == "Codex", state == "thinking" {
            let normalizedLabel = label
                .replacingOccurrences(of: "…", with: "...")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedLabel == "codex thinking..." || normalizedLabel == "code thinking" || normalizedLabel == "code thinking..." {
                label = ""
            }
        }
        if state == "thinking" || state == "tool" || state == "permission" {
            if age > 900 {
                state = "idle"; label = ""; started = 0
            } else if !transcript.isEmpty,
                      let last = lastLine(ofFileAt: transcript),
                      last.contains("interrupted by user") {
                state = "idle"; label = ""; started = 0
            }
        }
        var title = explicitTitle.isEmpty ? titleForSession(source: source, sessionId: sessionId) : explicitTitle
        if title.isEmpty, source == "Claude" {
            title = titleFromClaudeTranscript(transcript)
        }
        return AgentStatus(source: source, state: state, label: label, project: project, tool: tool, sessionId: sessionId, title: title, startedAt: started, ts: ts, transcript: transcript, client: client)
    }

    func readSessionStatuses(in dir: String, source: String) -> [AgentStatus] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var statuses: [AgentStatus] = []
        for file in files where file.hasSuffix(".json") {
            let path = (dir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            statuses.append(effectiveStatus(from: obj, source: source))
        }
        let now = Date().timeIntervalSince1970
        // Keep active and finished sessions (the latter linger until SessionEnd deletes the
        // file); only drop stale idle sessions that never reached a terminal state.
        return statuses.filter { $0.isActive || $0.state == "done" || now - $0.ts < 300 }
    }

    func refreshSessionTitles() {
        claudeSessionTitles = readClaudeSessionTitles()
        codexSessionTitles = readCodexSessionTitles()
    }

    func titleForSession(source: String, sessionId: String) -> String {
        guard !sessionId.isEmpty else { return "" }
        return source == "Codex" ? (codexSessionTitles[sessionId] ?? "") : (claudeSessionTitles[sessionId] ?? "")
    }

    func titleFromClaudeTranscript(_ path: String) -> String {
        guard !path.isEmpty,
              let lines = headLines(path, maxBytes: 131072) else { return "" }
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if obj["type"] as? String == "queue-operation",
               obj["operation"] as? String == "enqueue",
               let title = cleanSessionTitle(obj["content"] as? String),
               isUsefulSessionTitle(title) {
                return title
            }
            if obj["type"] as? String == "user",
               let message = obj["message"] as? [String: Any],
               let title = cleanSessionTitle(promptContentText(message["content"])),
               isUsefulSessionTitle(title) {
                return title
            }
        }
        return ""
    }

    func promptContentText(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        guard let parts = value as? [[String: Any]] else { return nil }
        return parts.compactMap { part in
            guard part["type"] as? String == "text" else { return nil }
            return part["text"] as? String
        }.joined(separator: " ")
    }

    func readCodexSessionTitles() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: codexSessionIndexPath),
              let text = String(data: data, encoding: .utf8) else { return [:] }
        var titles: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["id"] as? String else { continue }
            if let title = cleanSessionTitle(obj["thread_name"] as? String), !title.isEmpty {
                titles[id] = title
            }
        }
        return titles
    }

    func readClaudeSessionTitles() -> [String: String] {
        var titles: [String: String] = [:]
        if let data = FileManager.default.contents(atPath: claudeHistoryPath),
           let text = String(data: data, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let data = String(line).data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = obj["sessionId"] as? String else { continue }
                if let title = cleanSessionTitle(obj["display"] as? String), isUsefulSessionTitle(title) {
                    titles[id] = title
                }
            }
        }

        let fm = FileManager.default
        if let en = fm.enumerator(atPath: claudeProjectsRoot) {
            for case let rel as String in en where rel.hasSuffix("sessions-index.json") {
                let path = (claudeProjectsRoot as NSString).appendingPathComponent(rel)
                guard let data = fm.contents(atPath: path),
                      let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
                mergeClaudeIndexTitles(obj, into: &titles)
            }
        }
        return titles
    }

    func mergeClaudeIndexTitles(_ value: Any, into titles: inout [String: String]) {
        if let arr = value as? [Any] {
            for item in arr { mergeClaudeIndexTitles(item, into: &titles) }
            return
        }
        guard let obj = value as? [String: Any] else { return }
        if let sessions = obj["sessions"] { mergeClaudeIndexTitles(sessions, into: &titles) }
        if let id = (obj["sessionId"] as? String) ?? (obj["id"] as? String), titles[id] == nil {
            let title = cleanSessionTitle((obj["summary"] as? String) ?? (obj["firstPrompt"] as? String) ?? (obj["display"] as? String))
            if let title, isUsefulSessionTitle(title) { titles[id] = title }
        }
        for (_, child) in obj where !(child is String) && !(child is NSNumber) {
            mergeClaudeIndexTitles(child, into: &titles)
        }
    }

    func cleanSessionTitle(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "\n", with: " ")
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text.count > 80 ? String(text.prefix(80)) + "..." : text
    }

    func isUsefulSessionTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let ignoredCommands = ["/new", "/clear", "/model", "/help", "/quit", "/exit"]
        return !ignoredCommands.contains(trimmed)
    }

    func renderAgents() {
        let active = [aggregateStatus(for: "Claude", sessions: claudeSessionStatuses, fallback: claudeEff),
                      aggregateStatus(for: "Codex", sessions: codexSessionStatuses, fallback: codexEff)]
            .filter(\.isActive)
        let animate = active.contains { $0.isAnimating }
        activeBase = active.map { statusBarLabel(for: $0) }.joined(separator: "  ")
        startedAt = active.compactMap { $0.startedAt > 0 ? $0.startedAt : nil }.min() ?? 0
        activeColor = iconColor

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.animStep() }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate(); animTimer = nil
            frameIdx = 0
        }
        renderStatusItems(active)
    }

    func renderStatusItems(_ active: [AgentStatus]) {
        if active.isEmpty {
            setStatusItem(claudeStatusItem, icon: appIcon(for: "Claude"), label: "", startedAt: 0, hidden: false)
            setStatusItem(codexStatusItem, icon: appIcon(for: "Codex"), label: "", startedAt: 0, hidden: true)
            return
        }

        let activeBySource = Dictionary(uniqueKeysWithValues: active.map { ($0.source, $0) })
        for source in ["Claude", "Codex"] {
            guard let item = statusItem(for: source) else { continue }
            guard let status = activeBySource[source] else {
                // Claude is the always-visible anchor: when it has no active session it
                // falls back to its idle icon instead of vanishing. Without this, Claude's
                // item disappears whenever Codex is the only active agent. Codex still hides
                // when idle so the bar stays uncluttered.
                let isAnchor = (source == "Claude")
                setStatusItem(item, icon: appIcon(for: source), label: "", startedAt: 0, hidden: !isAnchor)
                continue
            }
            setStatusItem(
                item,
                icon: statusBarIcon(for: status),
                label: statusBarLabel(for: status),
                startedAt: status.startedAt,
                hidden: false,
                textColor: status.state == "permission" ? amber : NSColor.labelColor,
                // Only an executing session (thinking/tool) flips; permission/waiting stay still.
                flipIcon: status.isAnimating
            )
        }
    }

    func statusItem(for source: String) -> NSStatusItem? {
        source == "Codex" ? codexStatusItem : claudeStatusItem
    }

    func statusBarLabel(for status: AgentStatus) -> String {
        if status.label.hasSuffix(" sessions") { return status.label }
        switch status.state {
        case "thinking": return status.label.isEmpty ? "Thinking…" : status.label
        case "tool": return status.label.isEmpty ? "Working…" : status.label
        case "permission": return "Awaiting permission"
        case "waiting": return status.label.isEmpty ? "Waiting" : status.label
        default: return ""
        }
    }

    func aggregateStatus(for source: String, sessions: [AgentStatus], fallback: AgentStatus) -> AgentStatus {
        let active = sessions.filter(\.isActive).sorted { $0.ts > $1.ts }
        guard !active.isEmpty else { return fallback }
        var top = active[0]
        if active.count > 1 {
            if active.contains(where: { $0.state == "permission" }) {
                top.state = "permission"
                top.label = "\(active.count) sessions"
            } else if active.contains(where: { $0.state == "tool" }) {
                top.state = "tool"
                top.label = "\(active.count) sessions"
            } else {
                top.state = "thinking"
                top.label = "\(active.count) sessions"
            }
            top.source = source
            top.startedAt = active.compactMap { $0.startedAt > 0 ? $0.startedAt : nil }.min() ?? top.startedAt
        }
        return top
    }

    func combinedIcon(frame: Int) -> NSImage {
        let active = [aggregateStatus(for: "Claude", sessions: claudeSessionStatuses, fallback: claudeEff),
                      aggregateStatus(for: "Codex", sessions: codexSessionStatuses, fallback: codexEff)]
            .filter(\.isActive)
        if active.isEmpty { return appIcon(for: "Claude") }
        if active.count == 1 {
            return agentIcon(active[0], frame: frame)
        }
        let icons = active.map { agentIcon($0, frame: frame) }
        let h: CGFloat = 18, gap: CGFloat = 2
        let w = icons.reduce(CGFloat(0)) { $0 + max($1.size.width, 18) } + gap
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            var x: CGFloat = 0
            for icon in icons {
                let iw = max(icon.size.width, 18)
                icon.draw(in: NSRect(x: x, y: 0, width: iw, height: h), from: .zero, operation: .sourceOver, fraction: 1.0)
                x += iw + gap
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    func agentIcon(_ status: AgentStatus, frame: Int) -> NSImage {
        return appIcon(for: status.source)
    }

    func statusBarIcon(for status: AgentStatus) -> NSImage {
        appIcon(for: status.source)
    }

    // MARK: self-quit lifecycle (rationale + warmup-churn history in CLAUDE.md)

    func claudeDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == claudeDesktopBundleID }
    }

    func sessionCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir).count) ?? 0
    }

    func codexSessionCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: codexSessionsDir).count) ?? 0
    }

    // Stay while Claude desktop is open OR a session is active; otherwise quit after a
    // short debounced grace (warmup-session churn must not kill us).
    func checkLifecycle() {
        let now = Date()
        if now.timeIntervalSince(launchedAt) < launchGrace { return }
        if claudeDesktopRunning() || sessionCount() > 0 || codexSessionCount() > 0 {
            notNeededSince = nil
            return
        }
        if let since = notNeededSince {
            if now.timeIntervalSince(since) >= idleQuitDelay { NSApp.terminate(nil) }
        } else {
            notNeededSince = now
        }
    }

    // Read the last non-empty line of a (possibly large) file by tailing ~8KB.
    func lastLine(ofFileAt path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 8192
        try? fh.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? fh.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").last { !$0.isEmpty }.map(String.init)
    }

    // MARK: render

    func render(label: String, color: NSColor?, animate: Bool, startedAt: Double, dot: Bool = false) {
        guard let button = claudeStatusItem.button else { return }
        button.contentTintColor = nil // we paint the icon color ourselves; template-tint is unreliable
        activeBase = label
        activeColor = color
        self.startedAt = startedAt

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.animStep() }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate(); animTimer = nil
            frameIdx = 0
            button.image = dot ? dotIcon(color: color) : restingIcon(color: color)
        }
        applyTitle()
        if button.image == nil { button.image = dot ? dotIcon(color: color) : restingIcon(color: color) }
    }

    func animStep() {
        frameIdx = (frameIdx + 1) % frameCount
        let active = [aggregateStatus(for: "Claude", sessions: claudeSessionStatuses, fallback: claudeEff),
                      aggregateStatus(for: "Codex", sessions: codexSessionStatuses, fallback: codexEff)]
            .filter(\.isActive)
        renderStatusItems(active)
    }

    // While a session is executing, the icon does a 3D flip around its own vertical
    // center axis (rotateY) every 3s, lasting 0.8s. One self-repeating CAKeyframeAnimation
    // carries the whole 3s cadence — the flip fills the first 0.8s, the rest holds flat.
    // CoreAnimation runs on the render server, so it keeps flipping even while the menu
    // owns the run loop, and survives the frequent button.image updates.
    func iconFlipAnimation() -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: "transform")
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 480.0 // adds depth so the flip reads as 3D, not a flat squish
        func rotY(_ deg: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DRotate(perspective, deg * .pi / 180, 0, 1, 0))
        }
        anim.values = [rotY(0), rotY(90), rotY(180), rotY(270), rotY(360), rotY(360)]
        let flipEnd = 0.8 / 3.0 // the flip occupies the first 0.8s of the 3s loop
        anim.keyTimes = [0, flipEnd * 0.25, flipEnd * 0.5, flipEnd * 0.75, flipEnd, 1.0]
            .map { NSNumber(value: Double($0)) }
        anim.duration = 3.0
        anim.repeatCount = .infinity
        anim.calculationMode = .linear
        anim.isRemovedOnCompletion = false
        return anim
    }

    // The icon flips alone: it lives in its own sublayer (default anchorPoint .5,.5, so it
    // pivots about its own center) drawn on top of the text-only button image. The baked
    // image omits the icon while flipping, so the elapsed-time text never rotates.
    func updateIconLayer(_ button: NSStatusBarButton, icon: NSImage, imageWidth: CGFloat) {
        button.wantsLayer = true
        guard let host = button.layer else { return }
        let iconSize: CGFloat = 18
        let layer = host.sublayers?.first { $0.name == "iconFlip" } ?? {
            let l = CALayer(); l.name = "iconFlip"; host.addSublayer(l); return l
        }()
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        // The cell centers the image, so its left edge sits at (buttonWidth - imageWidth)/2;
        // the icon occupies the image's leftmost 18pt. Mirror that so the layer lines up.
        let pad = max(0, (button.bounds.width - imageWidth) / 2)
        let y = max(0, (button.bounds.height - iconSize) / 2)
        layer.frame = CGRect(x: pad, y: y, width: iconSize, height: iconSize)
        if layer.animation(forKey: "flip") == nil {
            layer.add(iconFlipAnimation(), forKey: "flip")
        }
    }

    func removeIconLayer(_ button: NSStatusBarButton) {
        button.layer?.sublayers?.first { $0.name == "iconFlip" }?.removeFromSuperlayer()
    }

    func applyTitle() {
        guard let button = claudeStatusItem.button else { return }
        var text = activeBase
        if showTimer, startedAt > 0 {
            let secs = max(0, Int(Date().timeIntervalSince1970 - startedAt))
            let m = secs / 60, s = secs % 60
            text += "  " + (m > 0 ? "\(m)m \(s)s" : "\(s)s") // Claude Code style: "1m 1s" / "43s"
        }
        if text.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.imagePosition = .imageLeading
        // labelColor adapts: white on a dark menu bar, black on a light one. Monospaced
        // digits keep the elapsed clock from nudging neighboring menu bar icons.
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ]
        button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attrs)
    }

    func setStatusItem(_ item: NSStatusItem, icon: NSImage, label: String, startedAt: Double, hidden: Bool = false, textColor: NSColor = .labelColor, flipIcon: Bool = false) {
        guard let button = item.button else { return }
        let text = statusBarDisplayText(label: label, startedAt: startedAt)
        // While flipping, draw the text only (icon omitted) and let the animating sublayer
        // supply the icon, so the 3D flip applies to the icon alone.
        let image = hidden ? nil : statusBarItemImage(icon: flipIcon ? nil : icon, text: text, textColor: textColor)
        item.length = hidden ? 0 : ((image?.size.width ?? 18) + 8)
        button.isHidden = hidden
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        if hidden || !flipIcon {
            removeIconLayer(button)
        } else {
            updateIconLayer(button, icon: icon, imageWidth: image?.size.width ?? 18)
        }
    }

    func statusBarDisplayText(label: String, startedAt: Double) -> String {
        var text = label
        if showTimer, startedAt > 0 {
            let secs = max(0, Int(Date().timeIntervalSince1970 - startedAt))
            let m = secs / 60, s = secs % 60
            text += "  " + (m > 0 ? "\(m)m \(s)s" : "\(s)s")
        }
        return text
    }

    // icon == nil reserves the icon's width but leaves it blank — used while the icon is
    // flipping in its own sublayer, so the text stays in exactly the same place.
    func statusBarItemImage(icon: NSImage?, text: String, textColor: NSColor = .labelColor) -> NSImage {
        let iconSize: CGFloat = 18
        let height: CGFloat = 18
        let gap: CGFloat = text.isEmpty ? 0 : 5
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font,
        ]
        let textSize = text.isEmpty ? .zero : NSAttributedString(string: text, attributes: attrs).size()
        let width = ceil(iconSize + gap + textSize.width)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: 0, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1)
            if !text.isEmpty {
                let textY = floor((height - textSize.height) / 2)
                text.draw(at: NSPoint(x: iconSize + gap, y: textY), withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    func applyTitle(to button: NSStatusBarButton, label: String, startedAt: Double) {
        let text = statusBarDisplayText(label: label, startedAt: startedAt)
        if text.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.imagePosition = .imageLeading
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        ]
        button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attrs)
    }

    // MARK: icon

    static func loadFrames() -> [NSImage] { decodePNGs(claudeSparkFramePNGs) }
    static func decodePNGs(_ list: [String]) -> [NSImage] {
        list.compactMap { Data(base64Encoded: $0).flatMap(NSImage.init(data:)) }
    }

    static func applicationIcon(bundleID: String, fallbackPath: String) -> NSImage? {
        let fm = FileManager.default
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? (fm.fileExists(atPath: fallbackPath) ? URL(fileURLWithPath: fallbackPath) : nil)
        guard let appURL else { return nil }
        return scaledAppIcon(NSWorkspace.shared.icon(forFile: appURL.path))
    }

    static func scaledAppIcon(_ source: NSImage) -> NSImage {
        let s: CGFloat = 18
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        img.isTemplate = false
        return img
    }

    func iconImage(color: NSColor?, frame: Int) -> NSImage {
        if animStyle == .web { return tint(frames, color: color, frame: frame) }
        if animStyle == .crab { return crabIcon(frame: frame) }
        let i = (frame / codeSub) % codeGlyphs.count
        let local = (CGFloat(frame % codeSub) + 0.5) / CGFloat(codeSub) // 0…1 within this glyph
        // Scale envelope per glyph: rise, hold at peak, fall, so each lands before the swap.
        let env: CGFloat
        if local < 0.30 { let u = local / 0.30; env = u * u * (3 - 2 * u) }
        else if local > 0.70 { let u = (1 - local) / 0.30; env = u * u * (3 - 2 * u) }
        else { env = 1 }
        let scale = codeDip + (codePeaks[i] - codeDip) * env
        return codeIcon(color: color, glyph: i, scale: scale)
    }

    // nil color => adaptive template image (system draws it black/white per the menu bar).
    func codeIcon(color: NSColor?, glyph: Int, scale: CGFloat) -> NSImage {
        let s: CGFloat = 18
        guard glyph < codeGlyphMasks.count else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = codeGlyphMasks[glyph]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let dw = s * scale
            let r = NSRect(x: (s - dw) / 2, y: (s - dw) / 2, width: dw, height: dw)
            if let c = color {
                c.setFill(); r.fill()
                mask.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    // Rasterize a single glyph into a centered 60x60 alpha mask filling ~92%.
    static func glyphMask(_ g: String) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 180), .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: g, attributes: attrs)
        let sz = str.size()
        let big = NSImage(size: sz, flipped: false) { _ in str.draw(at: .zero); return true }
        guard let rep = big.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return NSImage(size: NSSize(width: 60, height: 60))
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh, data = rep.bitmapData!
        var minx = w, miny = h, maxx = -1, maxy = -1
        for y in 0..<h { for x in 0..<w where data[(y*w+x)*4+3] > 20 {
            minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, y); maxy = max(maxy, y)
        }}
        guard maxx >= 0 else { return NSImage(size: NSSize(width: 60, height: 60)) }
        let bw = CGFloat(maxx - minx + 1), bh = CGFloat(maxy - miny + 1)
        let out: CGFloat = 60, fill = out * 0.92
        let scale = fill / max(bw, bh)
        let dw = bw * scale, dh = bh * scale
        // NSBitmapImageRep origin is top-left; convert the bbox to bottom-left for drawing.
        let srcRect = NSRect(x: CGFloat(minx), y: CGFloat(h - maxy - 1), width: bw, height: bh)
        return NSImage(size: NSSize(width: out, height: out), flipped: false) { _ in
            big.draw(in: NSRect(x: (out - dw)/2, y: (out - dh)/2, width: dw, height: dh),
                     from: srcRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    let logoSet: [NSImage] = Data(base64Encoded: claudeLogoPNG).flatMap(NSImage.init(data:)).map { [$0] } ?? []
    func restingIcon(color: NSColor?) -> NSImage {
        if animStyle == .crab { return crabIcon(frame: 0) }
        return tint(logoSet.isEmpty ? frames : logoSet, color: color, frame: 0)
    }

    func appIcon(for source: String) -> NSImage {
        if source == "Codex" {
            return codexApplicationIcon ?? codeIcon(color: iconColor, glyph: 0, scale: 0.92)
        }
        return claudeApplicationIcon ?? restingIcon(color: iconColor)
    }

    // Full color (isTemplate=false), so the Orange/System color setting does NOT apply here.
    func crabIcon(frame: Int) -> NSImage {
        guard !crabFrames.isEmpty else { return NSImage(size: NSSize(width: 18, height: 18)) }
        let src = crabFrames[frame % crabFrames.count]
        let rep = src.representations.first
        let pw = CGFloat(rep?.pixelsWide ?? Int(src.size.width))
        let ph = CGFloat(rep?.pixelsHigh ?? Int(src.size.height))
        let h: CGFloat = 18, w = (ph > 0 ? h * (pw / ph) : h)
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            src.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        img.isTemplate = false
        return img
    }

    func dotIcon(color: NSColor?) -> NSImage {
        let s: CGFloat = 18, d: CGFloat = 9
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            (color ?? .systemYellow).setFill()
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    // Paint `color` through a frame mask's alpha (destinationIn) so frames recolor.
    func tint(_ set: [NSImage], color: NSColor?, frame: Int) -> NSImage {
        let s: CGFloat = 18
        guard !set.isEmpty else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = set[frame % set.count]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { rect in
            if let c = color {
                c.setFill()
                rect.fill()
                mask.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil) // nil => adaptive black/white in the menu bar
        return img
    }

    // MARK: Usage limits

    func limitText(_ name: String, _ limit: LimitWindow?) -> String {
        guard let limit else { return name.isEmpty ? "Unknown" : "\(name): Unknown" }
        let reset = limit.resetsAt > 0 ? ", resets \(relativeTime(Date(timeIntervalSince1970: limit.resetsAt)))" : ""
        let value = "\(Int(round(limit.remainingPercent)))% remaining\(reset)"
        return name.isEmpty ? value : "\(name): \(value)"
    }

    func relativeTime(_ date: Date) -> String {
        let seconds = Int(date.timeIntervalSinceNow)
        if abs(seconds) < 60 { return seconds >= 0 ? "in \(seconds)s" : "\(abs(seconds))s ago" }
        let minutes = abs(seconds) / 60
        if minutes < 60 { return seconds >= 0 ? "in \(minutes)m" : "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return seconds >= 0 ? "in \(hours)h" : "\(hours)h ago" }
        let days = hours / 24
        return seconds >= 0 ? "in \(days)d" : "\(days)d ago"
    }

    func quotaIcon(primary: LimitWindow?, secondary: LimitWindow?) -> NSImage {
        let w: CGFloat = 17, h: CGFloat = 18
        let filledA = filledBlocks(primary?.remainingPercent)
        let filledB = filledBlocks(secondary?.remainingPercent)
        let colorA = quotaColor(primary?.remainingPercent)
        let colorB = quotaColor(secondary?.remainingPercent)
        let empty = NSColor.tertiaryLabelColor.withAlphaComponent(0.42)
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            for col in 0..<2 {
                let filled = col == 0 ? filledA : filledB
                let color = col == 0 ? colorA : colorB
                for row in 0..<5 {
                    let x = CGFloat(col) * 8 + 1
                    let y = CGFloat(row) * 3 + 2
                    let rect = NSRect(x: x, y: y, width: 6, height: 2)
                    if row < filled {
                        color.setFill()
                        rect.fill()
                    } else {
                        empty.setStroke()
                        NSBezierPath(rect: rect).stroke()
                    }
                }
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    func filledBlocks(_ remaining: Double?) -> Int {
        guard let remaining else { return 0 }
        if remaining <= 0 { return 0 }
        return max(1, min(5, Int(ceil(remaining / 20))))
    }

    func quotaColor(_ remaining: Double?) -> NSColor {
        guard let remaining else { return NSColor.tertiaryLabelColor }
        if remaining <= 20 { return NSColor.systemRed }
        if remaining <= 45 { return NSColor.systemYellow }
        return NSColor.systemGreen
    }

    func readClaudeRateLimits() -> RateLimitSnapshot? {
        if let data = FileManager.default.contents(atPath: claudeLimitsPath),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let ts = (obj["ts"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
            return RateLimitSnapshot(
                primary: parseRemainingLimit(obj["fiveHour"], windowMinutes: 300),
                secondary: parseRemainingLimit(obj["sevenDay"], windowMinutes: 10080),
                planType: obj["planType"] as? String ?? "",
                modelContextWindow: (obj["modelContextWindow"] as? NSNumber)?.intValue ?? 0,
                updatedAt: Date(timeIntervalSince1970: ts)
            )
        }
        return readClaudeHudRateLimits()
    }

    func readClaudeHudRateLimits() -> RateLimitSnapshot? {
        guard let data = FileManager.default.contents(atPath: claudeHudUsagePath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let source = (obj["lastGoodData"] as? [String: Any]) ?? (obj["data"] as? [String: Any]) ?? obj
        let tsMs = (obj["timestamp"] as? NSNumber)?.doubleValue ?? 0
        return RateLimitSnapshot(
            primary: LimitWindow(
                usedPercent: max(0, min(100, 100 - ((source["fiveHour"] as? NSNumber)?.doubleValue ?? 0))),
                windowMinutes: 300,
                resetsAt: parseTimestamp(source["fiveHourResetAt"] as? String)?.timeIntervalSince1970 ?? 0
            ),
            secondary: LimitWindow(
                usedPercent: max(0, min(100, 100 - ((source["sevenDay"] as? NSNumber)?.doubleValue ?? 0))),
                windowMinutes: 10080,
                resetsAt: parseTimestamp(source["sevenDayResetAt"] as? String)?.timeIntervalSince1970 ?? 0
            ),
            planType: source["planName"] as? String ?? "",
            modelContextWindow: 0,
            updatedAt: tsMs > 0 ? Date(timeIntervalSince1970: tsMs / 1000) : Date()
        )
    }

    func parseRemainingLimit(_ value: Any?, windowMinutes: Int) -> LimitWindow? {
        guard let obj = value as? [String: Any],
              let remaining = (obj["remainingPercent"] as? NSNumber)?.doubleValue else { return nil }
        return LimitWindow(
            usedPercent: max(0, min(100, 100 - remaining)),
            windowMinutes: windowMinutes,
            resetsAt: (obj["resetsAt"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    func readLatestCodexRateLimits() -> RateLimitSnapshot? {
        guard let file = newestJSONL(in: codexTranscriptRoot),
              let lines = tailLines(file, maxBytes: 262144) else { return nil }
        for line in lines.reversed() {
            guard line.contains("\"token_count\""),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any] else { continue }
            let info = payload["info"] as? [String: Any]
            return RateLimitSnapshot(
                primary: parseLimit(limits["primary"]),
                secondary: parseLimit(limits["secondary"]),
                planType: limits["plan_type"] as? String ?? "",
                modelContextWindow: (info?["model_context_window"] as? NSNumber)?.intValue ?? 0,
                updatedAt: parseTimestamp(obj["timestamp"] as? String) ?? Date()
            )
        }
        return nil
    }

    func parseLimit(_ value: Any?) -> LimitWindow? {
        guard let obj = value as? [String: Any] else { return nil }
        return LimitWindow(
            usedPercent: (obj["used_percent"] as? NSNumber)?.doubleValue ?? 0,
            windowMinutes: (obj["window_minutes"] as? NSNumber)?.intValue ?? 0,
            resetsAt: (obj["resets_at"] as? NSNumber)?.doubleValue ?? 0
        )
    }

    func parseTimestamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    func newestJSONL(in root: String) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: root) else { return nil }
        var best: (path: String, date: Date)?
        for case let rel as String in en where rel.hasSuffix(".jsonl") {
            let p = (root as NSString).appendingPathComponent(rel)
            guard let attrs = try? fm.attributesOfItem(atPath: p),
                  let m = attrs[.modificationDate] as? Date else { continue }
            if best == nil || m > best!.date { best = (p, m) }
        }
        return best?.path
    }

    func tailLines(_ path: String, maxBytes: UInt64) -> [String]? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        try? fh.seek(toOffset: size > maxBytes ? size - maxBytes : 0)
        guard let data = try? fh.readToEnd(),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").map(String.init)
    }

    func headLines(_ path: String, maxBytes: Int) -> [String]? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: maxBytes),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").map(String.init)
    }
}

// Single-instance guard. Two .app bundles can share this bundle id — a dev build in
// build/ running alongside the installed /Applications copy, or a leftover pre-upgrade
// instance — and each spawns its own status items, so the menu bar shows duplicate
// (old + new style) bars. Terminate any other running instance so the newest wins.
func terminateOtherInstances() {
    guard let me = Bundle.main.bundleIdentifier else { return }
    let myPID = ProcessInfo.processInfo.processIdentifier
    for other in NSWorkspace.shared.runningApplications
    where other.bundleIdentifier == me && other.processIdentifier != myPID {
        if !other.terminate() { other.forceTerminate() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
terminateOtherInstances()
let controller = StatusController()
app.run()
