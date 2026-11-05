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
    let nudges = NudgeLedger(mark: { Settings.nudged($0) }, setMark: { Settings.setNudged($0, $1) })   // the rule: NudgeRules

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
    let scroll = NSScrollView()
    var keyMonitor: Any?
    var feedTimer: DispatchSourceTimer?
    var macTimer: DispatchSourceTimer?
    var transcriptTimer: DispatchSourceTimer?
    var feedWatch: FolderWatch?                 // write events in the sessions folder, kept through a delete of the folder
    var pacer = FeedPacer()                     // folds a burst of folder events into one scan now and one trailing scan
    var liveSessions = LiveSessionCache()       // Claude Code's session files, parsed again only when one changes
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
        // the lines sit in a clear scroll view: the popover is never taller than the screen it opens on, and scrolls
        // beyond that (0.1.14; before, a long Settings or many sessions ran off a small or zoomed screen)
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        // an overlay scroller over the 380 pt lines: a legacy one ("Show scroll bars: Always", a mouse attached) took
        // 17 pt of the width, cut every line and let them slide sideways. No rubber band: the panel stays still.
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scroll.scrollerStyle = .overlay }
        }
        scroll.documentView = lineView
        root.addSubview(scroll)
        // pinned to the root on all four edges: the popover shrinks and grows while open as lines come and go,
        // and an autoresized view in the non flipped root kept its old height and slid up out of the frame
        for v in [tint, scroll] {
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
        hook.refreshScripts()   // an entry installed by an earlier version gets the current script, its chained command kept
        notifier.onReopen = { [weak self] in self?.reopen() }
        notifier.onReopenEnded = { [weak self] id in self?.reopenEnded(id) }
        Reopen.removeLeftovers(in: FileManager.default.temporaryDirectory, now: Date())   // scripts a cancelled prompt left
        offerRestore(now: Date())   // before the first scan, which writes this boot's record over the last one
        notifier.refreshState()   // no prompt at launch: the first nudge that is due asks
        startFeedWatch()
        startTimers(open: false)
        Task { await refreshFeed(); await refreshTranscripts(); await sampleMac(full: false) }
        // macOS 26 can keep a new item switched off under System Settings, Menu Bar, and a full bar hides items behind
        // the notch: then nothing says the app runs. Checked once, a few seconds after the first launch in a bundle.
        if Bundle.main.bundleIdentifier != nil, !Settings.defaults.bool(forKey: Self.hiddenHintKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkItemShows(tries: 10) }
        }

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
                // the open panel itself (scroll view and lines; cacheDisplay draws no blur behind the glass), for the height check
                let before = tab
                tab = 2; render()
                try? await Task.sleep(for: .seconds(1))
                defer { tab = before; render() }
                if let v = popover.contentViewController?.view, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("live-panel.png"))
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        feedTimer?.cancel(); macTimer?.cancel(); transcriptTimer?.cancel(); feedWatch?.stop()
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

    func startFeedWatch() {
        feedWatch?.stop()
        // a burst of writes from many sessions is one scan now and one trailing scan, at most FeedPacer.gap apart (0.1.16).
        // The handler runs on the timer queue and only hands the event to the main actor.
        let w = FolderWatch(path: feed.sessionsDir.path, queue: queue) { @Sendable [weak self] in
            Task { @MainActor in self?.feedEvent() }
        }
        w.start()
        feedWatch = w
    }

    // MARK: readers

    func refreshFeed(trailing: Bool = false) async {
        let now = Date()
        pacer.scanned(at: now, trailing: trailing)
        feedState = await feed.scan(now: now)
        working.apply(feedState.sessions)
        let live = liveSessions.read(settingsFolders: folders)
        sessionNames = Dictionary(live.compactMap { s in s.name.map { (s.sessionId, $0) } }, uniquingKeysWith: { a, _ in a })
        updateAwake(now: now)
        recordSessions(now: now, live: live)
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
        // the aggregate moves with new records, a new day (the "today" window) and a record crossing the 7 or 30 day
        // edge (0.1.15). Then the records are needed even when no transcript changed: an unchanged pass returns none,
        // and summing none emptied every row after midnight until the next transcript write (0.1.0 to 0.1.13).
        let day = Calendar.current.startOfDay(for: now)
        let plan = TokenRefresh.plan(lastDay: tokensDay, today: day, haveTokens: tokens != nil, now: now, nextEdge: tokens?.nextEdge)
        let result = await store.refresh(now: now, onlyIfChanged: plan.onlyIfChanged)
        transcriptsBusy = false
        transcriptsRootsExist = result.rootsExist
        transcriptsError = result.error
        if TokenRefresh.rebuild(plan: plan, versionMoved: result.version != transcriptsVersion) {
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
            let app = ReopenApp.current.title
            notifier.post(title: "\(n) Claude Code session\(n == 1 ? " was" : "s were") open before the restart",
                          body: "\(names). Reopen opens \(n == 1 ? "it" : "each") in \(app) as \(n == 1 ? "it was" : "they were") started.", id: "reopen-\(Int(boot.timeIntervalSince1970))",
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
    func recordSessions(now: Date, live given: [LiveSession]? = nil) {
        guard Settings.bool(Settings.restoreSessions) else { return }
        let live = given ?? liveSessions.read(settingsFolders: folders)
        // the launches of the last scan: a session that is gone now drops out of readLaunches, its options stay here for watchEnds
        let before = launches
        readLaunches(live)
        var byId: [String: RestoreRecord.Launch] = [:]
        for (_, v) in launches { byId[v.id] = v.launch }
        var r = restore ?? RestoreRecord(lastScan: now)
        r.apply(feedState.sessions, launches: byId, now: now)
        restore = r
        // written when a session comes or goes, or a name or the options change
        let key = r.entries.map { [$0.id, $0.name ?? "", ($0.options ?? []).joined(separator: "\u{1}")].joined(separator: "\u{2}") }
        if key != restoreSaved { restoreSaved = key; r.save(to: Paths.restoreFile) }
        watchEnds(live, now: now, launchesBefore: before)
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
    func watchEnds(_ live: [LiveSession], now: Date, launchesBefore: [Int32: (id: String, launch: RestoreRecord.Launch)] = [:]) {
        let gone = sessionWatch.apply(live) { ProcessTable.parent(of: $0) }
        for w in gone {
            guard let parent = w.parent else { continue }
            let entry = restore?.entries.first { $0.id == w.sessionId }
                ?? w.folder.map { RestoreRecord.Entry(id: w.sessionId, folder: $0, transcript: nil, lastSeen: now, name: w.name) }
            guard var e = entry else { continue }
            // a session that ended before its first status line write is not in the record yet: its start options come
            // from the process read of the last scan (VM test 05.11: it came back with its name only)
            if e.options == nil, let l = launchesBefore.values.first(where: { $0.id == w.sessionId }) { e.options = l.launch.options }
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
                // the app the window is in, found from the shell's parents: it need not be the one Reopen opens in
                let window = ReopenApp.windowApp(of: parent).map { "Its \($0.title) window" } ?? "Its window"
                notifier.postAsking(title: "\(e.label) ended", body: "At \(at). \(window) is still open. Reopen starts it again as it was started.",
                                    id: id, category: Notifier.endedCategory)
            }
        }
    }

    /// Reopen on an end notification: that one session, as it was started.
    func reopenEnded(_ notificationId: String) {
        guard let e = endedEntries.removeValue(forKey: notificationId) else { return }
        guard !LiveSession.read(settingsFolders: folders).contains(where: { $0.sessionId == e.id }) else { return }
        openSessions([e])
    }

    /// Reopen: one .command file per session in a private folder, opened in the picked app (Terminal, iTerm or Ghostty)
    /// through Launch Services so no Automation permission is needed. Each file deletes itself when it runs, the last
    /// one its folder; a folder left over is deleted after ten minutes, at the next Reopen or launch.
    func reopen() {
        // a session already open again, from a terminal window or an earlier click, is not opened a second time
        let openNow = Set(feedState.sessions.map(\.snapshot.sessionId)).union(LiveSession.read(settingsFolders: folders).map(\.sessionId))
        let entries = pendingReopen.filter { !openNow.contains($0.id) }
        pendingReopen = []
        restoreLog.info("reopen: \(entries.count, privacy: .public) of the offered sessions, the others are open already")
        guard !entries.isEmpty else { return }
        openSessions(entries)
    }

    /// One .command file per session, each starting the session with its name and options, opened in the picked app.
    func openSessions(_ entries: [RestoreRecord.Entry]) {
        let fm = FileManager.default
        Reopen.removeLeftovers(in: fm.temporaryDirectory, now: Date())
        let dir = fm.temporaryDirectory.appendingPathComponent(Reopen.folderPrefix + UUID().uuidString, isDirectory: true)
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
        guard !files.isEmpty else { return }
        Task { @MainActor in
            // Remote Control connects once, when a session starts, so the sessions wait for the network; without one they still open
            await Self.waitForNetwork(timeout: Rules.restoreNetworkWait)
            await ReopenApp.open(files)
        }
    }

    // MARK: nudges

    /// Each window's nudge is spent only once it was posted: one held back while notifications are off comes at a
    /// later check after they are on again, while its rule still holds (0.1.15, flow test 04.10). While they are off,
    /// the permission is read again at most once a minute here, and at each open of the panel.
    func checkNudges(now: Date) {
        for o in NudgeRules.due(limits: feedState.limits, now: now, enabled: Settings.bool(Settings.nudges))
        where nudges.isDue(o.key, window: o.window) && notifier.mayRead(now: now) {
            nudges.offer(o, ask: { [notifier] in await notifier.authorize() },
                         stillDue: { [weak self] o in
                             guard let self else { return false }
                             // the same text as now, or nothing: a figure that moved while the prompt was up is posted
                             // fresh by the next pass
                             return NudgeRules.due(limits: feedState.limits, now: Date(), enabled: Settings.bool(Settings.nudges)).contains(o)
                         },
                         post: { [notifier] in await notifier.deliver(title: o.title, body: o.body, id: o.id) })
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
        // looked up in Launch Services only while Settings shows, where the row is
        if i.restoreSessions, tab == 2 { i.reopenApp = ReopenApp.current }
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
            let size = fitPanel()
            if popover.contentSize != size { popover.contentSize = size }
        }
    }

    /// The lines at their full height inside the scroll view; the panel as tall as they are, at most the screen's
    /// visible height less a margin for the arrow and the menu bar gap.
    func fitPanel() -> NSSize {
        let full = lineView.contentHeight
        lineView.setFrameSize(NSSize(width: LineView.width, height: full))
        var visible = (item.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height
        #if DEBUG
        // --panel-screen-height N: a small screen, for the scroll check
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--panel-screen-height"), i + 1 < args.count, let h = Double(args[i + 1]) { visible = h }
        #endif
        return NSSize(width: LineView.width, height: PanelSize.height(content: full, visible: visible))
    }

    static let hiddenHintKey = "hiddenItemHintShown"

    /// Is the status item on screen? Not when macOS keeps it switched off, the notch covers it or a menu bar manager
    /// keeps it out of view. While the menu bar itself is away (a full screen app), ask again later.
    func checkItemShows(tries: Int) {
        // a locked screen, a session switched away (Fast User Switching) or a sleeping display hides the menu bar too:
        // no verdict until the user is back at an awake, unlocked screen
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool ?? false
        let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
        guard NSMenu.menuBarVisible(), !locked, onConsole, !asleep else {
            if tries > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkItemShows(tries: tries - 1) } }
            return
        }
        let shows: Bool = {
            guard let w = item.button?.window, w.occlusionState.contains(.visible) else { return false }
            let mid = NSPoint(x: w.frame.midX, y: w.frame.midY)
            return NSScreen.screens.contains { $0.frame.contains(mid) }
        }()
        Settings.defaults.set(true, forKey: Self.hiddenHintKey)   // once: shown now, or seen and never needed
        guard !shows else { log.info("status item visible, no menu bar hint needed"); return }
        log.info("status item not visible, showing the menu bar hint")
        var switchInSettings = false
        if #available(macOS 26, *) { switchInSettings = true }
        // the notch of the screen whose menu bar holds the item; with the item on no screen, none when no screen has one,
        // and both causes when one does (a MacBook with an external display): a Mac mini or an iMac has a full bar, no notch
        let notch = Grammar.notch(itemScreen: item.button?.window?.screen.map { $0.safeAreaInsets.top > 0 },
                                  anyScreen: NSScreen.screens.contains { $0.safeAreaInsets.top > 0 })
        let hint = Grammar.hiddenIconHint(switchInSettings: switchInSettings, notch: notch)
        let alert = NSAlert()
        alert.messageText = hint.title
        alert.informativeText = hint.text
        if let button = hint.button { alert.addButton(withTitle: button) }
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        let answer = alert.runModal()
        if hint.button != nil, answer == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func perform(_ a: Action) {
        switch a {
        case .tab(let t): tab = t; lineView.scroll(.zero)   // a new tab starts at the top
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
                feedWatch?.stop()   // nothing watches until Install; the watch never makes the folder again
            } catch {
                hookFailed("remove", error)
            }
            removeScriptError = hook.writeRemoveScript()
            readHookStatus()
        case .quit: NSApp.terminate(nil)
        case .pickReopenApp:
            showReopenAppMenu()
        case .openNotificationSettings:
            popover.performClose(nil)
            let id = Paths.bundleId
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
                NSWorkspace.shared.open(url)
            }
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
        notifier.refreshState { [weak self] in self?.render() }   // a change in System Settings shows at once
        let screen = ScreenBuilder.screen(input)
        lastScreen = screen
        lineView.lines = Grammar.popover(screen)
        popover.contentSize = fitPanel()
        lineView.scroll(.zero)   // every open starts at the top, with the header and the tabs in view
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
    // the popover's window may carry another appearance than the app: apply again once inside it, before the first frame
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }
    func apply() {
        let light = effectiveAppearance.isLight
        material = light ? .popover : .hudWindow
        tint.layer?.backgroundColor = Tokens.tint.ink(light).cgColor
    }
}
