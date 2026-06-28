import Cocoa

final class SessionRowView: NSView {
    weak var target: AnyObject?
    var action: Selector?
    var representedTag = 0
    private var tracking: NSTrackingArea?
    private var pressedInside = false
    private var hovering = false {
        didSet { updateAppearance() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 6
        updateAppearance()
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
        pressedInside = bounds.contains(convert(event.locationInWindow, from: nil))
        updateAppearance()
    }

    override func mouseDragged(with event: NSEvent) {
        // Cancel the press visually when the pointer is dragged out, and restore
        // it when dragged back in — the same affordance a real button gives.
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressedInside else { return }
        pressedInside = inside
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = pressedInside && bounds.contains(convert(event.locationInWindow, from: nil))
        pressedInside = false
        updateAppearance()
        guard inside, let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    private func updateAppearance() {
        // Stronger accent tint while the mouse is held down (tactile "press"
        // feedback), lighter on plain hover, transparent at rest.
        let tint: CGFloat = pressedInside ? 0.24 : (hovering ? 0.12 : 0)
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(tint).cgColor
    }
}

final class PassthroughVisualEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CompletionPopoverArrowView: NSView {
    static let size = NSSize(width: 13, height: 7)

    var fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88) {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        let tipRadius = min(bounds.width, bounds.height) * 0.22
        let shoulderInset = bounds.width * 0.12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.midX - tipRadius, y: bounds.minY + tipRadius))
        path.curve(
            to: NSPoint(x: bounds.midX + tipRadius, y: bounds.minY + tipRadius),
            controlPoint1: NSPoint(x: bounds.midX - tipRadius * 0.55, y: bounds.minY),
            controlPoint2: NSPoint(x: bounds.midX + tipRadius * 0.55, y: bounds.minY)
        )
        path.curve(
            to: NSPoint(x: bounds.maxX - shoulderInset, y: bounds.maxY),
            controlPoint1: NSPoint(x: bounds.midX + bounds.width * 0.20, y: bounds.minY + tipRadius * 1.15),
            controlPoint2: NSPoint(x: bounds.maxX - shoulderInset * 1.15, y: bounds.maxY)
        )
        path.line(to: NSPoint(x: shoulderInset, y: bounds.maxY))
        path.curve(
            to: NSPoint(x: bounds.midX - tipRadius, y: bounds.minY + tipRadius),
            controlPoint1: NSPoint(x: shoulderInset * 1.15, y: bounds.maxY),
            controlPoint2: NSPoint(x: bounds.midX - bounds.width * 0.20, y: bounds.minY + tipRadius * 1.15)
        )
        path.close()
        path.fill()
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

// A plain container whose origin sits at the top-left (flipped), used as the scroll document
// view so the overflow session rows can be stacked top-to-bottom in natural reading order.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class StatusController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
    let quitSuppressPath = (NSHomeDirectory() as NSString).appendingPathComponent(".vibego/quit-suppressed")
    let editorBridgesDir = (NSHomeDirectory() as NSString).appendingPathComponent(".vibego/editor-bridges")
    let claudeDesktopBundleID = "com.anthropic.claudefordesktop"
    let codexBundleID = "com.openai.codex"

    var lastMTime: Date = .distantPast
    var lastCodexMTime: Date = .distantPast
    var lastQuotaScan: Date = .distantPast
    var lastTitleScan: Date = .distantPast
    var pollTimer: Timer?
    var animTimer: Timer?
    var frameIdx = 0

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
    var overflowToggleTitleByTag: [Int: String] = [:]
    var nextSessionTag = 1
    // Which agent sections currently show their "+n more sessions" overflow expanded inline.
    // Reset on every menu open (see menuNeedsChange), so closing and reopening the popup
    // always restores the collapsed "+n more sessions" state.
    var expandedOverflowSections: Set<String> = []
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
    enum DynamicBackgroundStyle: String, CaseIterable {
        case liquid
        case breathing

        var title: String {
            switch self {
            case .liquid: return "Liquid"
            case .breathing: return "Breathing"
            }
        }

        // Accepts the current "breathing" value and the legacy "pulse" value, so an upgrade
        // doesn't silently reset a previously chosen Pulse background back to Liquid.
        init?(persistedValue: String) {
            switch persistedValue {
            case "liquid": self = .liquid
            case "breathing", "pulse": self = .breathing
            default: return nil
            }
        }
    }
    var animStyle: AnimStyle = .web
    var showTimer = false
    var showDynamicStatusBackground = true
    var dynamicBackgroundStyle: DynamicBackgroundStyle = .liquid
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
    var showCompletionPopup = true // drop a toast under the icon when a turn finishes
    var prevClaudeState = ""       // per-agent last state, for the completion popup
    var prevCodexState = ""
    var didObserveCompletionStates = false
    var completionWindow: NSPanel?
    var completionPopoverTimer: Timer?
    var completionPopoverPositionTimer: Timer?
    var completionPopoverStatus: AgentStatus?
    var didShowAutomationDeniedAlert = false
    var statusBarIconCentersBySource: [String: CGFloat] = [:]
    var iconColor: NSColor? { iconSystem ? nil : brand } // nil => render as an adaptive template
    let codeGlyphs = ["✻", "✽", "✶", "✳", "✢"]
    let codePeaks: [CGFloat] = [1.0, 1.0, 1.0, 1.0, 1.0]
    let codeDip: CGFloat = 0.14 // glyph shrinks to this at each swap
    let codeSub = 18            // sub-frames per glyph (tween smoothness)
    let codeCycle: Double = 3.8 // seconds for the full loop (lower = faster)
    lazy var codeGlyphMasks: [NSImage] = codeGlyphs.map { StatusController.glyphMask($0) }
    let crabFPS: Double = 12.5 // matches the source GIF's 0.08s frame delay
    let dynamicStatusBackgroundFPS: Double = 30
    let dynamicStatusBackgroundCycle: TimeInterval = 4.8
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
    var statusRefreshFPS: Double {
        showDynamicStatusBackground ? max(fps, dynamicStatusBackgroundFPS) : fps
    }
    let activeStatusBarHorizontalPadding: CGFloat = 6
    let activeStatusBarVerticalPadding: CGFloat = 3
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
        var closedAt: Double = 0
        var transcript: String
        var client: String = ""
        var terminalApp: String = ""
        var terminalBundleId: String = ""
        var terminalSessionId: String = ""
        var tty: String = ""
        var isActive: Bool { state == "thinking" || state == "tool" || state == "permission" || state == "waiting" }
        var isAnimating: Bool { state == "thinking" || state == "tool" }
        var isClosed: Bool { state == "closed" || closedAt > 0 }
        var isDisplayableResult: Bool { state == "done" || isClosed }
    }

    override init() {
        super.init()
        let d = UserDefaults.standard
        if d.object(forKey: "showTimer") != nil { showTimer = d.bool(forKey: "showTimer") }
        if d.object(forKey: "dynamicStatusBackground") != nil { showDynamicStatusBackground = d.bool(forKey: "dynamicStatusBackground") }
        if let s = d.string(forKey: "dynamicBackgroundStyle"), let st = DynamicBackgroundStyle(persistedValue: s) { dynamicBackgroundStyle = st }
        if d.object(forKey: "iconSystem") != nil { iconSystem = d.bool(forKey: "iconSystem") }
        if d.object(forKey: "completionSound") != nil { playCompletionSound = d.bool(forKey: "completionSound") }
        if d.object(forKey: "completionPopup") != nil { showCompletionPopup = d.bool(forKey: "completionPopup") }
        if let s = d.string(forKey: "animStyle"), let st = AnimStyle(rawValue: s) { animStyle = st }
        clearUserQuitSuppression()
        configureStatusItem(statusItem)
        setStatusItem(statusItem, icon: vibeGoStatusBarIcon(), label: "", startedAt: 0)
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
                NSLog("vibego: could not find node; hooks not installed (will retry next launch)")
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
    let releaseAPIURL = "https://api.github.com/repos/woolson/VibeGo/releases"
    let releasePageURL = "https://github.com/woolson/VibeGo/releases/latest"
    let repoURL = "https://github.com/woolson/VibeGo"
    let releaseLineResetDate = "2026-06-27T00:00:00Z"

    // Once/day: cache GitHub's latest release tag in UserDefaults. Nothing sent to us.
    // See CLAUDE.md "Update check" for the privacy/behavior notes.
    func checkForUpdate() {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if now - d.double(forKey: "lastUpdateCheck") < 86400 { return }
        guard let url = URL(string: releaseAPIURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("vibego", forHTTPHeaderField: "User-Agent") // GitHub API requires a UA
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            guard let obj = releases.first(where: { self.isReleaseInCurrentLine($0) }),
                  let tag = obj["tag_name"] as? String else {
                UserDefaults.standard.removeObject(forKey: "latestVersion")
                UserDefaults.standard.removeObject(forKey: "latestReleaseURL")
                UserDefaults.standard.set(false, forKey: "latestVersionIsCurrentLine")
                UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
                return
            }
            let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            UserDefaults.standard.set(ver, forKey: "latestVersion")
            if let htmlURL = obj["html_url"] as? String {
                UserDefaults.standard.set(htmlURL, forKey: "latestReleaseURL")
            }
            UserDefaults.standard.set(true, forKey: "latestVersionIsCurrentLine")
            UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
        }.resume()
    }

    func isReleaseInCurrentLine(_ release: [String: Any]) -> Bool {
        if (release["draft"] as? Bool) == true { return false }
        if (release["prerelease"] as? Bool) == true { return false }
        guard let published = release["published_at"] as? String,
              let publishedDate = ISO8601DateFormatter().date(from: published),
              let resetDate = ISO8601DateFormatter().date(from: releaseLineResetDate) else { return false }
        return publishedDate >= resetDate
    }

    // Numeric component-wise compare so "0.0.10" > "0.0.9".
    func versionIsNewer(_ a: String, than b: String) -> Bool {
        let pa = versionComponents(a)
        let pb = versionComponents(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func versionComponents(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .map { Int($0) ?? 0 }
    }

    @objc func openLatestRelease() {
        let cached = UserDefaults.standard.string(forKey: "latestReleaseURL")
        if let url = URL(string: cached ?? releasePageURL) { NSWorkspace.shared.open(url) }
    }

    @objc func openGitHubRepo() {
        if let url = URL(string: repoURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Each open of the status bar popup starts with every section collapsed, so closing
        // the popup and reopening it always restores the "+n more sessions" summary.
        expandedOverflowSections.removeAll()
        menu.removeAllItems()
        checkForUpdate() // refreshes the update cache for next open (gated to once a day)

        menu.addItem(usageOverviewItem())
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu()
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About", action: nil, keyEquivalent: "")
        aboutItem.submenu = aboutMenu()
        menu.addItem(aboutItem)
        let d = UserDefaults.standard
        if d.bool(forKey: "latestVersionIsCurrentLine"),
           let latest = d.string(forKey: "latestVersion"),
           versionIsNewer(latest, than: currentVersion) {
            let up = NSMenuItem(title: "Update available", action: #selector(openLatestRelease), keyEquivalent: "")
            up.target = self
            menu.addItem(up)
        }
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    func settingsMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(header("Function Controls"))
        let timerItem = NSMenuItem(title: "Show timer", action: #selector(toggleTimer), keyEquivalent: "")
        timerItem.target = self
        timerItem.state = showTimer ? .on : .off
        menu.addItem(timerItem)

        let soundItem = NSMenuItem(title: "Play Completion Sound", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = playCompletionSound ? .on : .off
        if #available(macOS 14.0, *) { soundItem.badge = NSMenuItemBadge(string: "1m+") }
        menu.addItem(soundItem)

        let popupItem = NSMenuItem(title: "Show Completion Prompt", action: #selector(togglePopup), keyEquivalent: "")
        popupItem.target = self
        popupItem.state = showCompletionPopup ? .on : .off
        menu.addItem(popupItem)

        menu.addItem(.separator())
        menu.addItem(header("Interface Effects"))
        let backgroundItem = NSMenuItem(title: "Enable Dynamic Background", action: #selector(toggleDynamicStatusBackground), keyEquivalent: "")
        backgroundItem.target = self
        backgroundItem.state = showDynamicStatusBackground ? .on : .off
        menu.addItem(backgroundItem)

        let styleItem = NSMenuItem(title: "Background Style", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for style in DynamicBackgroundStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(chooseDynamicBackgroundStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = dynamicBackgroundStyle == style ? .on : .off
            item.isEnabled = showDynamicStatusBackground
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        styleItem.isEnabled = showDynamicStatusBackground
        menu.addItem(styleItem)
        return menu
    }

    func aboutMenu() -> NSMenu {
        let menu = NSMenu()
        let versionItem = NSMenuItem(title: "Version \(currentVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let githubItem = NSMenuItem(title: "View on GitHub", action: #selector(openGitHubRepo), keyEquivalent: "")
        githubItem.target = self
        menu.addItem(githubItem)
        return menu
    }

    func usageOverviewItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = buildOverviewView()
        return item
    }

    // Builds (or rebuilds) the overview view shown as the menu's first item. Re-runnable so
    // toggling a section's overflow expansion can relayout the same item in place.
    func buildOverviewView() -> NSView {
        sessionDetailsByTag.removeAll()
        agentSourceByTag.removeAll()
        overflowToggleTitleByTag.removeAll()
        nextSessionTag = 1
        let claudeRows = displaySessions(claudeSessionStatuses, fallback: claudeEff)
        let codexRows = displaySessions(codexSessionStatuses, fallback: codexEff)
        let claudeHeight = agentSectionHeight(title: "Claude", sessions: claudeRows)
        let codexHeight = agentSectionHeight(title: "Codex", sessions: codexRows)
        let topPadding: CGFloat = 8
        // Space below the Codex section before the native menu separator. Paired with the ~1pt
        // section bottom padding (see sectionHeight) so the Codex "+n more sessions" sits ~12pt
        // above that divider, matching the Claude section's gap to the internal divider above it.
        let bottomPadding: CGFloat = 5
        let sectionGap: CGFloat = 22
        let totalHeight = topPadding + claudeHeight + sectionGap + codexHeight + bottomPadding
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: totalHeight))
        let codexY = bottomPadding
        let dividerY = codexY + codexHeight + (sectionGap / 2)
        let claudeY = codexY + codexHeight + sectionGap
        addAgentSection(to: view, y: claudeY, height: claudeHeight, title: "Claude", quota: claudeQuota, sessions: claudeRows)
        addDivider(to: view, y: dividerY)
        addAgentSection(to: view, y: codexY, height: codexHeight, title: "Codex", quota: codexQuota, sessions: codexRows)
        return view
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
        let overflowCount = sessions.count - visibleSessionLimit
        guard overflowCount > 0 else { return }
        if expandedOverflowSections.contains(title) {
            // Expanded: replace the "+n more sessions" summary with a scrollable list of the
            // remaining sessions. The view is anchored to the section's bottom edge (origin.y = y)
            // so it always fits as the section grows taller — see agentSectionHeight.
            let overflow = Array(sessions.dropFirst(visibleSessionLimit))
            let scrollH = CGFloat(min(overflow.count, 10)) * 22
            parent.addSubview(overflowScrollView(overflow: overflow, bottomY: y, height: scrollH))
        } else {
            // Collapsed: a clickable row that expands the section inline. Custom-view clicks
            // keep the menu open, so the toggle can relayout the item without dismissing it.
            let toggle = SessionRowView(frame: NSRect(x: 10, y: rowY - 3, width: 370, height: 22))
            toggle.target = self
            toggle.action = #selector(toggleOverflowExpansion(_:))
            toggle.representedTag = nextSessionTag
            overflowToggleTitleByTag[nextSessionTag] = title
            nextSessionTag += 1
            toggle.addSubview(menuLabel("+\(overflowCount) more sessions", x: 28, y: 2, width: width - 52, height: 18, size: 11, color: .tertiaryLabelColor, centerVertically: true))
            parent.addSubview(toggle)
        }
    }

    func addSessionRow(to parent: NSView, status: AgentStatus, y: CGFloat) {
        let row = SessionRowView(frame: NSRect(x: 10, y: y - 3, width: 370, height: 22))
        populateSessionRow(row, status: status)
        parent.addSubview(row)
    }

    // Configures a session row view (tag registration + status dot + title/status labels) and
    // wires its click to open that session's conversation. Shared by the inline rows and the
    // overflow scroll list so both render identically.
    func populateSessionRow(_ row: SessionRowView, status: AgentStatus) {
        row.target = self
        row.action = #selector(openSessionConversation(_:))
        row.representedTag = nextSessionTag
        sessionDetailsByTag[nextSessionTag] = status
        nextSessionTag += 1

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
        row.addSubview(menuLabel(sessionTitle(status), x: 28, y: 2, width: 228, height: 18, size: 11, color: .labelColor, centerVertically: true))
        row.addSubview(menuLabel(statusText(status), x: 260, y: 2, width: 104, height: 18, size: 10, color: .secondaryLabelColor, alignRight: true, centerVertically: true))
    }

    @objc func openSessionConversation(_ sender: AnyObject) {
        let tag = (sender as? SessionRowView)?.representedTag ?? (sender as? NSButton)?.tag ?? 0
        guard let status = sessionDetailsByTag[tag] else { dbg("openSessionConversation tag=\(tag): NO STATUS"); return }
        dbg("openSessionConversation tag=\(tag) source=\(status.source) client=\(status.client) state=\(status.state) isClosed=\(status.isClosed) tty=\(status.tty) bundleID=\(status.terminalBundleId)")
        DispatchQueue.main.async { [weak self] in
            self?.openConversation(status)
        }
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
        let results = sessions
            .filter { !$0.isActive && $0.isDisplayableResult }
            .sorted { $0.ts > $1.ts }
        // Running tasks present: show all of them, plus any just-finished ones alongside.
        if !active.isEmpty {
            return (active + results).sorted {
                if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
                return $0.ts > $1.ts
            }
        }
        // Idle: keep finished tasks available so the menu can show the first few plus
        // a "+n more sessions" overflow row.
        if !results.isEmpty { return results }
        return fallback.isActive ? [fallback] : []
    }

    func sectionHeight(rowCount: Int) -> CGFloat {
        if rowCount == 0 { return 53 }
        let rows = rowCount > 3 ? 4 : max(1, rowCount)
        // Base 30 leaves ~1pt below the last row / "+n more sessions" toggle, so the toggle rests
        // ~12pt above the divider beneath it (1pt padding + 11pt, half of sectionGap or bottomPadding).
        return CGFloat(30 + rows * 22)
    }

    // Height of one agent section. When collapsed this matches sectionHeight (3 inline rows +
    // a "+n more sessions" summary). When expanded it replaces that summary row with a scroll
    // list of the overflow sessions, capped at 10 visible rows.
    func agentSectionHeight(title: String, sessions: [AgentStatus]) -> CGFloat {
        let overflow = max(0, sessions.count - 3)
        if overflow > 0, expandedOverflowSections.contains(title) {
            // 114pt covers the header + 3 inline rows on the 22pt grid; the scroll list anchors
            // to the section's bottom edge so the section simply grows downward by its height.
            return 114 + CGFloat(min(overflow, 10)) * 22
        }
        return sectionHeight(rowCount: sessions.count)
    }

    // A vertically-scrolling list of the overflow sessions, anchored at `bottomY` (the section's
    // bottom edge) and `height` rows tall. Up to 10 rows are visible; the rest scroll. Rows are
    // built with the same populateSessionRow used by the inline rows so they look and behave
    // identically (click to open the conversation).
    func overflowScrollView(overflow: [AgentStatus], bottomY: CGFloat, height: CGFloat) -> NSScrollView {
        let contentWidth: CGFloat = 370
        let docHeight = CGFloat(overflow.count) * 22
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: docHeight))
        doc.wantsLayer = true
        var topY: CGFloat = 0
        for status in overflow {
            let row = SessionRowView(frame: NSRect(x: 0, y: topY, width: contentWidth, height: 22))
            populateSessionRow(row, status: status)
            doc.addSubview(row)
            topY += 22
        }
        let scroll = NSScrollView(frame: NSRect(x: 10, y: bottomY, width: contentWidth, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.documentView = doc
        return scroll
    }

    @objc func toggleOverflowExpansion(_ sender: AnyObject) {
        let tag = (sender as? SessionRowView)?.representedTag ?? (sender as? NSButton)?.tag ?? 0
        guard let title = overflowToggleTitleByTag[tag] else { return }
        if expandedOverflowSections.contains(title) {
            expandedOverflowSections.remove(title)
        } else {
            expandedOverflowSections.insert(title)
        }
        rebuildOverviewLive()
    }

    // Rebuilds the overview item's view while the menu is open and reassigns it so AppKit
    // reflows the menu to the new (taller/shorter) height. The expanded-state set persists
    // across this rebuild; it is only cleared when the menu is next opened (menuNeedsUpdate).
    func rebuildOverviewLive() {
        guard let menu = statusItem.menu, let item = menu.item(at: 0) else { return }
        item.view = buildOverviewView()
    }

    enum ResetStyle {
        case hoursMinutes
        case daysHours
    }

    func quotaOverviewView(_ quota: RateLimitSnapshot?, x: CGFloat, y: CGFloat, width: CGFloat) -> NSView {
        // No usage data (neither limit window resolved): hide the progress blade and countdown,
        // showing only a placeholder. Keep the same height (14 + 2 + 7) so the header alignment
        // is unchanged. If just one window resolved we still render normally below.
        if quota == nil || (quota?.primary == nil && quota?.secondary == nil) {
            let view = NSView(frame: NSRect(x: x, y: y, width: width, height: 23))
            view.addSubview(menuLabel("(no data)", x: 0, y: 0, width: width, height: 23, size: 10, color: .tertiaryLabelColor, alignRight: true, centerVertically: true))
            return view
        }
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
        if status.isClosed { return NSColor.secondaryLabelColor }
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

    func multilineLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, bold: Bool = false, size: CGFloat = 11, color: NSColor? = nil, maximumLines: Int = 2) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: height)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = color ?? (bold ? NSColor.labelColor : NSColor.secondaryLabelColor)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = maximumLines
        label.cell?.wraps = true
        label.cell?.usesSingleLineMode = false
        label.cell?.lineBreakMode = .byTruncatingTail
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
        if status.isClosed { return "Closed" }
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

    @objc func quit() {
        markUserQuitSuppressed()
        NSApp.terminate(nil)
    }

    func markUserQuitSuppressed() {
        let fm = FileManager.default
        let dir = (quitSuppressPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let payload = "\(Date().timeIntervalSince1970)\n"
        try? payload.write(toFile: quitSuppressPath, atomically: true, encoding: .utf8)
    }

    func clearUserQuitSuppression() {
        try? FileManager.default.removeItem(atPath: quitSuppressPath)
    }

    func openConversation(_ status: AgentStatus) {
        dbg("openConversation ENTER source=\(status.source) client=\(status.client) state=\(status.state) isClosed=\(status.isClosed)")
        let ws = NSWorkspace.shared
        if status.client.lowercased() == "cli" {
            if !status.isClosed, openTerminalSession(status) { return }
            if openTerminalSession(status) { return }
            if let transcript = transcriptPath(for: status) {
                ws.open(URL(fileURLWithPath: transcript))
                return
            }
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

    // Editor-integrated terminals (VSCode / Cursor / Qoder) aren't AppleScript-addressable the way
    // Terminal/iTerm tabs are. Each editor runs the VibeGo Bridge extension, which owns the only
    // tty→terminal map and serves a localhost HTTP endpoint. We discover live bridges from files in
    // editorBridgesDir and ask each to focus (or type into) the pane that owns `tty`.

    func editorBridgeEndpoints() -> [(port: Int, token: String, file: String, app: String, proc: String)] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: editorBridgesDir) else { return [] }
        var out: [(port: Int, token: String, file: String, app: String, proc: String)] = []
        for file in files where file.hasSuffix(".json") {
            let p = (editorBridgesDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: p),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["token"] as? String,
                  let port = (obj["port"] as? Int) ?? ((obj["port"] as? NSNumber)?.intValue) else { continue }
            if port > 0 {
                out.append((port: port, token: token, file: p, app: (obj["app"] as? String) ?? "", proc: (obj["proc"] as? String) ?? ""))
            }
        }
        return out
    }

    // Restore a covered/minimized editor window via the Accessibility API. The bridge already raises
    // its own window when it focuses the pane, but Electron editors don't expose AppleScript's
    // minimization, so we toggle AXMinimized through System Events here too as a backup — whichever
    // holds Accessibility permission (VibeGo or the editor) wins. System Events names a process by its
    // EXECUTABLE (VSCode is "Code", not "Visual Studio Code"), so prefer the bridge's reported `proc`
    // and only fall back to the display name (mapping the VSCode case). Needs the holder to have
    // Accessibility access (one-time TCC prompt). Run off the main thread so a pending permission
    // dialog never blocks the click.
    func raiseEditor(appName: String, proc: String) {
        var target = proc.isEmpty ? appName : proc
        guard !target.isEmpty else { return }
        if target == "Visual Studio Code" { target = "Code" }
        let q = target.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
          set frontmost of process "\(q)" to true
          try
            set value of attribute "AXMinimized" of every window of process "\(q)" to false
          end try
        end tell
        """
        DispatchQueue.global().async { [weak self] in
            let appleScript = NSAppleScript(source: script)
            var error: NSDictionary?
            appleScript?.executeAndReturnError(&error)
            if let error { self?.dbg("raiseEditor AX err: \(error[NSAppleScript.errorNumber] ?? "?")") }
        }
    }

    // Synchronous (mirrors runAppleScript's blocking style; openSessionConversation already pushes
    // openConversation onto the main queue). Returns true once any live editor claims the tty.
    func callEditorBridge(tty: String) -> Bool {
        enum Outcome { case claimed, alive, dead }
        let route = "/focus"
        let body: [String: Any] = ["tty": tty]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 0.6
        cfg.timeoutIntervalForResource = 1.0
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)

        for ep in editorBridgeEndpoints() {
            guard let url = URL(string: "http://127.0.0.1:\(ep.port)\(route)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer " + ep.token, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = payload

            var outcome: Outcome = .alive
            let sem = DispatchSemaphore(value: 0)
            let task = session.dataTask(with: req) { _, response, error in
                if let http = response as? HTTPURLResponse {
                    outcome = (http.statusCode == 200) ? .claimed : .alive
                } else {
                    outcome = .dead // transport error (refused/timeout) → stale discovery file
                }
                sem.signal()
            }
            task.resume()
            if sem.wait(timeout: .now() + 0.8) == .timedOut { task.cancel() }
            switch outcome {
            case .claimed:
                dbg("editor bridge port=\(ep.port) focused tty=\(tty)")
                raiseEditor(appName: ep.app, proc: ep.proc)
                return true
            case .dead:
                try? FileManager.default.removeItem(atPath: ep.file) // prune stale bridge
            case .alive:
                break // bridge up but doesn't own this tty → try the next editor
            }
        }
        return false
    }

    func openTerminalSession(_ status: AgentStatus) -> Bool {
        let bundleID = status.terminalBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let tty = status.tty.trimmingCharacters(in: .whitespacesAndNewlines)
        dbg("openTerminalSession bundleID=\(bundleID) tty=\(tty)")
        // Editor terminals (VSCode/Cursor/Qoder) carry no bundleId — ask the bridge to focus the
        // matching pane before falling through. No overhead for Terminal/iTerm (their bundleId is set).
        if bundleID.isEmpty, !tty.isEmpty, callEditorBridge(tty: tty) { return true }
        if !tty.isEmpty {
            if bundleID == "com.apple.Terminal" {
                let ok = runAppleScript(terminalSelectScript(tty: tty))
                dbg("Terminal select-script result=\(ok ? 1 : 0)")
                if ok { return true }
            }
            if bundleID == "com.googlecode.iterm2", runAppleScript(iTermSelectScript(tty: tty)) { return true }
        }
        if bundleID == "com.mitchellh.ghostty",
           !status.terminalSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           runAppleScript(ghosttySelectScript(terminalId: status.terminalSessionId)) {
            return true
        }
        dbg("falling back to plain openApplication")
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    func terminalRunScript(command: String, tty: String) -> String {
        let escapedCommand = appleScriptString(command)
        let escapedTTY = appleScriptString(tty)
        return """
        \(appleScriptTTYHelpers())
        tell application id "com.apple.Terminal"
          activate
          if \(escapedTTY) is not equal to "" then
            repeat with w in windows
              repeat with t in tabs of w
                try
                  if my ttyMatches((tty of t as string), \(escapedTTY)) then
                    set index of w to 1
                    set selected of t to true
                    do script \(escapedCommand) in t
                    return true
                  end if
                end try
              end repeat
            end repeat
          end if
          do script \(escapedCommand)
        end tell
        return true
        """
    }

    func iTermRunScript(command: String, tty: String) -> String {
        let escapedCommand = appleScriptString(command)
        let escapedTTY = appleScriptString(tty)
        return """
        \(appleScriptTTYHelpers())
        tell application id "com.googlecode.iterm2"
          activate
          if \(escapedTTY) is not equal to "" then
            repeat with w in windows
              repeat with t in tabs of w
                repeat with s in sessions of t
                  try
                    if my ttyMatches((tty of s as string), \(escapedTTY)) then
                      select s
                      select t
                      set index of w to 1
                      tell s to write text \(escapedCommand)
                      return true
                    end if
                  end try
                end repeat
              end repeat
            end repeat
          end if
          if (count of windows) is 0 then
            create window with default profile
          end if
          tell current session of current window to write text \(escapedCommand)
        end tell
        return true
        """
    }

    func ghosttyRunScript(command: String) -> String {
        let escapedCommand = appleScriptString(command)
        return """
        tell application id "com.mitchellh.ghostty"
          activate
          set cfg to new surface configuration from {command:\(escapedCommand), wait after command:true}
          if (count of windows) is 0 then
            new window with configuration cfg
          else
            new tab in front window with configuration cfg
          end if
        end tell
        return true
        """
    }

    func terminalSelectScript(tty: String) -> String {
        let escapedTTY = appleScriptString(tty)
        return """
        \(appleScriptTTYHelpers())
        tell application id "com.apple.Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              try
                if my ttyMatches((tty of t as string), \(escapedTTY)) then
                  set index of w to 1
                  set selected of t to true
                  return true
                end if
              end try
            end repeat
          end repeat
        end tell
        return false
        """
    }

    func iTermSelectScript(tty: String) -> String {
        let escapedTTY = appleScriptString(tty)
        return """
        \(appleScriptTTYHelpers())
        tell application id "com.googlecode.iterm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                try
                  if my ttyMatches((tty of s as string), \(escapedTTY)) then
                    select s
                    select t
                    set index of w to 1
                    return true
                  end if
                end try
              end repeat
            end repeat
          end repeat
        end tell
        return false
        """
    }

    func ghosttySelectScript(terminalId: String) -> String {
        let escapedTerminalId = appleScriptString(terminalId.trimmingCharacters(in: .whitespacesAndNewlines))
        return """
        tell application id "com.mitchellh.ghostty"
          activate
          repeat with w in windows
            repeat with tb in tabs of w
              repeat with trm in terminals of tb
                try
                  if (id of trm as string) is equal to \(escapedTerminalId) then
                    focus trm
                    return true
                  end if
                end try
              end repeat
            end repeat
          end repeat
        end tell
        return false
        """
    }

    func appleScriptTTYHelpers() -> String {
        """
        on normalizedTTY(v)
          set s to v as string
          if s starts with "/dev/" and (length of s) > 5 then
            return text 6 thru -1 of s
          end if
          return s
        end normalizedTTY

        on ttyMatches(a, b)
          set aa to my normalizedTTY(a)
          set bb to my normalizedTTY(b)
          return aa is not equal to "" and aa is equal to bb
        end ttyMatches
        """
    }

    // TEMP diagnostic: logs to both unified log and ~/.claude/statusbar/click-debug.log so we
    // can trace the click path even when `log show` won't surface NSLog.
    func dbg(_ msg: String) {
        NSLog("vibego: %@", msg)
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/statusbar/click-debug.log")
        let line = "\(Date().timeIntervalSince1970) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    func runAppleScript(_ script: String) -> Bool {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        if let error {
            dbg("AppleScript ERROR: \(error.description)")
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                showAutomationDeniedAlert()
            }
            return false
        }
        return result?.booleanValue == true
    }

    func showAutomationDeniedAlert() {
        if didShowAutomationDeniedAlert { return }
        didShowAutomationDeniedAlert = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "VibeGo needs permission to control Terminal"
            alert.informativeText = "Allow VibeGo under System Settings > Privacy & Security > Automation so it can select the exact Terminal, iTerm, or Ghostty tab for CLI sessions."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "OK")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            self.didShowAutomationDeniedAlert = false
        }
    }

    func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    @objc func toggleDynamicStatusBackground() {
        showDynamicStatusBackground.toggle()
        UserDefaults.standard.set(showDynamicStatusBackground, forKey: "dynamicStatusBackground")
        animTimer?.invalidate(); animTimer = nil
        renderAgents()
    }

    @objc func chooseDynamicBackgroundStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = DynamicBackgroundStyle(rawValue: raw) else { return }
        dynamicBackgroundStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: "dynamicBackgroundStyle")
        animTimer?.invalidate(); animTimer = nil
        renderAgents()
    }

    @objc func toggleSound() {
        playCompletionSound.toggle()
        UserDefaults.standard.set(playCompletionSound, forKey: "completionSound")
    }

    @objc func togglePopup() {
        showCompletionPopup.toggle()
        UserDefaults.standard.set(showCompletionPopup, forKey: "completionPopup")
        if !showCompletionPopup {
            dismissCompletionPopover(animated: true)
        }
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
        // Per-agent done transition drives the completion popup (fires on every finish,
        // unlike the sound which gates on a 1-minute turn).
        let claudeJustDone = didObserveCompletionStates && claudeEff.state == "done" && prevClaudeState != "done"
        let codexJustDone = didObserveCompletionStates && codexEff.state == "done" && prevCodexState != "done"
        prevClaudeState = claudeEff.state
        prevCodexState = codexEff.state
        didObserveCompletionStates = true

        if !claudeEff.isAnimating && !codexEff.isAnimating { lastTurnStart = 0 }
        prevEff = combinedEff

        renderAgents()

        if showCompletionPopup {
            if claudeJustDone { showCompletionPopover(for: claudeEff) }
            else if codexJustDone { showCompletionPopover(for: codexEff) }
        }
    }

    // MARK: completion popup

    // A transient toast that drops straight down from the status bar icon when a turn
    // finishes. It is anchored to the single status item, which renders Claude and
    // Codex together when both are active.
    func showCompletionPopover(for status: AgentStatus) {
        completionPopoverTimer?.invalidate()
        completionPopoverPositionTimer?.invalidate()
        dismissCompletionPopover(animated: false)
        completionPopoverStatus = status
        statusItem.menu?.cancelTracking()

        // Defer the anchor to the next runloop turn. renderAgents() just changed the
        // icon/label/width for the end of this turn; reading button.bounds before that
        // relayout settles would point the popover's arrow at the icon's old position.
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let button = self.statusItem.button, button.window != nil else { return }
            let size = NSSize(width: 223, height: 50 + CompletionPopoverArrowView.size.height)
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.hasShadow = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            panel.contentViewController = self.completionPopoverContent(for: status)
            panel.alphaValue = 1
            self.completionWindow = panel
            self.repositionCompletionPopover()
            panel.orderFrontRegardless()

            let t = Timer(timeInterval: 10.0, repeats: false) { [weak self] _ in
                self?.dismissCompletionPopover(animated: true)
            }
            RunLoop.main.add(t, forMode: .common)
            self.completionPopoverTimer = t

            let positionTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.repositionCompletionPopover()
            }
            RunLoop.main.add(positionTimer, forMode: .common)
            self.completionPopoverPositionTimer = positionTimer
        }
    }

    func repositionCompletionPopover() {
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              let toastWindow = completionWindow else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let anchor = buttonWindow.convertToScreen(buttonRectInWindow)
        let anchorXInButton = completionPopoverAnchorX(in: button)
        let anchorScreenX = anchor.minX + anchorXInButton
        var frame = toastWindow.frame
        frame.origin.x = anchorScreenX - frame.width / 2
        frame.origin.y = anchor.minY - frame.height - 8

        if let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, screenFrame.minX + 6), screenFrame.maxX - frame.width - 6)
            frame.origin.y = min(max(frame.origin.y, screenFrame.minY + 6), screenFrame.maxY - frame.height - 6)
        }
        toastWindow.setFrame(frame, display: true)
        updateCompletionPopoverArrow(anchorScreenX: anchorScreenX, windowFrame: frame)
    }

    func completionPopoverAnchorX(in button: NSStatusBarButton) -> CGFloat {
        guard let status = completionPopoverStatus,
              let iconCenter = statusBarIconCentersBySource[status.source] else {
            return button.bounds.midX
        }
        let imageWidth = button.image?.size.width ?? button.bounds.width
        let imagePad = max(0, (button.bounds.width - imageWidth) / 2)
        return imagePad + iconCenter
    }

    func updateCompletionPopoverArrow(anchorScreenX: CGFloat, windowFrame: NSRect) {
        guard let root = completionWindow?.contentViewController?.view else { return }
        let arrow = root.subviews.first { $0.identifier?.rawValue == "completionPopoverArrow" }
        let arrowWidth = CompletionPopoverArrowView.size.width
        let minX = CGFloat(14)
        let maxX = max(minX, root.bounds.width - arrowWidth - 14)
        let x = min(max(anchorScreenX - windowFrame.minX - arrowWidth / 2, minX), maxX)
        arrow?.frame.origin.x = x
    }

    func dismissCompletionPopover(animated: Bool, completion: (() -> Void)? = nil) {
        completionPopoverTimer?.invalidate()
        completionPopoverTimer = nil
        completionPopoverPositionTimer?.invalidate()
        completionPopoverPositionTimer = nil

        guard let toastWindow = completionWindow else {
            completionPopoverStatus = nil
            completion?()
            return
        }

        let finish = { [weak self, weak toastWindow] in
            toastWindow?.close()
            if self?.completionWindow === toastWindow {
                self?.completionWindow = nil
                self?.completionPopoverStatus = nil
            }
            completion?()
        }

        guard animated else {
            finish()
            return
        }

        var targetFrame = toastWindow.frame
        targetFrame = targetFrame.insetBy(dx: 8, dy: 3)
        targetFrame.origin.y += 8

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            toastWindow.animator().alphaValue = 0
            toastWindow.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            finish()
        }
    }

    func completionPopoverContent(for status: AgentStatus) -> NSViewController {
        let width: CGFloat = 223, bodyHeight: CGFloat = 50, arrowHeight = CompletionPopoverArrowView.size.height
        let height = bodyHeight + arrowHeight
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor

        let arrow = completionPopoverArrowView(frame: NSRect(x: (width - CompletionPopoverArrowView.size.width) / 2, y: bodyHeight, width: CompletionPopoverArrowView.size.width, height: arrowHeight))
        arrow.autoresizingMask = []
        root.addSubview(arrow)

        let content = SessionRowView(frame: NSRect(x: 0, y: 0, width: width, height: bodyHeight))
        content.autoresizingMask = [.width, .height]
        content.target = self
        content.action = #selector(openCompletionPopoverConversation(_:))
        content.layer?.backgroundColor = NSColor.clear.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            content.layer?.cornerCurve = .continuous
        }

        let appIconView = NSImageView(frame: NSRect(x: 14, y: (bodyHeight - 28) / 2, width: 28, height: 28))
        appIconView.image = appIcon(for: status.source)
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(appIconView)

        let iconView = NSImageView(frame: NSRect(x: 31, y: 9, width: 13, height: 13))
        if #available(macOS 11.0, *),
           let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Task complete") {
            img.isTemplate = true
            iconView.image = img
            iconView.contentTintColor = NSColor.systemGreen
        }
        content.addSubview(iconView)

        // The app icon conveys the source; the right-side copy gets up to two lines before
        // truncating. A single-line title is drawn in a vertically-centered cell (its own line
        // height is much shorter than the body), so it sits mid-row instead of pinned to the top.
        let title = status.title.isEmpty ? status.source : status.title
        let titleWidth = width - 64
        let titleFont = NSFont.boldSystemFont(ofSize: 13)
        let isSingleLine = (title as NSString).size(withAttributes: [.font: titleFont]).width <= titleWidth
        if isSingleLine {
            content.addSubview(menuLabel(title, x: 52, y: 0, width: titleWidth, height: bodyHeight, bold: true, size: 13, color: .labelColor, centerVertically: true))
        } else {
            let titleHeight: CGFloat = 34
            content.addSubview(multilineLabel(title, x: 52, y: floor((bodyHeight - titleHeight) / 2), width: titleWidth, height: titleHeight, bold: true, size: 13, color: .labelColor, maximumLines: 2))
        }

        let vc = NSViewController()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: width, height: bodyHeight))
            glass.cornerRadius = 14
            glass.tintColor = brand.withAlphaComponent(0.08)
            glass.style = .regular
            glass.contentView = content
            root.addSubview(glass, positioned: .below, relativeTo: arrow)
            vc.view = root
        } else {
            let blur = PassthroughVisualEffectView(frame: content.bounds)
            blur.autoresizingMask = [.width, .height]
            blur.blendingMode = .behindWindow
            blur.material = .popover
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 14
            blur.layer?.masksToBounds = true
            if #available(macOS 10.15, *) {
                blur.layer?.cornerCurve = .continuous
            }
            content.addSubview(blur, positioned: .below, relativeTo: nil)
            root.addSubview(content, positioned: .below, relativeTo: arrow)
            vc.view = root
        }
        return vc
    }

    func completionPopoverArrowView(frame: NSRect) -> NSView {
        let view: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = 0
            glass.tintColor = brand.withAlphaComponent(0.08)
            glass.style = .regular
            glass.wantsLayer = true
            glass.layer?.mask = completionPopoverArrowMask(size: frame.size)
            view = glass
        } else {
            let arrow = CompletionPopoverArrowView(frame: frame)
            arrow.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.88)
            view = arrow
        }
        view.identifier = NSUserInterfaceItemIdentifier("completionPopoverArrow")
        return view
    }

    func completionPopoverArrowMask(size: NSSize) -> CALayer {
        let path = CGMutablePath()
        let tipRadius = min(size.width, size.height) * 0.22
        let shoulderInset = size.width * 0.12
        let midX = size.width / 2
        let tipY = size.height - tipRadius

        path.move(to: CGPoint(x: midX - tipRadius, y: tipY))
        path.addCurve(
            to: CGPoint(x: midX + tipRadius, y: tipY),
            control1: CGPoint(x: midX - tipRadius * 0.55, y: size.height),
            control2: CGPoint(x: midX + tipRadius * 0.55, y: size.height)
        )
        path.addCurve(
            to: CGPoint(x: size.width - shoulderInset, y: 0),
            control1: CGPoint(x: midX + size.width * 0.20, y: tipY - tipRadius * 0.15),
            control2: CGPoint(x: size.width - shoulderInset * 1.15, y: 0)
        )
        path.addLine(to: CGPoint(x: shoulderInset, y: 0))
        path.addCurve(
            to: CGPoint(x: midX - tipRadius, y: tipY),
            control1: CGPoint(x: shoulderInset * 1.15, y: 0),
            control2: CGPoint(x: midX - size.width * 0.20, y: tipY - tipRadius * 0.15)
        )
        path.closeSubpath()

        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: size)
        mask.path = path
        return mask
    }

    @objc func openCompletionPopoverConversation(_ sender: AnyObject) {
        guard let status = completionPopoverStatus else { return }
        dismissCompletionPopover(animated: true) { [weak self] in
            self?.openConversation(status)
        }
    }

    func effectiveStatus(from current: [String: Any], source: String) -> AgentStatus {
        let rawState = current["state"] as? String ?? "idle"
        var label = current["label"] as? String ?? ""
        let project = current["project"] as? String ?? ""
        let tool = current["tool"] as? String ?? ""
        let sessionId = current["sessionId"] as? String ?? ""
        let explicitTitle = current["title"] as? String ?? ""
        let ts = (current["ts"] as? NSNumber)?.doubleValue ?? 0
        var closedAt = (current["closedAt"] as? NSNumber)?.doubleValue ?? 0
        var started = (current["startedAt"] as? NSNumber)?.doubleValue ?? 0
        let transcript = current["transcript"] as? String ?? ""
        let client = current["client"] as? String ?? ""
        let terminalApp = current["terminalApp"] as? String ?? ""
        let terminalBundleId = current["terminalBundleId"] as? String ?? ""
        let terminalSessionId = current["terminalSessionId"] as? String ?? ""
        let tty = current["tty"] as? String ?? ""
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
                if source == "Claude", client.lowercased() == "cli" {
                    state = "closed"; label = "Closed"; started = 0
                    if closedAt == 0 { closedAt = ts > 0 ? ts : Date().timeIntervalSince1970 }
                } else {
                    state = "idle"; label = ""; started = 0
                }
            }
        }
        var title = explicitTitle.isEmpty ? titleForSession(source: source, sessionId: sessionId) : explicitTitle
        if title.isEmpty, source == "Claude" {
            title = titleFromClaudeTranscript(transcript)
        }
        return AgentStatus(source: source, state: state, label: label, project: project, tool: tool, sessionId: sessionId, title: title, startedAt: started, ts: ts, closedAt: closedAt, transcript: transcript, client: client, terminalApp: terminalApp, terminalBundleId: terminalBundleId, terminalSessionId: terminalSessionId, tty: tty)
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
        // Keep active and recently finished sessions; only drop stale idle sessions that
        // never reached a terminal state.
        return statuses.filter { $0.isActive || $0.isDisplayableResult || now - $0.ts < 300 }
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
        activeBase = combinedStatusBarLabel(active)
        startedAt = active.compactMap { $0.startedAt > 0 ? $0.startedAt : nil }.min() ?? 0
        activeColor = iconColor

        if animate || (!active.isEmpty && showDynamicStatusBackground) {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / statusRefreshFPS, repeats: true) { [weak self] _ in self?.animStep() }
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
            statusBarIconCentersBySource = [:]
            setStatusItem(statusItem, icon: vibeGoStatusBarIcon(), label: "", startedAt: 0, hidden: false)
            return
        }

        if active.count > 1 {
            setCombinedStatusItem(statusItem, statuses: active)
            return
        }

        let status = active[0]
        let iconPadding = showDynamicStatusBackground ? activeStatusBarHorizontalPadding : 0
        statusBarIconCentersBySource = [status.source: iconPadding + max(statusBarIcon(for: status).size.width, 18) / 2]
        setStatusItem(
            statusItem,
            icon: statusBarIcon(for: status),
            label: statusBarLabel(for: status),
            startedAt: status.startedAt,
            hidden: false,
            textColor: status.state == "permission" ? amber : NSColor.labelColor,
            flipIcon: status.isAnimating,
            animatedBackground: showDynamicStatusBackground
        )
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

    func combinedStatusBarLabel(_ active: [AgentStatus]) -> String {
        guard active.count > 1 else { return active.first.map { statusBarLabel(for: $0) } ?? "" }
        let labels = active.map { statusBarLabel(for: $0) }
        return labels.allSatisfy { $0 == labels.first } ? (labels.first ?? "") : labels.joined(separator: "  ")
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

    func combinedIcon(frame: Int, active: [AgentStatus]) -> NSImage {
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

    // MARK: lifecycle

    func claudeDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == claudeDesktopBundleID }
    }

    func sessionCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir).count) ?? 0
    }

    func codexSessionCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: codexSessionsDir).count) ?? 0
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
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil // we paint the icon color ourselves; template-tint is unreliable
        activeBase = label
        activeColor = color
        self.startedAt = startedAt

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / statusRefreshFPS, repeats: true) { [weak self] _ in self?.animStep() }
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

    // While a session is executing, the icon loops through three motions: a vertical
    // 3D flip, a flat in-place spin, then a horizontal 3D flip.
    // CoreAnimation runs on the render server, so it keeps moving even while the menu
    // owns the run loop, and survives the frequent button.image updates.
    func iconFlipAnimation() -> CAKeyframeAnimation {
        let anim = CAKeyframeAnimation(keyPath: "transform")
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 480.0 // adds depth so the flip reads as 3D, not a flat squish
        func rot(_ deg: CGFloat, x: CGFloat, y: CGFloat, z: CGFloat) -> NSValue {
            NSValue(caTransform3D: CATransform3DRotate(perspective, deg * .pi / 180, x, y, z))
        }

        let step = 0.8
        let pause = 2.0
        let total = (step * 3) + (pause * 3)
        func t(_ seconds: CGFloat) -> NSNumber {
            NSNumber(value: Double(seconds / total))
        }
        func addFlipCycle(start: CGFloat, axis: (x: CGFloat, y: CGFloat, z: CGFloat), values: inout [NSValue], keyTimes: inout [NSNumber]) {
            values += [
                rot(0, x: axis.x, y: axis.y, z: axis.z),
                rot(70, x: axis.x, y: axis.y, z: axis.z),
                rot(0, x: axis.x, y: axis.y, z: axis.z),
                rot(-70, x: axis.x, y: axis.y, z: axis.z),
                rot(0, x: axis.x, y: axis.y, z: axis.z),
                rot(0, x: axis.x, y: axis.y, z: axis.z),
            ]
            keyTimes += [
                t(start),
                t(start + step * 0.25),
                t(start + step * 0.5),
                t(start + step * 0.75),
                t(start + step),
                t(start + step + pause),
            ]
        }
        func addSpinCycle(start: CGFloat, values: inout [NSValue], keyTimes: inout [NSNumber]) {
            values += [
                rot(0, x: 0, y: 0, z: 1),
                rot(90, x: 0, y: 0, z: 1),
                rot(180, x: 0, y: 0, z: 1),
                rot(270, x: 0, y: 0, z: 1),
                rot(360, x: 0, y: 0, z: 1),
                rot(360, x: 0, y: 0, z: 1),
            ]
            keyTimes += [
                t(start),
                t(start + step * 0.25),
                t(start + step * 0.5),
                t(start + step * 0.75),
                t(start + step),
                t(start + step + pause),
            ]
        }

        var values: [NSValue] = []
        var keyTimes: [NSNumber] = []
        addFlipCycle(start: 0, axis: (0, 1, 0), values: &values, keyTimes: &keyTimes)
        addSpinCycle(start: step + pause, values: &values, keyTimes: &keyTimes)
        addFlipCycle(start: (step + pause) * 2, axis: (1, 0, 0), values: &values, keyTimes: &keyTimes)
        anim.values = values
        anim.keyTimes = keyTimes
        anim.duration = CFTimeInterval(total)
        anim.repeatCount = .infinity
        anim.calculationMode = .linear
        anim.isRemovedOnCompletion = false
        return anim
    }

    // The icon flips alone: it lives in its own sublayer (default anchorPoint .5,.5, so it
    // pivots about its own center) drawn on top of the text-only button image. The baked
    // image omits the icon while flipping, so the elapsed-time text never rotates.
    func updateIconLayer(_ button: NSStatusBarButton, icon: NSImage, imageWidth: CGFloat, iconXOffset: CGFloat = 0) {
        removeCombinedIconLayers(button)
        button.wantsLayer = true
        guard let host = button.layer else { return }
        host.masksToBounds = false
        let iconSize = NSSize(width: max(icon.size.width, 18), height: 18)
        let flipPadding: CGFloat = 8
        let layerSize = NSSize(width: iconSize.width + flipPadding * 2, height: iconSize.height + flipPadding * 2)
        let paddedIcon = paddedIconImage(icon, iconSize: iconSize, canvasSize: layerSize)
        let layer = host.sublayers?.first { $0.name == "iconFlip" } ?? {
            let l = CALayer(); l.name = "iconFlip"; host.addSublayer(l); return l
        }()
        layer.masksToBounds = false
        layer.isDoubleSided = true
        layer.allowsEdgeAntialiasing = true
        layer.zPosition = 10
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = paddedIcon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        // The cell centers the image, so its left edge sits at (buttonWidth - imageWidth)/2;
        // the icon occupies the image's leftmost 18pt. Mirror that so the layer lines up.
        let pad = max(0, (button.bounds.width - imageWidth) / 2)
        let y = max(0, (button.bounds.height - iconSize.height) / 2)
        layer.frame = CGRect(
            x: pad + iconXOffset - flipPadding,
            y: y - flipPadding,
            width: layerSize.width,
            height: layerSize.height
        )
        if layer.animation(forKey: "flip") == nil {
            layer.add(iconFlipAnimation(), forKey: "flip")
        }
    }

    func updateCombinedIconLayers(_ button: NSStatusBarButton, statuses: [AgentStatus], imageWidth: CGFloat, animatedBackground: Bool) {
        button.layer?.sublayers?.first { $0.name == "iconFlip" }?.removeFromSuperlayer()
        button.wantsLayer = true
        guard let host = button.layer else { return }
        host.masksToBounds = false
        let activeSources = Set(statuses.filter(\.isAnimating).map(\.source))
        host.sublayers?
            .filter { ($0.name ?? "").hasPrefix("combinedIconFlip:") && !activeSources.contains(String(($0.name ?? "").dropFirst("combinedIconFlip:".count))) }
            .forEach { $0.removeFromSuperlayer() }

        let positions = statusBarSegmentIconLeftOffsets(for: statuses, animatedBackground: animatedBackground)
        for status in statuses where status.isAnimating {
            let source = status.source
            guard let xOffset = positions[source] else { continue }
            let icon = statusBarIcon(for: status)
            updateNamedIconLayer(
                button,
                name: "combinedIconFlip:\(source)",
                icon: icon,
                imageWidth: imageWidth,
                iconXOffset: xOffset
            )
        }
        if activeSources.isEmpty { removeCombinedIconLayers(button) }
    }

    func updateNamedIconLayer(_ button: NSStatusBarButton, name: String, icon: NSImage, imageWidth: CGFloat, iconXOffset: CGFloat) {
        button.wantsLayer = true
        guard let host = button.layer else { return }
        let iconSize = NSSize(width: max(icon.size.width, 18), height: 18)
        let flipPadding: CGFloat = 8
        let layerSize = NSSize(width: iconSize.width + flipPadding * 2, height: iconSize.height + flipPadding * 2)
        let paddedIcon = paddedIconImage(icon, iconSize: iconSize, canvasSize: layerSize)
        let layer = host.sublayers?.first { $0.name == name } ?? {
            let l = CALayer(); l.name = name; host.addSublayer(l); return l
        }()
        layer.masksToBounds = false
        layer.isDoubleSided = true
        layer.allowsEdgeAntialiasing = true
        layer.zPosition = 10
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = paddedIcon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let pad = max(0, (button.bounds.width - imageWidth) / 2)
        let y = max(0, (button.bounds.height - iconSize.height) / 2)
        layer.frame = CGRect(
            x: pad + iconXOffset - flipPadding,
            y: y - flipPadding,
            width: layerSize.width,
            height: layerSize.height
        )
        if layer.animation(forKey: "flip") == nil {
            layer.add(iconFlipAnimation(), forKey: "flip")
        }
    }

    func paddedIconImage(_ icon: NSImage, iconSize: NSSize, canvasSize: NSSize) -> NSImage {
        let img = NSImage(size: canvasSize, flipped: false) { _ in
            let rect = NSRect(
                x: floor((canvasSize.width - iconSize.width) / 2),
                y: floor((canvasSize.height - iconSize.height) / 2),
                width: iconSize.width,
                height: iconSize.height
            )
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        img.isTemplate = false
        return img
    }

    func removeIconLayer(_ button: NSStatusBarButton) {
        button.layer?.sublayers?.first { $0.name == "iconFlip" }?.removeFromSuperlayer()
        removeCombinedIconLayers(button)
    }

    func removeCombinedIconLayers(_ button: NSStatusBarButton) {
        button.layer?.sublayers?
            .filter { ($0.name ?? "").hasPrefix("combinedIconFlip:") }
            .forEach { $0.removeFromSuperlayer() }
    }

    func applyTitle() {
        guard let button = statusItem.button else { return }
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

    func setStatusItem(_ item: NSStatusItem, icon: NSImage, label: String, startedAt: Double, hidden: Bool = false, textColor: NSColor = .labelColor, flipIcon: Bool = false, animatedBackground: Bool = false) {
        guard let button = item.button else { return }
        let text = statusBarDisplayText(label: label, startedAt: startedAt)
        // While flipping, draw the text only (icon omitted) and let the animating sublayer
        // supply the icon, so the 3D flip applies to the icon alone.
        let image: NSImage?
        if hidden {
            image = nil
        } else if text.isEmpty && !flipIcon {
            image = animatedBackground ? statusBarItemImage(icon: icon, text: "", textColor: textColor, animatedBackground: true) : icon
        } else {
            image = statusBarItemImage(icon: flipIcon ? nil : icon, text: text, textColor: textColor, animatedBackground: animatedBackground)
        }
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
            updateIconLayer(button, icon: icon, imageWidth: image?.size.width ?? 18, iconXOffset: animatedBackground ? activeStatusBarHorizontalPadding : 0)
        }
    }

    func setCombinedStatusItem(_ item: NSStatusItem, statuses: [AgentStatus]) {
        guard let button = item.button else { return }
        statusBarIconCentersBySource = statusBarSegmentIconCenters(for: statuses)
        let image = statusBarSegmentsImage(statuses.map {
            (
                icon: $0.isAnimating ? nil : statusBarIcon(for: $0),
                text: statusBarDisplayText(label: statusBarLabel(for: $0), startedAt: $0.startedAt),
                textColor: $0.state == "permission" ? amber : NSColor.labelColor
            )
        }, animatedBackground: showDynamicStatusBackground)
        item.length = image.size.width + 8
        button.isHidden = false
        button.contentTintColor = nil
        button.image = image
        button.imagePosition = .imageOnly
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        updateCombinedIconLayers(button, statuses: statuses, imageWidth: image.size.width, animatedBackground: showDynamicStatusBackground)
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

    func statusBarSegmentIconCenters(for statuses: [AgentStatus]) -> [String: CGFloat] {
        let iconTextGap: CGFloat = 5
        let segmentGap: CGFloat = 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        var x: CGFloat = showDynamicStatusBackground ? activeStatusBarHorizontalPadding : 0
        var centers: [String: CGFloat] = [:]

        for (idx, status) in statuses.enumerated() {
            if idx > 0 { x += segmentGap }
            let iconWidth = max(statusBarIcon(for: status).size.width, 18)
            centers[status.source] = x + iconWidth / 2
            x += iconWidth

            let text = statusBarDisplayText(label: statusBarLabel(for: status), startedAt: status.startedAt)
            if !text.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                x += iconTextGap + NSAttributedString(string: text, attributes: attrs).size().width
            }
        }

        return centers
    }

    func statusBarSegmentIconLeftOffsets(for statuses: [AgentStatus], animatedBackground: Bool) -> [String: CGFloat] {
        let iconTextGap: CGFloat = 5
        let segmentGap: CGFloat = 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        var x: CGFloat = animatedBackground ? activeStatusBarHorizontalPadding : 0
        var offsets: [String: CGFloat] = [:]

        for (idx, status) in statuses.enumerated() {
            if idx > 0 { x += segmentGap }
            offsets[status.source] = x
            x += max(statusBarIcon(for: status).size.width, 18)

            let text = statusBarDisplayText(label: statusBarLabel(for: status), startedAt: status.startedAt)
            if !text.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                x += iconTextGap + NSAttributedString(string: text, attributes: attrs).size().width
            }
        }

        return offsets
    }

    // icon == nil reserves the icon's width but leaves it blank — used while the icon is
    // flipping in its own sublayer, so the text stays in exactly the same place.
    func statusBarItemImage(icon: NSImage?, text: String, textColor: NSColor = .labelColor, animatedBackground: Bool = false) -> NSImage {
        let iconWidth = max(icon?.size.width ?? 18, 18)
        let iconHeight: CGFloat = 18
        let height: CGFloat = animatedBackground ? 18 + activeStatusBarVerticalPadding * 2 : 18
        let gap: CGFloat = text.isEmpty ? 0 : 5
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .font: font,
        ]
        let textSize = text.isEmpty ? .zero : NSAttributedString(string: text, attributes: attrs).size()
        let contentWidth = ceil(iconWidth + gap + textSize.width)
        let width = contentWidth + (animatedBackground ? activeStatusBarHorizontalPadding * 2 : 0)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if animatedBackground {
                self.drawActiveStatusBarBackground(in: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
            }
            let contentX = animatedBackground ? self.activeStatusBarHorizontalPadding : 0
            let iconY = floor((height - iconHeight) / 2)
            icon?.draw(in: NSRect(x: contentX, y: iconY, width: iconWidth, height: iconHeight), from: .zero, operation: .sourceOver, fraction: 1)
            if !text.isEmpty {
                let textY = floor((height - textSize.height) / 2)
                text.draw(at: NSPoint(x: contentX + iconWidth + gap, y: textY), withAttributes: attrs)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    func statusBarSegmentsImage(_ segments: [(icon: NSImage?, text: String, textColor: NSColor)], animatedBackground: Bool = false) -> NSImage {
        let iconHeight: CGFloat = 18
        let height: CGFloat = animatedBackground ? 18 + activeStatusBarVerticalPadding * 2 : 18
        let iconTextGap: CGFloat = 5
        let segmentGap: CGFloat = 12
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let measured = segments.map { segment in
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: segment.textColor,
                .font: font,
            ]
            let textSize = segment.text.isEmpty ? .zero : NSAttributedString(string: segment.text, attributes: attrs).size()
            return (segment: segment, attrs: attrs, textSize: textSize, iconWidth: max(segment.icon?.size.width ?? 18, 18))
        }
        let contentWidth = ceil(measured.enumerated().reduce(CGFloat(0)) { acc, item in
            let gap = item.offset == 0 ? CGFloat(0) : segmentGap
            let textGap = item.element.segment.text.isEmpty ? CGFloat(0) : iconTextGap
            return acc + gap + item.element.iconWidth + textGap + item.element.textSize.width
        })
        let width = contentWidth + (animatedBackground ? activeStatusBarHorizontalPadding * 2 : 0)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            if animatedBackground {
                self.drawActiveStatusBarBackground(in: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
            }
            var x: CGFloat = animatedBackground ? self.activeStatusBarHorizontalPadding : 0
            for (idx, item) in measured.enumerated() {
                if idx > 0 { x += segmentGap }
                let iconY = floor((height - iconHeight) / 2)
                item.segment.icon?.draw(in: NSRect(x: x, y: iconY, width: item.iconWidth, height: iconHeight), from: .zero, operation: .sourceOver, fraction: 1)
                x += item.iconWidth
                if !item.segment.text.isEmpty {
                    x += iconTextGap
                    let textY = floor((height - item.textSize.height) / 2)
                    item.segment.text.draw(at: NSPoint(x: x, y: textY), withAttributes: item.attrs)
                    x += item.textSize.width
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // Linear RGBA blend (alpha included) between two colors. Used to ease a gradient's
    // endpoints between a dim wash and a lit glow as the background breathes.
    static func lerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let a = a.usingColorSpace(.sRGB) ?? a
        let b = b.usingColorSpace(.sRGB) ?? b
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return NSColor(
            srgbRed: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }

    func drawActiveStatusBarBackground(in rect: NSRect) {
        switch dynamicBackgroundStyle {
        case .liquid:
            drawLiquidStatusBarBackground(in: rect)
        case .breathing:
            drawBreathingStatusBarBackground(in: rect)
        }
    }

    func drawLiquidStatusBarBackground(in rect: NSRect) {
        let elapsed = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: dynamicStatusBackgroundCycle)
        let phase = CGFloat(elapsed / dynamicStatusBackgroundCycle)
        let capsule = rect.insetBy(dx: 0.5, dy: 1)
        let path = NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        NSColor.controlBackgroundColor.withAlphaComponent(0.52).setFill()
        capsule.fill()

        let colors = [
            NSColor(srgbRed: 0.58, green: 0.86, blue: 1.00, alpha: 0.30),
            NSColor(srgbRed: 0.96, green: 0.68, blue: 0.94, alpha: 0.24),
            NSColor(srgbRed: 1.00, green: 0.88, blue: 0.55, alpha: 0.22),
        ]
        let bandWidth = max(capsule.width * 0.72, 38)
        for (idx, color) in colors.enumerated() {
            let offset = (phase + CGFloat(idx) / CGFloat(colors.count)).truncatingRemainder(dividingBy: 1)
            let x = capsule.minX - bandWidth + offset * (capsule.width + bandWidth * 2)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: capsule.minY - capsule.height * 0.42, width: bandWidth, height: capsule.height * 1.84)).fill()
        }

        NSColor.white.withAlphaComponent(0.30).setFill()
        let shineWidth = max(12, capsule.width * 0.20)
        let shineX = capsule.minX - shineWidth + phase * (capsule.width + shineWidth * 2)
        NSBezierPath(roundedRect: NSRect(x: shineX, y: capsule.minY + 1, width: shineWidth, height: capsule.height - 2), xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.28).setStroke()
        path.lineWidth = 0.7
        path.stroke()
    }

    func drawBreathingStatusBarBackground(in rect: NSRect) {
        let elapsed = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: dynamicStatusBackgroundCycle)
        let phase = CGFloat(elapsed / dynamicStatusBackgroundCycle)
        let capsule = rect.insetBy(dx: 0.5, dy: 1)
        let path = NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        // Pill base holds the capsule shape even at the dim end of the breath.
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        capsule.fill()

        // One smooth in-out breath per cycle: 0 → 1 → 0.
        let breath = sin(phase * .pi)

        // The gradient endpoints ease between a dim wash and a lit glow, so the colors
        // themselves brighten and soften — not just a flat alpha tween. The blend midpoint
        // also slides left↔right so the color flows along the pill instead of holding still.
        let dim1 = NSColor(srgbRed: 0.50, green: 0.74, blue: 1.00, alpha: 0.10)
        let dim2 = NSColor(srgbRed: 0.84, green: 0.66, blue: 1.00, alpha: 0.08)
        let lit1 = NSColor(srgbRed: 0.58, green: 0.86, blue: 1.00, alpha: 0.46)
        let lit2 = NSColor(srgbRed: 1.00, green: 0.72, blue: 0.90, alpha: 0.36)
        let c1 = StatusController.lerpColor(dim1, lit1, breath)
        let c2 = StatusController.lerpColor(dim2, lit2, breath)
        let drift = 0.5 + sin(phase * .pi * 2) * 0.15 // blend midpoint: 0.35 ↔ 0.65
        let mid = StatusController.lerpColor(c1, c2, 0.5)
        if let grad = NSGradient(colors: [c1, mid, c2], atLocations: [0, drift, 1], colorSpace: .sRGB) {
            grad.draw(in: capsule, angle: 0)
        }

        // Glassy inner light that brightens with the breath.
        NSColor.white.withAlphaComponent(0.06 + breath * 0.12).setFill()
        NSBezierPath(roundedRect: capsule.insetBy(dx: 1.2, dy: 1.2), xRadius: capsule.height / 2, yRadius: capsule.height / 2).fill()

        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.24).setStroke()
        path.lineWidth = 0.7
        path.stroke()
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

    // A template menu-bar version of the VibeGo app icon. The filled alpha becomes the
    // system status item color, so it adapts on light and dark menu bar backgrounds.
    func vibeGoStatusBarIcon(showsDot: Bool = false) -> NSImage {
        let s: CGFloat = 18
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.17, y: 1.17, width: 15.66, height: 15.66)).fill()

            let v = NSBezierPath()
            v.lineWidth = 3.00
            v.lineCapStyle = .round
            v.lineJoinStyle = .round
            v.move(to: NSPoint(x: 4.46, y: 11.09))
            v.curve(
                to: NSPoint(x: 8.68, y: 5.51),
                controlPoint1: NSPoint(x: 5.81, y: 9.74),
                controlPoint2: NSPoint(x: 6.73, y: 6.0)
            )
            v.curve(
                to: NSPoint(x: 13.81, y: 11.68),
                controlPoint1: NSPoint(x: 10.62, y: 5.08),
                controlPoint2: NSPoint(x: 11.43, y: 10.2)
            )
            if let cg = NSGraphicsContext.current?.cgContext {
                cg.saveGState()
                cg.setBlendMode(.clear)
                v.stroke()
                cg.restoreGState()
            }

            if showsDot {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.2, y: 2.0, width: 3.2, height: 3.2)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
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
