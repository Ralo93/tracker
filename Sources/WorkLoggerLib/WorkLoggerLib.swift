import AppKit
import Carbon
import Foundation

// MARK: - Config

public struct Config: Codable {
    var logDirectory: String
    var idleThresholdSeconds: TimeInterval
    var defaultDurationMinutes: Int?
    var retentionDays: Int?
    var safariTrackingEnabled: Bool?
    var logSafariURLs: Bool?
    var logSafariDomainOnly: Bool?
    var showSafariTimeInReport: Bool?
    var consentGiven: Bool?

    // Stable location where all user edits are persisted (survives app rebuilds)
    static let userConfigPath: String =
        "\(NSHomeDirectory())/Library/Application Support/WorkLogger/config.json"

    // Bundle / repo-root config (read-only default)
    static let configPath: String = {
        if let bundled = Bundle.main.path(forResource: "config", ofType: "json") { return bundled }
        return FileManager.default.currentDirectoryPath + "/config.json"
    }()

    static func load() -> Config {
        let defaults = Config(
            logDirectory: "\(NSHomeDirectory())/Documents/WorkLogger/logs",
            idleThresholdSeconds: 300
        )
        let fm = FileManager.default
        // Bootstrap user config from bundle on very first launch
        if !fm.fileExists(atPath: userConfigPath),
           let bundled = Bundle.main.path(forResource: "config", ofType: "json") {
            let dir = (userConfigPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? fm.copyItem(atPath: bundled, toPath: userConfigPath)
            // Fix any hardcoded home dir from the bundle to the current user
            if var text = try? String(contentsOfFile: userConfigPath, encoding: .utf8) {
                let pattern = "/Users/[^/]+/"
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let home = NSHomeDirectory() + "/"
                    text = regex.stringByReplacingMatches(
                        in: text, range: NSRange(text.startIndex..., in: text), withTemplate: home)
                    try? text.write(toFile: userConfigPath, atomically: true, encoding: .utf8)
                }
            }
        }
        // Prefer user config, fall back to bundle/repo root
        for path in [userConfigPath, configPath] {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let config = try? JSONDecoder().decode(Config.self, from: data) {
                return config
            }
        }
        return defaults
    }

    func save() {
        // Merge into existing JSON to preserve report section and other keys
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: Config.userConfigPath)),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        json["logDirectory"] = logDirectory
        json["idleThresholdSeconds"] = idleThresholdSeconds
        if let dur = defaultDurationMinutes { json["defaultDurationMinutes"] = dur }
        if let ret = retentionDays { json["retentionDays"] = ret }
        if let s = safariTrackingEnabled { json["safariTrackingEnabled"] = s }
        if let s = logSafariURLs { json["logSafariURLs"] = s }
        if let s = logSafariDomainOnly { json["logSafariDomainOnly"] = s }
        if let s = showSafariTimeInReport { json["showSafariTimeInReport"] = s }
        if let c = consentGiven { json["consentGiven"] = c }
        guard let newData = try? JSONSerialization.data(withJSONObject: json,
                                                        options: [.prettyPrinted, .sortedKeys]) else { return }
        let dir = (Config.userConfigPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? newData.write(to: URL(fileURLWithPath: Config.userConfigPath))
        // Restrict config to owner-only
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: Config.userConfigPath)
    }
}

// MARK: - ReportPrefs

/// Reads and writes only the user-editable report keys (repositories, prefilledSlots)
/// using raw JSON so all other keys (gapMinutes, skipApps, …) are preserved exactly.
public struct ReportPrefs {
    var repositories: [String]
    var prefilledSlots: [String: [String]]   // weekday name → ["HH:MM-HH:MM"]
    var blockMinutes: Int
    var skipApps: [String]
    var skipSafariExact: [String]
    var skipSafariContains: [String]

    static func load() -> ReportPrefs {
        let path = FileManager.default.fileExists(atPath: Config.userConfigPath)
            ? Config.userConfigPath : Config.configPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let report = json["report"] as? [String: Any] else {
            return ReportPrefs(repositories: [], prefilledSlots: [:],
                              blockMinutes: 15, skipApps: [], skipSafariExact: [], skipSafariContains: [])
        }
        let repos = report["repositories"] as? [String] ?? []
        var slots: [String: [String]] = [:]
        if let raw = report["prefilledSlots"] as? [String: Any] {
            for (key, value) in raw where key != "comment" {
                if let arr = value as? [String] { slots[key] = arr }
            }
        }
        let blockMin = report["blockMinutes"] as? Int ?? 15
        let skipA = report["skipApps"] as? [String] ?? []
        let skipSE = report["skipSafariExact"] as? [String] ?? []
        let skipSC = report["skipSafariContains"] as? [String] ?? []
        return ReportPrefs(repositories: repos, prefilledSlots: slots,
                          blockMinutes: blockMin, skipApps: skipA,
                          skipSafariExact: skipSE, skipSafariContains: skipSC)
    }

    func save() {
        // Read whichever config file currently exists (user > bundle)
        let readPath = FileManager.default.fileExists(atPath: Config.userConfigPath)
            ? Config.userConfigPath : Config.configPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: readPath)),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        var report = json["report"] as? [String: Any] ?? [:]
        report["repositories"] = repositories
        var rawSlots = report["prefilledSlots"] as? [String: Any] ?? [:]
        let comment = rawSlots["comment"]
        for (day, ranges) in prefilledSlots { rawSlots[day] = ranges }
        if let comment = comment { rawSlots["comment"] = comment }
        report["prefilledSlots"] = rawSlots
        report["blockMinutes"] = blockMinutes
        report["skipApps"] = skipApps
        report["skipSafariExact"] = skipSafariExact
        report["skipSafariContains"] = skipSafariContains
        json["report"] = report
        guard let newData = try? JSONSerialization.data(withJSONObject: json,
                                                        options: [.prettyPrinted, .sortedKeys]) else { return }
        // Always write to the stable user config path
        let dir = (Config.userConfigPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? newData.write(to: URL(fileURLWithPath: Config.userConfigPath))
    }
}

// MARK: - Logger

public class Logger {
    private let fileManager = FileManager.default
    private let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()
    private let config: Config

    init(config: Config) {
        self.config = config
    }

    private var logDir: String { config.logDirectory }

    private var currentLogPath: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(logDir)/\(formatter.string(from: Date())).jsonl"
    }

    /// Extract domain from a URL string, stripping path/query/fragment.
    static func domainOnly(_ urlString: String) -> String {
        guard let comps = URLComponents(string: urlString), let host = comps.host else {
            // Fallback: strip after first / past scheme
            if let slashRange = urlString.range(of: "://") {
                let afterScheme = urlString[slashRange.upperBound...]
                return String(afterScheme.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" }))
            }
            return urlString
        }
        return host
    }

    /// Strip query string and fragment from a URL.
    static func stripQuery(_ urlString: String) -> String {
        guard var comps = URLComponents(string: urlString) else { return urlString }
        comps.query = nil
        comps.fragment = nil
        return comps.string ?? urlString
    }

    /// Sanitize a URL according to config privacy settings.
    func sanitizeURL(_ urlString: String) -> String {
        if config.logSafariDomainOnly ?? true {
            return Logger.domainOnly(urlString)
        }
        return Logger.stripQuery(urlString)
    }

    func log(_ fields: [String: Any]) {
        try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        // Truncate string values to 200 characters
        var entry: [String: Any] = [:]
        for (key, value) in fields {
            if let s = value as? String, s.count > 200 {
                entry[key] = String(s.prefix(200))
            } else {
                entry[key] = value
            }
        }
        entry["timestamp"] = iso8601.string(from: Date())

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys),
              let line = String(data: data, encoding: .utf8) else { return }

        let lineWithNewline = line + "\n"
        let path = currentLogPath

        if fileManager.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            handle.closeFile()
        } else {
            try? Data(lineWithNewline.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        // Restrict log file to owner-only
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Write an entry into a specific date's JSONL file (for retroactive entries).
    func logToDate(_ date: Date, fields: [String: Any]) {
        try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)

        var entry: [String: Any] = [:]
        for (key, value) in fields {
            if let s = value as? String, s.count > 200 {
                entry[key] = String(s.prefix(200))
            } else {
                entry[key] = value
            }
        }
        entry["timestamp"] = iso8601.string(from: date)

        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: .sortedKeys),
              let line = String(data: data, encoding: .utf8) else { return }

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        let path = "\(logDir)/\(dayFmt.string(from: date)).jsonl"
        let lineWithNewline = line + "\n"

        if fileManager.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(lineWithNewline.utf8))
            handle.closeFile()
        } else {
            try? Data(lineWithNewline.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// Delete JSONL files older than retentionDays.
    func purgeOldLogs() {
        let retention = config.retentionDays ?? 90
        guard retention > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retention, to: Date()) ?? Date()
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        guard let files = try? fileManager.contentsOfDirectory(atPath: logDir) else { return }
        for file in files where file.hasSuffix(".jsonl") {
            let name = (file as NSString).deletingPathExtension
            if let fileDate = dayFmt.date(from: name), fileDate < cutoff {
                try? fileManager.removeItem(atPath: "\(logDir)/\(file)")
            }
        }
    }
}

// MARK: - ActivityTracker

public class ActivityTracker {
    private let logger: Logger
    private let config: Config

    init(logger: Logger, config: Config) {
        self.logger = logger
        self.config = config
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc func screenLocked() { logger.log(["event": "screen_lock"]) }
    @objc func screenUnlocked() { logger.log(["event": "screen_unlock"]) }
    @objc func systemWillSleep() { logger.log(["event": "system_sleep"]) }
    @objc func systemDidWake() { logger.log(["event": "system_wake"]) }

    @objc func appDidChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

        let bundleId = app.bundleIdentifier ?? "unknown"
        var entry: [String: Any] = [
            "event": "app_switch",
            "app": app.localizedName ?? "unknown",
            "bundle_id": bundleId
        ]

        if bundleId == "com.apple.Safari" {
            if config.safariTrackingEnabled ?? true {
                let safari = safariInfo()
                entry["detail"] = safari.title ?? "unknown tab"
                if config.logSafariURLs ?? true, let url = safari.url {
                    entry["url"] = logger.sanitizeURL(url)
                }
            } else {
                entry["detail"] = "Safari"
            }
        } else if bundleId == "com.microsoft.VSCode" {
            entry["detail"] = vscodeWindowTitle() ?? "unknown window"
        } else {
            if let title = windowTitle(for: app) { entry["detail"] = title }
        }

        logger.log(entry)
    }

    private func windowTitle(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windowList
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
    }

    private func safariInfo() -> (title: String?, url: String?) {
        let script = """
        tell application "Safari"
            set t to name of current tab of front window
            set u to URL of current tab of front window
            return t & "||" & u
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let combined = result?.stringValue else { return (nil, nil) }
        let parts = combined.components(separatedBy: "||")
        let title = parts.first
        let url = parts.count > 1 ? parts[1] : nil
        return (title, url)
    }

    private func vscodeWindowTitle() -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windowList
            .filter {
                let owner = $0[kCGWindowOwnerName as String] as? String ?? ""
                return owner == "Code" || owner == "Visual Studio Code"
            }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
            .map { parseVSCodeTitle($0) }
    }

    private func parseVSCodeTitle(_ title: String) -> String {
        // VS Code format: "● filename — ProjectName" → extract ProjectName
        if let range = title.range(of: " \u{2014} ", options: .backwards) {
            return String(title[range.upperBound...])
        }
        return title
    }
}

// MARK: - SafariTabMonitor

public class SafariTabMonitor {
    private var timer: Timer?
    private var lastTab: String?
    private let logger: Logger
    private let config: Config

    init(logger: Logger, config: Config) {
        self.logger = logger
        self.config = config
    }

    func start() {
        guard config.safariTrackingEnabled ?? true else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkTab()
        }
    }

    private func checkTab() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari" else {
            return
        }
        let script = """
        tell application "Safari"
            set t to name of current tab of front window
            set u to URL of current tab of front window
            return t & "||" & u
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let combined = result?.stringValue else { return }
        let parts = combined.components(separatedBy: "||")
        let tab = parts.first ?? ""
        guard tab != lastTab else { return }
        lastTab = tab
        var entry: [String: Any] = ["event": "safari_tab_change", "detail": tab]
        if config.logSafariURLs ?? true, parts.count > 1 {
            entry["url"] = logger.sanitizeURL(parts[1])
        }
        logger.log(entry)
    }
}

// MARK: - VSCodeProjectMonitor

public class VSCodeProjectMonitor {
    private var timer: Timer?
    private var lastProject: String?
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkProject()
        }
    }

    private func checkProject() {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.microsoft.VSCode" else { return }
        guard let project = currentProject(), project != lastProject else { return }
        lastProject = project
        logger.log(["event": "vscode_project_change", "detail": project])
    }

    private func currentProject() -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windowList
            .filter {
                let owner = $0[kCGWindowOwnerName as String] as? String ?? ""
                return owner == "Code" || owner == "Visual Studio Code"
            }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
            .map { parseTitle($0) }
    }

    private func parseTitle(_ title: String) -> String {
        if let range = title.range(of: " \u{2014} ", options: .backwards) {
            return String(title[range.upperBound...])
        }
        return title
    }
}

// MARK: - IdleMonitor

public class IdleMonitor {
    private var timer: Timer?
    private var isIdle = false
    private var idleStartTime: Date?
    private let logger: Logger
    var threshold: TimeInterval

    init(logger: Logger, threshold: TimeInterval) {
        self.logger = logger
        self.threshold = threshold
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.check()
        }
    }

    private func check() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let idleKb = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let minIdle = min(idle, idleKb)

        if !isIdle && minIdle >= threshold {
            isIdle = true
            idleStartTime = Date().addingTimeInterval(-minIdle)
            logger.log(["event": "idle_start", "idle_seconds": Int(minIdle)])
        } else if isIdle && minIdle < threshold {
            let duration = idleStartTime.map { Int(Date().timeIntervalSince($0)) } ?? Int(minIdle)
            isIdle = false
            idleStartTime = nil
            logger.log(["event": "idle_end", "idle_duration_seconds": duration])
        }
    }
}

// MARK: - PreferencesWindowController

public class PreferencesWindowController: NSObject, NSWindowDelegate,
                                   NSTableViewDataSource, NSTableViewDelegate {
    private var window: NSWindow?
    private var tabView: NSTabView!

    // General tab
    private var logDirField: NSTextField!
    private var logDir: String = ""
    private var retentionDaysField: NSTextField!
    private var safariTrackingCheck: NSButton!
    private var logSafariURLsCheck: NSButton!
    private var domainOnlyCheck: NSButton!
    private var safariTimeCheck: NSButton!

    // Repos tab
    private var reposTable: NSTableView!
    private var repos: [String] = []

    // Slots tab
    private var slotsTable: NSTableView!
    private var dayPopup: NSPopUpButton!
    private var slotsByDay: [String: [String]] = [:]
    private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    private var selectedDay: String { weekdays[dayPopup?.indexOfSelectedItem ?? 0] }

    // Advanced tab
    private var defaultDurationField: NSTextField!
    private var blockMinutesField: NSTextField!
    private var idleThresholdField: NSTextField!
    private var skipAppsView: NSTextView!
    private var skipSafariExactView: NSTextView!
    private var skipSafariContainsView: NSTextView!

    var onSave: ((_ logDir: String, _ repos: [String], _ slots: [String: [String]],
                  _ defaultDuration: Int, _ blockMinutes: Int, _ idleThreshold: Int,
                  _ skipApps: [String], _ skipSafariExact: [String], _ skipSafariContains: [String],
                  _ retentionDays: Int, _ safariTrackingEnabled: Bool, _ logSafariURLs: Bool, _ logSafariDomainOnly: Bool, _ showSafariTime: Bool) -> Void)?

    func show(logDir: String, repos: [String], slots: [String: [String]],
              defaultDuration: Int, blockMinutes: Int, idleThreshold: Int,
              skipApps: [String], skipSafariExact: [String], skipSafariContains: [String],
              retentionDays: Int, safariTrackingEnabled: Bool, logSafariURLs: Bool, logSafariDomainOnly: Bool, showSafariTime: Bool) {
        self.logDir = logDir
        self.repos = repos
        self.slotsByDay = slots
        if window == nil { buildWindow() }
        logDirField.stringValue = logDir
        retentionDaysField.stringValue = "\(retentionDays)"
        safariTrackingCheck.state = safariTrackingEnabled ? .on : .off
        logSafariURLsCheck.state = logSafariURLs ? .on : .off
        domainOnlyCheck.state = logSafariDomainOnly ? .on : .off
        safariTimeCheck.state = showSafariTime ? .on : .off
        reposTable.reloadData()
        slotsTable.reloadData()
        defaultDurationField.stringValue = "\(defaultDuration)"
        blockMinutesField.stringValue = "\(blockMinutes)"
        idleThresholdField.stringValue = "\(idleThreshold)"
        skipAppsView.string = skipApps.joined(separator: "\n")
        skipSafariExactView.string = skipSafariExact.joined(separator: "\n")
        skipSafariContainsView.string = skipSafariContains.joined(separator: "\n")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "WorkLogger Preferences"
        win.center()
        win.delegate = self

        tabView = NSTabView(frame: NSRect(x: 0, y: 50, width: 520, height: 370))

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = "General"
        generalItem.view = buildGeneralView()
        tabView.addTabViewItem(generalItem)

        let reposItem = NSTabViewItem(identifier: "repos")
        reposItem.label = "Repositories"
        reposItem.view = buildReposView()
        tabView.addTabViewItem(reposItem)

        let slotsItem = NSTabViewItem(identifier: "slots")
        slotsItem.label = "Prefilled Slots"
        slotsItem.view = buildSlotsView()
        tabView.addTabViewItem(slotsItem)

        let advancedItem = NSTabViewItem(identifier: "advanced")
        advancedItem.label = "Advanced"
        advancedItem.view = buildAdvancedView()
        tabView.addTabViewItem(advancedItem)

        win.contentView?.addSubview(tabView)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.frame = NSRect(x: 428, y: 12, width: 80, height: 28)
        saveBtn.keyEquivalent = "\r"
        win.contentView?.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.frame = NSRect(x: 340, y: 12, width: 80, height: 28)
        cancelBtn.keyEquivalent = "\u{1b}"
        win.contentView?.addSubview(cancelBtn)

        self.window = win
    }

    private func buildGeneralView() -> NSView {
        let view = NSView()

        let label = NSTextField(labelWithString: "Log Directory:")
        label.frame = NSRect(x: 12, y: 308, width: 100, height: 18)
        view.addSubview(label)

        let hint = NSTextField(labelWithString: "JSONL event files are written here (one per day)")
        hint.frame = NSRect(x: 12, y: 284, width: 480, height: 16)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        view.addSubview(hint)

        logDirField = NSTextField(frame: NSRect(x: 12, y: 254, width: 400, height: 24))
        logDirField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logDirField.lineBreakMode = .byTruncatingHead
        logDirField.toolTip = "The folder where daily JSONL log files are stored.\nEach day creates a new file (e.g. 2025-07-14.jsonl).\nAll activity events, Safari tabs, VS Code projects, and idle states are written here."
        view.addSubview(logDirField)

        let browseBtn = NSButton(title: "Browse…", target: self, action: #selector(browseLogDir))
        browseBtn.frame = NSRect(x: 420, y: 252, width: 72, height: 28)
        view.addSubview(browseBtn)

        // --- Privacy & Retention ---
        let privacyHeader = NSTextField(labelWithString: "Privacy & Data Retention")
        privacyHeader.frame = NSRect(x: 12, y: 218, width: 300, height: 18)
        privacyHeader.font = .boldSystemFont(ofSize: 12)
        view.addSubview(privacyHeader)

        let retLabel = NSTextField(labelWithString: "Auto-delete logs older than")
        retLabel.frame = NSRect(x: 12, y: 190, width: 190, height: 18)
        view.addSubview(retLabel)
        retentionDaysField = NSTextField(frame: NSRect(x: 204, y: 188, width: 50, height: 22))
        retentionDaysField.toolTip = "JSONL log files older than this number of days are automatically deleted on launch.\nThis implements GDPR storage limitation (Article 5(1)(e)).\nDefault: 90 days."
        view.addSubview(retentionDaysField)
        let retSuffix = NSTextField(labelWithString: "days")
        retSuffix.frame = NSRect(x: 260, y: 190, width: 40, height: 18)
        view.addSubview(retSuffix)

        safariTrackingCheck = NSButton(checkboxWithTitle: "Track Safari tab changes", target: nil, action: nil)
        safariTrackingCheck.frame = NSRect(x: 12, y: 158, width: 250, height: 18)
        safariTrackingCheck.toolTip = "When enabled, WorkLogger monitors Safari for tab/window changes and logs them.\nWhen disabled, no Safari activity is recorded at all — neither titles nor URLs."
        view.addSubview(safariTrackingCheck)

        logSafariURLsCheck = NSButton(checkboxWithTitle: "Log Safari URLs in events", target: nil, action: nil)
        logSafariURLsCheck.frame = NSRect(x: 12, y: 134, width: 250, height: 18)
        logSafariURLsCheck.toolTip = "When enabled, the full URL of the active Safari tab is stored in log events.\nWhen disabled, only the page title is recorded — no URL is logged.\nRequires 'Track Safari tab changes' to be enabled."
        view.addSubview(logSafariURLsCheck)

        domainOnlyCheck = NSButton(checkboxWithTitle: "Store domain only (strip paths & query strings)", target: nil, action: nil)
        domainOnlyCheck.frame = NSRect(x: 12, y: 110, width: 350, height: 18)
        domainOnlyCheck.toolTip = "When enabled, URLs are trimmed to the domain only (e.g. 'github.com' instead of 'github.com/user/repo/issues/42?q=test').\nPaths, query parameters, and fragments are stripped before writing to the log file.\nRequires both Safari tracking and URL logging to be enabled."
        view.addSubview(domainOnlyCheck)

        safariTimeCheck = NSButton(checkboxWithTitle: "Show accumulated Safari tab time in report", target: nil, action: nil)
        safariTimeCheck.frame = NSRect(x: 12, y: 86, width: 350, height: 18)
        safariTimeCheck.toolTip = "When enabled, the weekly Excel report shows how long each Safari tab was active (e.g. 'Azure DevOps (12min)').\nTabs are ranked by time and the top 5 are shown. When disabled, only tab names are listed without durations."
        view.addSubview(safariTimeCheck)

        return view
    }

    @objc private func browseLogDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the directory for JSONL log files"
        if !logDirField.stringValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: logDirField.stringValue)
        }
        if panel.runModal() == .OK, let url = panel.url {
            logDirField.stringValue = url.path
        }
    }

    private func buildReposView() -> NSView {
        let view = NSView()

        let label = NSTextField(labelWithString: "Git repositories scanned for commits when generating reports:")
        label.frame = NSRect(x: 12, y: 308, width: 480, height: 18)
        view.addSubview(label)

        let sv = NSScrollView(frame: NSRect(x: 12, y: 50, width: 480, height: 252))
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder

        reposTable = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.width = 460
        reposTable.addTableColumn(col)
        reposTable.headerView = nil
        reposTable.dataSource = self
        reposTable.delegate = self
        sv.documentView = reposTable
        view.addSubview(sv)

        let addBtn = NSButton(title: "+", target: self, action: #selector(addRepo))
        addBtn.frame = NSRect(x: 12, y: 14, width: 32, height: 26)
        let removeBtn = NSButton(title: "−", target: self, action: #selector(removeRepo))
        removeBtn.frame = NSRect(x: 52, y: 14, width: 32, height: 26)
        view.addSubview(addBtn)
        view.addSubview(removeBtn)

        return view
    }

    private func buildSlotsView() -> NSView {
        let view = NSView()

        let dayLabel = NSTextField(labelWithString: "Day:")
        dayLabel.frame = NSRect(x: 12, y: 310, width: 32, height: 18)
        view.addSubview(dayLabel)

        dayPopup = NSPopUpButton(frame: NSRect(x: 48, y: 306, width: 150, height: 26))
        weekdays.forEach { dayPopup.addItem(withTitle: $0) }
        dayPopup.target = self
        dayPopup.action = #selector(dayChanged)
        view.addSubview(dayPopup)

        let hint = NSTextField(labelWithString: "Format: HH:MM-HH:MM  (e.g. 09:00-09:30)")
        hint.frame = NSRect(x: 212, y: 310, width: 280, height: 18)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        view.addSubview(hint)

        let sv = NSScrollView(frame: NSRect(x: 12, y: 50, width: 480, height: 252))
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder

        slotsTable = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("slot"))
        col.width = 460
        slotsTable.addTableColumn(col)
        slotsTable.headerView = nil
        slotsTable.dataSource = self
        slotsTable.delegate = self
        sv.documentView = slotsTable
        view.addSubview(sv)

        let addBtn = NSButton(title: "+", target: self, action: #selector(addSlot))
        addBtn.frame = NSRect(x: 12, y: 14, width: 32, height: 26)
        let removeBtn = NSButton(title: "−", target: self, action: #selector(removeSlot))
        removeBtn.frame = NSRect(x: 52, y: 14, width: 32, height: 26)
        view.addSubview(addBtn)
        view.addSubview(removeBtn)

        return view
    }

    // MARK: - Actions

    @objc private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Repository"
        panel.message = "Choose the root folder of a git repository"
        if panel.runModal() == .OK, let url = panel.url {
            if !repos.contains(url.path) {
                repos.append(url.path)
                reposTable.reloadData()
            }
        }
    }

    @objc private func removeRepo() {
        let row = reposTable.selectedRow
        guard row >= 0 else { return }
        repos.remove(at: row)
        reposTable.reloadData()
    }

    @objc private func dayChanged() { slotsTable.reloadData() }

    @objc private func addSlot() {
        let alert = NSAlert()
        alert.messageText = "Add Time Slot for \(selectedDay)"
        alert.informativeText = "Enter a time range:"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "09:00-09:30"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        slotsByDay[selectedDay, default: []].append(value)
        slotsByDay[selectedDay]?.sort()
        slotsTable.reloadData()
    }

    @objc private func removeSlot() {
        let row = slotsTable.selectedRow
        guard row >= 0 else { return }
        slotsByDay[selectedDay]?.remove(at: row)
        slotsTable.reloadData()
    }

    private func buildAdvancedView() -> NSView {
        let view = NSView()

        // Row 1: Default Duration
        let durLabel = NSTextField(labelWithString: "Default Quick Entry Duration (min):")
        durLabel.frame = NSRect(x: 12, y: 305, width: 240, height: 18)
        view.addSubview(durLabel)
        defaultDurationField = NSTextField(frame: NSRect(x: 260, y: 302, width: 60, height: 22))
        defaultDurationField.toolTip = "The duration (in minutes) pre-filled in the Quick Log dialog (⌘⇧L).\nYou can always change it before submitting an entry."
        view.addSubview(defaultDurationField)

        // Row 2: Block Minutes + Idle Threshold
        let blockLabel = NSTextField(labelWithString: "Block Minutes:")
        blockLabel.frame = NSRect(x: 12, y: 273, width: 110, height: 18)
        view.addSubview(blockLabel)
        blockMinutesField = NSTextField(frame: NSRect(x: 130, y: 270, width: 60, height: 22))
        blockMinutesField.toolTip = "The time-block size (in minutes) used for the Excel report grid.\nEach row in the report represents one block. Lower values give finer granularity.\nDefault: 15."
        view.addSubview(blockMinutesField)

        let idleLabel = NSTextField(labelWithString: "Idle Threshold (sec):")
        idleLabel.frame = NSRect(x: 260, y: 273, width: 150, height: 18)
        view.addSubview(idleLabel)
        idleThresholdField = NSTextField(frame: NSRect(x: 420, y: 270, width: 60, height: 22))
        idleThresholdField.toolTip = "Seconds of keyboard/mouse inactivity before an 'idle_start' event is logged.\nWhen you return, an 'idle_end' event is written. Idle time is excluded from the report.\nDefault: 300 (5 minutes)."
        view.addSubview(idleThresholdField)

        // Skip Apps
        let skipAppsLabel = NSTextField(labelWithString: "Skip Apps (one per line):")
        skipAppsLabel.frame = NSRect(x: 12, y: 242, width: 200, height: 18)
        view.addSubview(skipAppsLabel)
        let skipAppsScroll = NSScrollView(frame: NSRect(x: 12, y: 170, width: 488, height: 70))
        skipAppsView = NSTextView(frame: skipAppsScroll.contentView.bounds)
        skipAppsView.autoresizingMask = [.width, .height]
        skipAppsView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        skipAppsView.isRichText = false
        skipAppsView.toolTip = "Apps listed here (one per line) are excluded from the report description.\nActivity is still logged to JSONL, but the app name won't appear in the Excel report.\nExample: 'Finder' or '1Password'."
        skipAppsScroll.documentView = skipAppsView
        skipAppsScroll.hasVerticalScroller = true
        skipAppsScroll.borderType = .bezelBorder
        view.addSubview(skipAppsScroll)

        // Skip Safari Exact + Contains side by side
        let skipSELabel = NSTextField(labelWithString: "Skip Safari Exact (one per line):")
        skipSELabel.frame = NSRect(x: 12, y: 142, width: 230, height: 18)
        view.addSubview(skipSELabel)
        let skipSEScroll = NSScrollView(frame: NSRect(x: 12, y: 68, width: 236, height: 72))
        skipSafariExactView = NSTextView(frame: skipSEScroll.contentView.bounds)
        skipSafariExactView.autoresizingMask = [.width, .height]
        skipSafariExactView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        skipSafariExactView.isRichText = false
        skipSafariExactView.toolTip = "Safari page titles listed here (one per line) are hidden from the report description.\nThe match must be exact (case-sensitive). Events are still logged to JSONL.\nExample: 'Favorites' or 'Start Page'."
        skipSEScroll.documentView = skipSafariExactView
        skipSEScroll.hasVerticalScroller = true
        skipSEScroll.borderType = .bezelBorder
        view.addSubview(skipSEScroll)

        let skipSCLabel = NSTextField(labelWithString: "Skip Safari Contains (one per line):")
        skipSCLabel.frame = NSRect(x: 260, y: 142, width: 240, height: 18)
        view.addSubview(skipSCLabel)
        let skipSCScroll = NSScrollView(frame: NSRect(x: 260, y: 68, width: 240, height: 72))
        skipSafariContainsView = NSTextView(frame: skipSCScroll.contentView.bounds)
        skipSafariContainsView.autoresizingMask = [.width, .height]
        skipSafariContainsView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        skipSafariContainsView.isRichText = false
        skipSafariContainsView.toolTip = "Safari page titles containing any of these substrings (one per line) are hidden from the report.\nThe match is case-insensitive. Events are still recorded in the JSONL log file.\nExample: adding 'WhatsApp' hides WhatsApp Web from the report but it is still logged."
        skipSCScroll.documentView = skipSafariContainsView
        skipSCScroll.hasVerticalScroller = true
        skipSCScroll.borderType = .bezelBorder
        view.addSubview(skipSCScroll)

        return view
    }

    @objc private func saveClicked() {
        logDir = logDirField.stringValue.trimmingCharacters(in: .whitespaces)
        let defaultDur = Int(defaultDurationField.stringValue) ?? 60
        let blockMin = Int(blockMinutesField.stringValue) ?? 15
        let idleThresh = Int(idleThresholdField.stringValue) ?? 300
        let skipA = skipAppsView.string.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let skipSE = skipSafariExactView.string.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let skipSC = skipSafariContainsView.string.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let retDays = Int(retentionDaysField.stringValue) ?? 90
        let safariTracking = safariTrackingCheck.state == .on
        let safariURLs = logSafariURLsCheck.state == .on
        let domainOnly = domainOnlyCheck.state == .on
        let safariTime = safariTimeCheck.state == .on
        onSave?(logDir, repos, slotsByDay, defaultDur, blockMin, idleThresh, skipA, skipSE, skipSC, retDays, safariTracking, safariURLs, domainOnly, safariTime)
        window?.orderOut(nil)
    }

    @objc private func cancelClicked() { window?.orderOut(nil) }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === reposTable
            ? repos.count
            : (slotsByDay[selectedDay]?.count ?? 0)
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = tableView === reposTable
            ? repos[row]
            : (slotsByDay[selectedDay]?[row] ?? "")
        let cell = NSTextField(labelWithString: text)
        cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.lineBreakMode = .byTruncatingMiddle
        return cell
    }
}

// MARK: - QuickLogWindowController

public class QuickLogWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var tabView: NSTabView!

    // Today tab
    private var descriptionField: NSTextField!
    private var timeField: NSTextField!
    private var durationField: NSTextField!

    // Retro tab
    private var retroDescField: NSTextField!
    private var retroDatePicker: NSDatePicker!
    private var retroTimeField: NSTextField!
    private var retroDurationField: NSTextField!

    var onSave: ((_ description: String, _ time: String, _ durationMinutes: Int) -> Void)?
    var onRetroSave: ((_ description: String, _ date: Date, _ time: String, _ durationMinutes: Int) -> Void)?
    var defaultDuration: Int = 60

    func show() {
        if panel == nil { buildPanel() }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let now = fmt.string(from: Date())
        // Today tab defaults
        timeField.stringValue = now
        durationField.stringValue = "\(defaultDuration)"
        descriptionField.stringValue = ""
        // Retro tab defaults – yesterday, same time
        retroDatePicker.dateValue = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        retroTimeField.stringValue = "09:00"
        retroDurationField.stringValue = "\(defaultDuration)"
        retroDescField.stringValue = ""
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if tabView.indexOfTabViewItem(tabView.selectedTabViewItem!) == 0 {
            panel?.makeFirstResponder(descriptionField)
        } else {
            panel?.makeFirstResponder(retroDescField)
        }
    }

    private func buildPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "⚡ Quick Log"
        p.center()
        p.isFloatingPanel = true
        p.delegate = self

        tabView = NSTabView(frame: NSRect(x: 0, y: 50, width: 420, height: 170))

        let todayItem = NSTabViewItem(identifier: "today")
        todayItem.label = "Today"
        todayItem.view = buildTodayView()
        tabView.addTabViewItem(todayItem)

        let retroItem = NSTabViewItem(identifier: "retro")
        retroItem.label = "Retroactive"
        retroItem.view = buildRetroView()
        tabView.addTabViewItem(retroItem)

        p.contentView?.addSubview(tabView)

        let save = NSButton(title: "Log Entry", target: self, action: #selector(saveClicked))
        save.frame = NSRect(x: 310, y: 14, width: 90, height: 28)
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        p.contentView?.addSubview(save)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.frame = NSRect(x: 220, y: 14, width: 80, height: 28)
        cancel.keyEquivalent = "\u{1b}"
        p.contentView?.addSubview(cancel)

        self.panel = p
    }

    private func buildTodayView() -> NSView {
        let view = NSView()

        let descLabel = NSTextField(labelWithString: "What are you working on?")
        descLabel.frame = NSRect(x: 20, y: 104, width: 380, height: 18)
        descLabel.textColor = .secondaryLabelColor
        descLabel.font = .systemFont(ofSize: 11)
        view.addSubview(descLabel)

        descriptionField = NSTextField(frame: NSRect(x: 20, y: 78, width: 370, height: 22))
        descriptionField.placeholderString = "e.g. GPT4Gov file processing API review"
        view.addSubview(descriptionField)

        let timeLabel = NSTextField(labelWithString: "Time:")
        timeLabel.frame = NSRect(x: 20, y: 46, width: 40, height: 18)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.font = .systemFont(ofSize: 11)
        view.addSubview(timeLabel)

        timeField = NSTextField(frame: NSRect(x: 64, y: 44, width: 70, height: 22))
        timeField.placeholderString = "HH:MM"
        view.addSubview(timeField)

        let durLabel = NSTextField(labelWithString: "Duration (min):")
        durLabel.frame = NSRect(x: 154, y: 46, width: 110, height: 18)
        durLabel.textColor = .secondaryLabelColor
        durLabel.font = .systemFont(ofSize: 11)
        view.addSubview(durLabel)

        durationField = NSTextField(frame: NSRect(x: 268, y: 44, width: 60, height: 22))
        durationField.placeholderString = "60"
        view.addSubview(durationField)

        return view
    }

    private func buildRetroView() -> NSView {
        let view = NSView()

        let descLabel = NSTextField(labelWithString: "Description:")
        descLabel.frame = NSRect(x: 20, y: 104, width: 380, height: 18)
        descLabel.textColor = .secondaryLabelColor
        descLabel.font = .systemFont(ofSize: 11)
        view.addSubview(descLabel)

        retroDescField = NSTextField(frame: NSRect(x: 20, y: 78, width: 370, height: 22))
        retroDescField.placeholderString = "e.g. Code review session"
        view.addSubview(retroDescField)

        let dateLabel = NSTextField(labelWithString: "Date:")
        dateLabel.frame = NSRect(x: 20, y: 46, width: 40, height: 18)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.font = .systemFont(ofSize: 11)
        view.addSubview(dateLabel)

        retroDatePicker = NSDatePicker(frame: NSRect(x: 64, y: 42, width: 120, height: 24))
        retroDatePicker.datePickerStyle = .textFieldAndStepper
        retroDatePicker.datePickerElements = .yearMonthDay
        retroDatePicker.dateValue = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        view.addSubview(retroDatePicker)

        let timeLabel = NSTextField(labelWithString: "Time:")
        timeLabel.frame = NSRect(x: 198, y: 46, width: 40, height: 18)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.font = .systemFont(ofSize: 11)
        view.addSubview(timeLabel)

        retroTimeField = NSTextField(frame: NSRect(x: 240, y: 44, width: 60, height: 22))
        retroTimeField.placeholderString = "HH:MM"
        retroTimeField.stringValue = "09:00"
        view.addSubview(retroTimeField)

        let durLabel = NSTextField(labelWithString: "Min:")
        durLabel.frame = NSRect(x: 314, y: 46, width: 30, height: 18)
        durLabel.textColor = .secondaryLabelColor
        durLabel.font = .systemFont(ofSize: 11)
        view.addSubview(durLabel)

        retroDurationField = NSTextField(frame: NSRect(x: 348, y: 44, width: 50, height: 22))
        retroDurationField.placeholderString = "60"
        view.addSubview(retroDurationField)

        return view
    }

    @objc private func saveClicked() {
        let isRetro = tabView.indexOfTabViewItem(tabView.selectedTabViewItem!) == 1
        if isRetro {
            let desc = retroDescField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else {
                panel?.makeFirstResponder(retroDescField)
                return
            }
            let time = retroTimeField.stringValue.trimmingCharacters(in: .whitespaces)
            let duration = Int(retroDurationField.stringValue) ?? defaultDuration
            let date = retroDatePicker.dateValue
            onRetroSave?(desc, date, time, duration)
        } else {
            let desc = descriptionField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !desc.isEmpty else {
                panel?.makeFirstResponder(descriptionField)
                return
            }
            let time = timeField.stringValue.trimmingCharacters(in: .whitespaces)
            let duration = Int(durationField.stringValue) ?? defaultDuration
            onSave?(desc, time, duration)
        }
        panel?.close()
    }

    @objc private func cancelClicked() { panel?.close() }
}

// MARK: - ExportController

public class ExportController: NSObject {

    func run() {
        guard let python3 = findPython3() else {
            alert("Export Failed", "Python 3 not found.\nInstall via pyenv or Homebrew, then rebuild the app.")
            return
        }
        guard let scriptPath = Bundle.main.path(forResource: "report", ofType: "py") else {
            alert("Export Failed", "report.py not found in app bundle. Run 'make app' to rebuild.")
            return
        }

        let cal  = Calendar(identifier: .iso8601)
        let now  = Date()
        let week = cal.component(.weekOfYear, from: now)
        let year = cal.component(.yearForWeekOfYear, from: now)

        let panel = NSSavePanel()
        if #available(macOS 12, *) {
            panel.allowedContentTypes = [.spreadsheet]
        } else {
            panel.allowedFileTypes = ["xlsx"]
        }
        panel.nameFieldStringValue = String(format: "report_KW%02d_%d.xlsx", week, year)
        panel.message = "Save weekly report"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        // Show spinner in menu bar title while running
        let statusItem = (NSApp.delegate as? AppDelegate)?.statusItem
        statusItem?.button?.title = " ⏳"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python3)
        process.arguments = [scriptPath, String(year), String(week), "--xlsx", "--out", outURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    statusItem?.button?.title = ""
                    self.alert("Export Failed", error.localizedDescription)
                }
                return
            }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                statusItem?.button?.title = ""
                if process.terminationStatus == 0 {
                    NSWorkspace.shared.open(outURL)
                } else {
                    self.alert("Export Failed", output.isEmpty ? "Unknown error." : output)
                }
            }
        }
    }

    private func findPython3() -> String? {
        // Prefer the bundled venv inside the app bundle
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = "\(resourcePath)/venv/bin/python3"
            if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.pyenv/versions/3.10.13/bin/python3",
            "\(home)/.pyenv/shims/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }
}

// MARK: - AppDelegate

public class AppDelegate: NSObject, NSApplicationDelegate {
    var config = Config.load()
    var logger: Logger!
    var tracker: ActivityTracker!
    var safariTabMonitor: SafariTabMonitor!
    var vscodeProjectMonitor: VSCodeProjectMonitor!
    var idleMonitor: IdleMonitor!
    var statusItem: NSStatusItem!
    let preferencesController = PreferencesWindowController()
    let quickLogController = QuickLogWindowController()

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    let exportController = ExportController()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // First-launch consent
        if !(config.consentGiven ?? false) {
            let accepted = showConsentDialog()
            if !accepted {
                NSApplication.shared.terminate(nil)
                return
            }
            config.consentGiven = true
            config.save()
        }

        logger = Logger(config: config)
        logger.purgeOldLogs()

        // Restrict log directory permissions
        let fm = FileManager.default
        try? fm.createDirectory(atPath: config.logDirectory, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: config.logDirectory)

        setupMenuBar()
        startTracking()
        setupQuickLog()
        quickLogController.defaultDuration = config.defaultDurationMinutes ?? 60

        // Request Screen Recording permission after a short delay so menu bar renders first
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            logger.log([
                "event": "permissions",
                "screen_recording": CGPreflightScreenCaptureAccess()
            ])
        }
    }

    func setupQuickLog() {
        quickLogController.onSave = { [weak self] description, time, durationMinutes in
            guard let self else { return }
            self.logger.log([
                "event":            "manual_entry",
                "description":      description,
                "time":             time,
                "duration_minutes": durationMinutes
            ])
        }

        quickLogController.onRetroSave = { [weak self] description, date, time, durationMinutes in
            guard let self else { return }
            // Build a Date with the chosen date + time for the timestamp
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            let parts = time.split(separator: ":").compactMap { Int($0) }
            var dc = DateComponents()
            dc.year = comps.year; dc.month = comps.month; dc.day = comps.day
            dc.hour = parts.count > 0 ? parts[0] : 9
            dc.minute = parts.count > 1 ? parts[1] : 0
            let entryDate = cal.date(from: dc) ?? date
            self.logger.logToDate(entryDate, fields: [
                "event":            "manual_entry",
                "description":      description,
                "time":             time,
                "duration_minutes": durationMinutes
            ])
        }

        // Global hotkey: Cmd+Shift+L via Carbon RegisterEventHotKey.
        // This is a true system-wide hotkey — fires before other apps see the event,
        // requires no Accessibility permission, and works from any frontmost app.
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x574C5148) // 'WLQH'
        hotKeyID.id = 1
        RegisterEventHotKey(
            UInt32(kVK_ANSI_L),           // L key
            UInt32(cmdKey | shiftKey),    // Cmd+Shift
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let ptr = userData else { return OSStatus(eventNotHandledErr) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                DispatchQueue.main.async { delegate.quickLogController.show() }
                return noErr
            },
            1, &eventSpec, selfPtr, &hotKeyHandlerRef
        )
    }

    func startTracking() {
        setMenuBarIcon()
        tracker = ActivityTracker(logger: logger, config: config)
        safariTabMonitor = SafariTabMonitor(logger: logger, config: config)
        vscodeProjectMonitor = VSCodeProjectMonitor(logger: logger)
        idleMonitor = IdleMonitor(logger: logger, threshold: config.idleThresholdSeconds)
        safariTabMonitor.start()
        vscodeProjectMonitor.start()
        idleMonitor.start()
        logger.log(["event": "started", "config_path": Config.configPath])

        preferencesController.onSave = { [weak self] logDir, repos, slots, defaultDur, blockMin, idleThresh, skipApps, skipSafariExact, skipSafariContains, retDays, safariTracking, safariURLs, domainOnly, safariTime in
            guard let self else { return }
            // Persist top-level config
            self.config.logDirectory = logDir
            self.config.idleThresholdSeconds = TimeInterval(idleThresh)
            self.config.defaultDurationMinutes = defaultDur
            self.config.retentionDays = retDays
            self.config.safariTrackingEnabled = safariTracking
            self.config.logSafariURLs = safariURLs
            self.config.logSafariDomainOnly = domainOnly
            self.config.showSafariTimeInReport = safariTime
            self.config.save()
            // Update quick log default
            self.quickLogController.defaultDuration = defaultDur
            // Update idle monitor threshold
            self.idleMonitor.threshold = TimeInterval(idleThresh)
            // Persist report prefs
            var prefs = ReportPrefs.load()
            prefs.repositories = repos
            prefs.prefilledSlots = slots
            prefs.blockMinutes = blockMin
            prefs.skipApps = skipApps
            prefs.skipSafariExact = skipSafariExact
            prefs.skipSafariContains = skipSafariContains
            prefs.save()
        }
    }

    func setMenuBarIcon() {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont.boldSystemFont(ofSize: 12)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let str = NSAttributedString(string: "WL", attributes: attrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: (rect.width - sz.width) / 2, y: (rect.height - sz.height) / 2))
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.title = ""
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setMenuBarIcon()

        let menu = NSMenu()

        let quickLogItem = NSMenuItem(
            title: "⚡ Quick Log Entry",
            action: #selector(openQuickLog),
            keyEquivalent: "l"
        )
        quickLogItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(quickLogItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Export Report",
            action: #selector(exportReport),
            keyEquivalent: "e"
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Preferences",
            action: #selector(openPreferences),
            keyEquivalent: ","
        ))
        menu.addItem(NSMenuItem(
            title: "About WorkLogger Data",
            action: #selector(showDataInfo),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Export All My Data",
            action: #selector(exportAllData),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Delete All My Data",
            action: #selector(deleteAllData),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem.separator())

        let launchItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        statusItem.menu = menu
    }

    // MARK: - Launch at Login

    private var launchAgentPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/com.worklogger.app.plist"
    }

    func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath)
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if isLaunchAtLoginEnabled() {
            try? FileManager.default.removeItem(atPath: launchAgentPath)
            sender.state = .off
        } else {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.worklogger.app</string>
                <key>ProgramArguments</key>
                <array>
                    <string>open</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            let dir = (launchAgentPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? plist.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
            sender.state = .on
        }
    }

    @objc func openQuickLog() { quickLogController.show() }

    @objc func exportReport() { exportController.run() }

    /// Art. 15 — Right of access: export all personal data as a zip of JSONL files + config.
    @objc func exportAllData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "WorkLogger-data-export.zip"
        panel.message = "Export all WorkLogger data (GDPR Art. 15 — Right of Access)"
        if #available(macOS 12, *) {
            panel.allowedContentTypes = [.zip]
        } else {
            panel.allowedFileTypes = ["zip"]
        }
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let outURL = panel.url else { return }

        let fm = FileManager.default
        let tmpDir = NSTemporaryDirectory() + "WorkLogger-export-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        // Copy all JSONL files
        if let files = try? fm.contentsOfDirectory(atPath: config.logDirectory) {
            for file in files where file.hasSuffix(".jsonl") {
                try? fm.copyItem(atPath: "\(config.logDirectory)/\(file)",
                                 toPath: "\(tmpDir)/\(file)")
            }
        }
        // Copy config
        if fm.fileExists(atPath: Config.userConfigPath) {
            try? fm.copyItem(atPath: Config.userConfigPath,
                             toPath: "\(tmpDir)/config.json")
        }

        // Create zip using ditto (macOS built-in, preserves UTF-8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", tmpDir, outURL.path]
        try? process.run()
        process.waitUntilExit()
        try? fm.removeItem(atPath: tmpDir)

        if process.terminationStatus == 0 {
            NSWorkspace.shared.activateFileViewerSelecting([outURL])
        } else {
            let a = NSAlert()
            a.messageText = "Export Failed"
            a.informativeText = "Could not create zip archive."
            a.runModal()
        }
    }

    /// Art. 17 — Right to erasure: delete all personal data.
    @objc func deleteAllData() {
        let a = NSAlert()
        a.messageText = "Delete All WorkLogger Data?"
        a.informativeText = """
        This will permanently delete:
        • All JSONL log files in \(config.logDirectory)
        • Your configuration at ~/Library/Application Support/WorkLogger/

        This action cannot be undone. WorkLogger will quit after deletion.
        """
        a.alertStyle = .critical
        a.addButton(withTitle: "Delete Everything")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }

        // Second confirmation
        let b = NSAlert()
        b.messageText = "Are you sure?"
        b.informativeText = "All activity logs and settings will be permanently erased."
        b.alertStyle = .critical
        b.addButton(withTitle: "Yes, Delete All")
        b.addButton(withTitle: "Cancel")
        guard b.runModal() == .alertFirstButtonReturn else { return }

        let fm = FileManager.default
        // Delete all JSONL files
        if let files = try? fm.contentsOfDirectory(atPath: config.logDirectory) {
            for file in files where file.hasSuffix(".jsonl") {
                try? fm.removeItem(atPath: "\(config.logDirectory)/\(file)")
            }
        }
        // Delete config directory
        let configDir = (Config.userConfigPath as NSString).deletingLastPathComponent
        try? fm.removeItem(atPath: configDir)
        // Remove LaunchAgent if present
        if fm.fileExists(atPath: launchAgentPath) {
            try? fm.removeItem(atPath: launchAgentPath)
        }

        let c = NSAlert()
        c.messageText = "Data Deleted"
        c.informativeText = "All WorkLogger data has been erased. The app will now quit."
        c.runModal()
        NSApplication.shared.terminate(nil)
    }

    @objc func showDataInfo() {
        let retention = config.retentionDays ?? 90
        let safariOn = config.safariTrackingEnabled ?? true
        let urlMode = (config.logSafariDomainOnly ?? true) ? "domain only" :
                      (config.logSafariURLs ?? true) ? "full (query stripped)" : "disabled"
        let a = NSAlert()
        a.messageText = "WorkLogger — Data Collection"
        a.informativeText = """
        WorkLogger tracks your activity locally on this Mac. No data is sent to any server.

        What is collected:
        • Active application name and window title
        • VS Code project name
        \(safariOn ? "• Safari tab names and URLs (\(urlMode))" : "• Safari tracking: disabled")
        • Idle periods, screen lock/unlock, sleep/wake
        • Manual entries you create
        • Git commits from configured repos (report only)

        Where data is stored:
        • Logs: \(config.logDirectory) (owner-only, chmod 600)
        • Config: ~/Library/Application Support/WorkLogger/

        Retention: \(retention) days (older logs are deleted on launch)

        You can delete your data at any time by removing the log files.
        """
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func showConsentDialog() -> Bool {
        let a = NSAlert()
        a.messageText = "WorkLogger — Data Collection Consent"
        a.informativeText = """
        WorkLogger will track the following activity on this Mac:

        • Active application names and window titles
        • VS Code project names
        • Safari tab names and URLs (domain only by default)
        • Idle periods, screen lock/unlock, sleep/wake events

        All data is stored locally in JSONL files on your disk. \
        No data is sent to any external server. \
        Logs are automatically deleted after \(config.retentionDays ?? 90) days.

        You can change these settings or disable Safari tracking at any time in Preferences → Advanced.

        Do you agree to start logging?
        """
        a.addButton(withTitle: "I Agree")
        a.addButton(withTitle: "Quit")
        return a.runModal() == .alertFirstButtonReturn
    }

    @objc func openPreferences() {
        let prefs = ReportPrefs.load()
        preferencesController.show(
            logDir: config.logDirectory, repos: prefs.repositories, slots: prefs.prefilledSlots,
            defaultDuration: config.defaultDurationMinutes ?? 60,
            blockMinutes: prefs.blockMinutes, idleThreshold: Int(config.idleThresholdSeconds),
            skipApps: prefs.skipApps, skipSafariExact: prefs.skipSafariExact,
            skipSafariContains: prefs.skipSafariContains,
            retentionDays: config.retentionDays ?? 90,
            safariTrackingEnabled: config.safariTrackingEnabled ?? true,
            logSafariURLs: config.logSafariURLs ?? true,
            logSafariDomainOnly: config.logSafariDomainOnly ?? true,
            showSafariTime: config.showSafariTimeInReport ?? false)
    }

    @objc func quit() { NSApplication.shared.terminate(nil) }
}
