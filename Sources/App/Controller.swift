// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import IOKit.pwr_mgt
import os
import ServiceManagement
import Text
import Pace
import Feed
import Transcripts
import MacStats
import UI

/// The keys the popover handles, by their virtual key code.
enum KeyCode {
    static let escape: UInt16 = 53
    static let tab: UInt16 = 48
}

/// The thresholds of the nudges and of the Mac warning.
enum Rules {
    static let weeklyNudgeAt = 80.0                           // percent of the weekly window
    static let fiveHourNudgeLead: TimeInterval = 15 * 60      // before the 5h window resets
    static let hogSustained: TimeInterval = 60                // one process over the hog threshold this long
    static let pressureWarn = 2                               // kern.memorystatus_vm_pressure_level: 2 warn, 4 critical
    static let keepAwakeGrace: TimeInterval = 10 * 60         // a session works while its figures moved this recently
    static let restoreSettle: TimeInterval = 15               // after launch, before the restart notification is posted
    static let restoreNetworkWait: TimeInterval = 120         // the longest the restore waits for a network
    static let endedSettle: TimeInterval = 3                  // after a session's process is gone, before its window is checked
}

/// The main actor state: the status item, the popover, the timers, and the readers it asks.
@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let feed: FeedReader
    var hook: HookSet
    var folders: [URL]
    let store: TranscriptStore
    let sampler = MacSampler()
    let notifier = Notifier()

    var feedState = FeedState()
    var hookStatus = HookStatus(installed: false, previousCommand: nil)
    var hookError: String? = nil
    var removeScriptError: String? = nil   // remove.sh could not be written, shown under the status line row
    var settingsModified: [Date?] = []   // the settings.json files are read again only when one of these moves
    let log = Logger(subsystem: Paths.bundleId, category: "hook")
    let restoreLog = Logger(subsystem: Paths.bundleId, category: "restore")
    var tokens: TokenSummary? = nil
    var transcriptsRootsExist = true
    var transcriptsError: String? = nil
    var mac: MacSample? = nil
    var weeks = WeekRecords()
    var hogPid: Int32? = nil
    var hogSince: Date? = nil
    var tab = 0
    var section = 0
    var lastItem: ItemState? = nil
    var lastScreen: Screen? = nil
    var transcriptsVersion = -1
    var tokensDay: Date? = nil
    var working = WorkingSessions()
    var awakeAssertion: IOPMAssertionID? = nil   // held only while the setting is on and a session works, or is open with the second switch
    var awake: KeepAwake? = nil                  // why it is held
    var login = LoginItem.off                    // the system's status, read when the popover opens and while Settings shows
    var loginError: String? = nil                // the last register or unregister error
    var restore: RestoreRecord? = nil            // the sessions open now, kept on disk only while the setting is on
    var restoreSaved: [String] = []              // the sessions last written (id, name, options), so the file is written only when they change
    var pendingReopen: [RestoreRecord.Entry] = []   // the sessions the restart notification offers
    var sessionNames: [String: String] = [:]   // the open sessions' names, read at each scan, for the Open sessions rows
    var launches: [Int32: (id: String, launch: RestoreRecord.Launch)] = [:]   // by process: how each running session was started
    var sessionWatch = SessionWatch()           // the running sessions by process, to tell when one ends
    var endedEntries: [String: RestoreRecord.Entry] = [:]   // the sessions an end notification offers, by notification id

    var item: NSStatusItem!
    let popover = NSPopover()
    let lineView = LineView()
    var keyMonitor: Any?
    var feedTimer: DispatchSourceTimer?
    var macTimer: DispatchSourceTimer?
    var transcriptTimer: DispatchSourceTimer?
    var dirSource: DispatchSourceFileSystemObject?
    var dirFD: Int32 = -1
    let queue = DispatchQueue(label: "dev.tokenpanda.timers", qos: .utility)
    var transcriptsBusy = false

    override init() {
        feed = FeedReader(dataDir: Paths.dataDir)
        folders = ConfigFolders.find()
        hook = HookSet(folders: folders, dataDir: Paths.dataDir)
        // the transcripts of every settings folder found, besides the usual places
        var roots = TranscriptLocator.roots()
        for f in ConfigFolders.transcriptFolders() { let r = f.appendingPathComponent("projects", isDirectory: true); if !roots.contains(r) { roots.append(r) } }
        store = TranscriptStore(roots: roots)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        weeks = WeekRecords.load(from: Paths.weeksFile)
        try? FileManager.default.createDirectory(at: feed.sessionsDir, withIntermediateDirectories: true)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityLabel("tokenpanda, Claude usage")

        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        // the panel follows the Mac's appearance: the glass and its tint change with it, the lines redraw themselves
        let root = Ground()
        let tint = root.tint
        root.addSubview(tint)
        root.addSubview(lineView)
        // pinned to the root on all four edges: the popover shrinks and grows while open as lines come and go,
        // and an autoresized view in the non flipped root kept its old height and slid up out of the frame
        for v in [tint, lineView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                v.topAnchor.constraint(equalTo: root.topAnchor), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        let vc = NSViewController(); vc.view = root
        popover.contentViewController = vc
        lineView.onAction = { [weak self] a in self?.perform(a) }

        readHookStatus()
        // an entry installed by an earlier version gets its remove script now, so brew's zap needs no click first
        removeScriptError = hook.writeRemoveScript()
        notifier.onReopen = { [weak self] in self?.reopen() }
        notifier.onReopenEnded = { [weak self] id in self?.reopenEnded(id) }
        offerRestore(now: Date())   // before the first scan, which writes this boot's record over the last one
        notifier.refreshState()   // no prompt at launch: the first nudge that is due asks
        startFeedWatch()
        startTimers(open: false)
        Task { await refreshFeed(); await refreshTranscripts(); await sampleMac(full: false) }

        #if DEBUG
        // debug flag: after 45 s, open the popover and write the three live tabs to PNG (for the CPU measurement)
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--live-snapshot"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            if args.contains("--snapshot-light") { LineView.lightOverride = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(45))
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if !popover.isShown { togglePopover() }
                try? await Task.sleep(for: .seconds(5))   // one full sample with the popover open
                for t in 0..<3 {
                    var i = input; i.tab = t
                    try? SnapshotWriter.writeScreen(ScreenBuilder.screen(i), to: dir.appendingPathComponent("live-tab\(t).png"))
                }
                try? SnapshotWriter.writeItem(ScreenBuilder.item(input), to: dir.appendingPathComponent("live-item.png"))
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        feedTimer?.cancel(); macTimer?.cancel(); transcriptTimer?.cancel(); dirSource?.cancel()
        releaseAwake()
    }

    // MARK: timers

    func timer(_ seconds: Double, _ body: @escaping @Sendable () -> Void) -> DispatchSourceTimer {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + seconds, repeating: seconds, leeway: .milliseconds(Int(seconds * 100)))
        t.setEventHandler(handler: body)
        t.resume()
        return t
    }

    func startTimers(open: Bool) {
        macTimer?.cancel(); transcriptTimer?.cancel(); feedTimer?.cancel()
        feedTimer = timer(5) { Task { @MainActor in await self.refreshFeed() } }
        macTimer = timer(open ? 2 : 10) { Task { @MainActor in await self.sampleMac(full: open) } }
        transcriptTimer = timer(open ? 10 : 300) { Task { @MainActor in await self.refreshTranscripts() } }
    }

    func stopFeedWatch() {
        dirSource?.cancel()   // the cancel handler closes its descriptor
        dirSource = nil
        dirFD = -1
    }

    func startFeedWatch() {
        stopFeedWatch()
        dirFD = open(feed.sessionsDir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write], queue: queue)
        src.setEventHandler { Task { @MainActor in await self.refreshFeed() } }
        src.setCancelHandler { [fd = dirFD] in close(fd) }
        src.resume()
        dirSource = src
    }

    // MARK: readers

    func refreshFeed() async {
        let now = Date()
        feedState = await feed.scan(now: now)
        working.apply(feedState.sessions)
        sessionNames = Dictionary(LiveSession.read(settingsFolders: folders).compactMap { s in s.name.map { (s.sessionId, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        updateAwake(now: now)
        recordSessions(now: now)
        refreshFolders()
        if hook.settingsModified() != settingsModified { readHookStatus() }
        if let l = feedState.limits, let w = l.windows["seven_day"] {
            var ws = weeks
            ws.apply(LimitWindow(key: "seven_day", usedPercentage: w.used, resetsAt: w.resetsAt), at: l.asOf)
            if ws != weeks { weeks = ws; weeks.save(to: Paths.weeksFile) }
        }
        checkNudges(now: now)
        render()
    }

    func refreshTranscripts() async {
        guard !transcriptsBusy else { return }
        transcriptsBusy = true
        let now = Date()
        let result = await store.refresh(now: now, onlyIfChanged: true)
        transcriptsBusy = false
        transcriptsRootsExist = result.rootsExist
        transcriptsError = result.error
        // the aggregate moves only with new records or a new day (the "today" window)
        let day = Calendar.current.startOfDay(for: now)
        if result.version != transcriptsVersion || tokensDay != day || tokens == nil {
            transcriptsVersion = result.version
            tokensDay = day
            let records = result.records
            tokens = await Task.detached(priority: .utility) { Aggregator.summarize(records, now: now) }.value
        }
        render()
    }

    /// A settings folder made since launch (a second account with CLAUDE_CONFIG_DIR) joins the set; Install then offers it.
    func refreshFolders() {
        let now = ConfigFolders.find()
        guard now != folders else { return }
        folders = now
        hook = HookSet(folders: now, dataDir: Paths.dataDir)
        readHookStatus()
    }

    /// settings.json, the one statusLine key, read at launch and again only when the file's modification time moves.
    func readHookStatus() {
        settingsModified = hook.settingsModified()
        hookStatus = hook.status()
    }

    func sampleMac(full: Bool) async {
        let s = await sampler.sample(full: full)
        mac = s
        // the hog is timed by the clock, so the rule holds at the 2 s and the 10 s cadence alike
        if let h = s.hogPid {
            if h != hogPid { hogPid = h; hogSince = Date() }
        } else {
            hogPid = nil; hogSince = nil
        }
        render()
    }

    var warning: Bool {
        guard let m = mac else { return false }
        let hog = hogSince.map { Date().timeIntervalSince($0) >= Rules.hogSustained } ?? false
        return m.pressureLevel >= Rules.pressureWarn || hog
    }

    // MARK: keep awake

    /// One power assertion against idle system sleep while the setting is on and a session works, or with the second switch
    /// while a session is open; the display may still sleep. Never a second one while one is held: when the reason changes,
    /// the held one is released before the one with the new name is made. Released as soon as nothing holds the Mac awake.
    func updateAwake(now: Date) {
        let next = KeepAwake.decide(on: Settings.bool(Settings.keepAwake), whileOpen: Settings.bool(Settings.keepAwakeWhileOpen),
                                    working: working.count(now: now, grace: Rules.keepAwakeGrace), open: feedState.sessions.count)
        guard let next else { releaseAwake(); return }
        let held = awake.map { Self.assertionName($0) }
        if awakeAssertion != nil, held == Self.assertionName(next) { awake = next; return }
        releaseAwake()
        var id = IOPMAssertionID(0)
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            Self.assertionName(next) as CFString, &id)
        if r == kIOReturnSuccess { awakeAssertion = id; awake = next }
    }

    static func assertionName(_ a: KeepAwake) -> String {
        switch a {
        case .working: return "tokenpanda: Claude Code is working"
        case .open: return "tokenpanda: a Claude Code session is open"
        }
    }

    func releaseAwake() {
        if let id = awakeAssertion { IOPMAssertionRelease(id); awakeAssertion = nil }
        awake = nil
    }

    // MARK: open at login

    /// The truth is the system: the user can remove the item in System Settings, General, Login Items at any time,
    /// so nothing of it is stored and the status is read again whenever the row is shown.
    static func loginStatus() -> LoginItem { ScreenBuilder.loginItem(SMAppService.mainApp.status) }

    /// register() on, unregister() off, through the system's login item service. Returns the error as the row says it.
    static func setLogin(on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Could not turn it \(on ? "on" : "off"): " + error.localizedDescription
        }
    }

    /// The row's click: while the system waits for the user's OK, it opens Login Items; otherwise it flips the system's state.
    func clickLogin() {
        login = Self.loginStatus()
        if login == .needsApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        loginError = Self.setLogin(on: login == .off)
        login = Self.loginStatus()
    }

    // MARK: session restore

    /// The time this Mac booted, from kern.boottime.
    static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }

    /// At launch: when the record was written before this boot, one notification offers the sessions that were open then.
    func offerRestore(now: Date) {
        guard Settings.bool(Settings.restoreSessions) else { return }
        let record = RestoreRecord.load(from: Paths.restoreFile)
        guard let boot = Self.bootTime(), let lost = record?.lost(bootTime: boot, now: now), !lost.isEmpty else { return }
        pendingReopen = lost
        restoreLog.info("restore: \(lost.count, privacy: .public) sessions were open before this boot")
        let n = lost.count
        let names = SessionNames.list(lost.map(\.label), named: Set(lost.compactMap(\.name)))
        Task { @MainActor in
            // right after login the notification centre may not show anything yet: wait a little, and for the network,
            // which Remote Control needs when the sessions start
            try? await Task.sleep(for: .seconds(Rules.restoreSettle))
            await Self.waitForNetwork(timeout: Rules.restoreNetworkWait)
            await notifier.authorize()
            restoreLog.info("restore: posting the offer")
            notifier.post(title: "\(n) Claude Code session\(n == 1 ? " was" : "s were") open before the restart",
                          body: "\(names). Reopen opens \(n == 1 ? "it" : "each") in Terminal as \(n == 1 ? "it was" : "they were") started.", id: "reopen-\(Int(boot.timeIntervalSince1970))",
                          category: Notifier.reopenCategory)
        }
    }

    /// Whether an interface other than loopback is up, running and has an address, read with getifaddrs.
    /// It reads the interfaces' state and opens no connection.
    static func hasNetworkAddress() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return false }
        defer { freeifaddrs(list) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0, let addr = p.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            if family == AF_INET {
                // a self assigned address (169.254.x.x) means no network answered
                let v4 = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if v4 >> 16 != 0xA9FE { return true }
                continue
            }
            if family == AF_INET6 {
                // a link local address (fe80::) alone does not reach anything
                let v6 = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                if !(v6.__u6_addr.__u6_addr8.0 == 0xfe && v6.__u6_addr.__u6_addr8.1 & 0xc0 == 0x80) { return true }
            }
        }
        return false
    }

    /// Returns once the Mac has a network address, checked every 2 s, or after the timeout.
    static func waitForNetwork(timeout: TimeInterval) async {
        let end = Date().addingTimeInterval(timeout)
        while !hasNetworkAddress(), Date() < end { try? await Task.sleep(for: .seconds(2)) }
    }

    /// Each scan while the setting is on: the open sessions go into the record, written only when the set of ids changes.
    func recordSessions(now: Date) {
        guard Settings.bool(Settings.restoreSessions) else { return }
        let live = LiveSession.read(settingsFolders: folders)
        readLaunches(live)
        var byId: [String: RestoreRecord.Launch] = [:]
        for (_, v) in launches { byId[v.id] = v.launch }
        var r = restore ?? RestoreRecord(lastScan: now)
        r.apply(feedState.sessions, launches: byId, now: now)
        restore = r
        // written when a session comes or goes, or a name or the options change
        let key = r.entries.map { [$0.id, $0.name ?? "", ($0.options ?? []).joined(separator: "\u{1}")].joined(separator: "\u{2}") }
        if key != restoreSaved { restoreSaved = key; r.save(to: Paths.restoreFile) }
        watchEnds(live, now: now)
    }

    /// Reads the start options of each session process not seen before, once per process; the name is read every time,
    /// as /rename changes it.
    func readLaunches(_ live: [LiveSession]) {
        var next: [Int32: (id: String, launch: RestoreRecord.Launch)] = [:]
        for s in live {
            var options = launches[s.pid]?.launch.options
            if launches[s.pid]?.id != s.sessionId || options == nil {
                options = ProcessTable.arguments(of: s.pid).flatMap { LaunchOptions.kept(fromArguments: $0) }
            }
            next[s.pid] = (s.sessionId, RestoreRecord.Launch(name: s.name, options: options))
        }
        launches = next
    }

    /// A session that ended while its window stays open gets one notification with its name and a Reopen button.
    func watchEnds(_ live: [LiveSession], now: Date) {
        let gone = sessionWatch.apply(live) { ProcessTable.parent(of: $0) }
        for w in gone {
            guard let parent = w.parent else { continue }
            let entry = restore?.entries.first { $0.id == w.sessionId }
                ?? w.folder.map { RestoreRecord.Entry(id: w.sessionId, folder: $0, transcript: nil, lastSeen: now, name: w.name) }
            guard var e = entry else { continue }
            if let n = w.name { e.name = n }
            Task { @MainActor in
                // a closed window takes its shell with it a moment later; a shutdown closes them all
                try? await Task.sleep(for: .seconds(Rules.endedSettle))
                guard ProcessTable.isRunning(parent),
                      !LiveSession.read(settingsFolders: folders).contains(where: { $0.sessionId == e.id }) else { return }
                let id = "ended-\(e.id)-\(Int(now.timeIntervalSince1970))"
                endedEntries[id] = e
                restoreLog.info("restore: a session ended while its window stays open")
                let at = now.formatted(date: .omitted, time: .shortened)
                notifier.postAsking(title: "\(e.label) ended", body: "At \(at). Its Terminal window is still open. Reopen starts it again as it was started.",
                                    id: id, category: Notifier.endedCategory)
            }
        }
    }

    /// Reopen on an end notification: that one session, as it was started.
    func reopenEnded(_ notificationId: String) {
        guard let e = endedEntries.removeValue(forKey: notificationId) else { return }
        guard !LiveSession.read(settingsFolders: folders).contains(where: { $0.sessionId == e.id }) else { return }
        openInTerminal([e])
    }

    /// Reopen: one Terminal file per session in a private folder, opened through Launch Services so no Automation
    /// permission is needed. Each file deletes itself when Terminal runs it.
    func reopen() {
        // a session already open again, from a Terminal window or an earlier click, is not opened a second time
        let openNow = Set(feedState.sessions.map(\.snapshot.sessionId)).union(LiveSession.read(settingsFolders: folders).map(\.sessionId))
        let entries = pendingReopen.filter { !openNow.contains($0.id) }
        pendingReopen = []
        restoreLog.info("reopen: \(entries.count, privacy: .public) of the offered sessions, the others are open already")
        guard !entries.isEmpty else { return }
        openInTerminal(entries)
    }

    /// One Terminal file per session, each starting the session with its name and options.
    func openInTerminal(_ entries: [RestoreRecord.Entry]) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("tokenpanda-reopen-" + UUID().uuidString, isDirectory: true)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return }
        var files: [URL] = []
        for e in entries {
            guard let text = Reopen.script(id: e.id, folder: e.folder, name: e.name, options: e.options,
                                           remoteControl: Reopen.hadRemoteControl(transcript: e.transcript)) else { continue }
            let url = dir.appendingPathComponent(e.id + ".command")
            guard fm.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else { continue }
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            files.append(url)
        }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard !files.isEmpty else { return }
        Task { @MainActor in
            // Remote Control connects once, when a session starts, so the sessions wait for the network; without one they still open
            await Self.waitForNetwork(timeout: Rules.restoreNetworkWait)
            NSWorkspace.shared.open(files, withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    // MARK: nudges

    func checkNudges(now: Date) {
        guard Settings.bool(Settings.nudges), let l = feedState.limits, !OpenSessionsRule.isStale(asOf: l.asOf, now: now) else { return }
        if let w = l.active("seven_day"), let length = WindowKind.length(forKey: "seven_day"), w.used >= Rules.weeklyNudgeAt, now < w.resetsAt,
           Settings.nudged(Settings.nudgedWeeklyWindow) != w.resetsAt.timeIntervalSince1970 {
            let start = w.resetsAt.addingTimeInterval(-length)
            let body = PaceModel.reading(used: w.used, start: start, reset: w.resetsAt, now: now).map { PaceModel.nudgeBody($0) } ?? ""
            notifier.postAsking(title: "Weekly at \(Int(w.used.rounded()))%", body: body, id: "weekly-\(Int(w.resetsAt.timeIntervalSince1970))")
            Settings.setNudged(Settings.nudgedWeeklyWindow, w.resetsAt.timeIntervalSince1970)
        }
        if let f = l.active("five_hour"), now >= f.resetsAt.addingTimeInterval(-Rules.fiveHourNudgeLead), now < f.resetsAt,
           Settings.nudged(Settings.nudgedFiveHourWindow) != f.resetsAt.timeIntervalSince1970 {
            notifier.postAsking(title: "5h window ends in 15 min", body: "\(Int(f.used.rounded()))% used.", id: "five-\(Int(f.resetsAt.timeIntervalSince1970))")
            Settings.setNudged(Settings.nudgedFiveHourWindow, f.resetsAt.timeIntervalSince1970)
        }
    }

    // MARK: rendering

    var input: LiveInput {
        var i = LiveInput(feed: feedState, hook: hookStatus, tokens: tokens, transcriptsRootsExist: transcriptsRootsExist, transcriptsError: transcriptsError,
                  mac: mac, weeks: weeks, macInBar: Settings.bool(Settings.macFiguresInBar), nudges: Settings.bool(Settings.nudges),
                  listPrice: Settings.bool(Settings.listPriceEquivalent), nudgeNote: notifier.noteForSettings, hookError: hookError,
                  keepAwake: Settings.bool(Settings.keepAwake),
                  keepAwakeWhileOpen: Settings.bool(Settings.keepAwakeWhileOpen), awake: awake, login: login, loginError: loginError,
                  restoreSessions: Settings.bool(Settings.restoreSessions), warn: warning, tab: tab, section: section, now: Date(),
                  version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        i.sessionNames = sessionNames
        i.removeScriptError = removeScriptError
        return i
    }

    func render() {
        if popover.isShown, tab == 2 { login = Self.loginStatus() }
        let i = input
        let st = ScreenBuilder.item(i)
        if st != lastItem {
            lastItem = st
            item.button?.image = ItemImage.make(st)
            item.button?.alphaValue = st.stale ? 0.5 : 1
            item.button?.setAccessibilityLabel("tokenpanda, " + st.label)   // VoiceOver names the app first, then the figures
        }
        if popover.isShown {
            let screen = ScreenBuilder.screen(i)
            guard screen != lastScreen else { return }
            lastScreen = screen
            let lines = Grammar.popover(screen)
            lineView.lines = lines
            let size = NSSize(width: LineView.width, height: lineView.contentHeight)
            if popover.contentSize != size { popover.contentSize = size }
        }
    }

    func perform(_ a: Action) {
        switch a {
        case .tab(let t): tab = t
        case .section(let s): section = s
        case .toggle(let key) where key == Grammar.loginKey: clickLogin()
        case .toggle(let key):
            Settings.toggle(key)
            if key == Settings.nudges, Settings.bool(key) { notifier.requestIfNeeded() }
            if key == Settings.keepAwake || key == Settings.keepAwakeWhileOpen { updateAwake(now: Date()) }
            if key == Settings.restoreSessions {
                if Settings.bool(key) { notifier.requestIfNeeded(); recordSessions(now: Date()) }
                else { restore = nil; restoreSaved = []; launches = [:]; sessionWatch = SessionWatch(); try? FileManager.default.removeItem(at: Paths.restoreFile) }
            }
        case .install:
            do {
                let done = try hook.install(previousFallback: { Settings.defaults.string(forKey: Settings.previousCommandKey($0.id)) })
                hookError = nil
                for (h, st) in done {
                    if let p = st.previousCommand { Settings.defaults.set(p, forKey: Settings.previousCommandKey(h.id)) }
                    if let r = st.slowerRefresh { Settings.defaults.set(r, forKey: Settings.previousRefreshKey(h.id)) }
                }
                startFeedWatch()
            } catch {
                hookFailed("install", error)
            }
            removeScriptError = hook.writeRemoveScript()
            readHookStatus()
        case .uninstall:
            do {
                try Self.removeEverywhere(hook)
                hookError = nil
                stopFeedWatch()
            } catch {
                hookFailed("remove", error)
            }
            removeScriptError = hook.writeRemoveScript()
            readHookStatus()
        case .quit: NSApp.terminate(nil)
        }
        render()
    }

    /// Remove in every settings folder, with the chained command and interval the app kept as the fallback for a lost backup.
    /// Also what `tokenpanda --remove-status-line` runs, which the cask's zap calls before it trashes the data folder.
    static func removeEverywhere(_ hook: HookSet) throws {
        try hook.uninstall(previousCommand: { Settings.defaults.string(forKey: Settings.previousCommandKey($0.id)) },
                           previousRefresh: { Settings.defaults.object(forKey: Settings.previousRefreshKey($0.id)) as? Double })
        for h in hook.hooks {
            Settings.defaults.removeObject(forKey: Settings.previousCommandKey(h.id))
            Settings.defaults.removeObject(forKey: Settings.previousRefreshKey(h.id))
        }
    }

    func hookFailed(_ what: String, _ error: Error) {
        let message = (error as? HookError)?.description ?? error.localizedDescription
        hookError = "Could not \(what) the entry: " + message
        log.error("status line \(what, privacy: .public) failed: \(message, privacy: .private)")
    }

    // MARK: popover

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        login = Self.loginStatus()
        let screen = ScreenBuilder.screen(input)
        lastScreen = screen
        lineView.lines = Grammar.popover(screen)
        popover.contentSize = NSSize(width: LineView.width, height: lineView.contentHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(lineView)
        startTimers(open: true)
        Task { await sampleMac(full: true); await refreshTranscripts() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastScreen = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        startTimers(open: false)
    }

    func handleKey(_ e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) {
            if e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return true }
            return false
        }
        switch e.keyCode {
        case KeyCode.escape: popover.performClose(nil); return true
        case KeyCode.tab:
            // Tab switches the tab and puts the focus on it, so the arrows go on from there
            tab = (tab + (e.modifierFlags.contains(.shift) ? 2 : 1)) % 3; render()
            lineView.focus(on: .tab(tab), visible: true)
            return true
        default: break
        }
        if let k = LineView.focusKey(forKeyCode: e.keyCode), lineView.moveFocus(k) { return true }
        if tab == 0, let c = e.charactersIgnoringModifiers, let i = ["m", "p", "s"].firstIndex(of: c) { section = i; render(); return true }
        return false
    }
}

/// The popover's glass: the HUD material and the dark tint in dark mode, the popover material and the light tint in
/// light mode. Switches live when the Mac's appearance changes.
final class Ground: NSVisualEffectView {
    let tint = NSView()
    init() {
        super.init(frame: .zero)
        blendingMode = .behindWindow
        state = .active
        tint.wantsLayer = true
        apply()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply()
    }
    func apply() {
        let light = effectiveAppearance.isLight
        material = light ? .popover : .hudWindow
        tint.layer?.backgroundColor = Tokens.tint.ink(light).cgColor
    }
}
