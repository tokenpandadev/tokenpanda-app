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
    var transcriptRoots: [URL]   // the store's roots as last given, for the panel's folder names (the store's own copy is actor isolated)
    let sampler = MacSampler()
    let notifier = Notifier()
    let nudges = NudgeLedger(mark: { Settings.nudged($0) }, setMark: { Settings.setNudged($0, $1) })   // the rule: NudgeRules

    var feedState = FeedState()
    var hookStatus = HookStatus(installed: false, previousCommand: nil)
    var hookError: String? = nil { didSet { if hookError == nil { faults.hook = nil } } }
    var faults = FaultState()   // the same errors in the problem report's fixed words: codes, never text
    var removeScriptError: String? = nil   // remove.sh could not be written, shown under the status line row
    var hookStamp: HookSet.Stamp? = nil   // the settings.json times and the scripts there: the status is read again only when it moves
    var folderClock = FolderClock()       // the home folder is looked at for new settings folders at most once a minute
    let log = Logger(subsystem: Paths.bundleId, category: "hook")
    let restoreLog = Logger(subsystem: Paths.bundleId, category: "restore")
    var tokens: TokenSummary? = nil
    var transcriptsRootsExist = true
    var transcriptsError: String? = nil
    var mac: MacSample? = nil
    var weeks = WeekRecords()
    var hogPid: Int32? = nil
    var hogSince: Date? = nil
    var panelTab = PanelTab()   // the tab and "Copy a problem report" since that tab showed: true copied, false refused, nil not clicked
    var tab: Int { get { panelTab.tab } set { panelTab.select(newValue) } }
    var reportCopied: Bool? { get { panelTab.reportCopied } set { panelTab.reportCopied = newValue } }
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
    var restoreSaved: [String] = []              // the sessions last written (id, name, options, settings folder)
    var restoreSavedAt: Date? = nil              // the last scan written: with no change the file is written again every few minutes
    var offerRepeat = OfferRepeat()              // the restart notice, said once more at the first panel open
    var offer: (title: String, body: String, id: String)? = nil   // the restart notice as posted, for that repeat
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
    var transcriptOrder = RefreshOrder()        // an older pass's summary never replaces a newer one

    override init() {
        feed = FeedReader(dataDir: Paths.dataDir)
        let found = ConfigFolders.scan()   // one listing of the home folder for both lists
        folders = found.install
        hook = HookSet(folders: folders, dataDir: Paths.dataDir)
        // the transcripts of every settings folder found, besides the usual places
        transcriptRoots = ConfigFolders.transcriptRoots(usual: TranscriptLocator.roots(), folders: found.transcripts)
        store = TranscriptStore(roots: transcriptRoots)
        super.init()
        _ = folderClock.due(now: Date())   // the look just made counts: the next one a minute on
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.register()
        weeks = WeekRecords.load(from: Paths.weeksFile)

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
        // only while an entry is installed: after Remove deleted the folder, a launch leaves it deleted (0.1.19)
        hook.prepareSessionsFolder()
        // an entry installed by an earlier version gets its remove script now, so brew's zap needs no click first
        noteRemoveScript(hook.writeRemoveScriptError())
        hook.refreshScripts()   // an entry installed by an earlier version gets the current script, its chained command kept
        notifier.onReopen = { [weak self] in self?.reopen() }
        notifier.onReopenEnded = { [weak self] id in self?.reopenEnded(id) }
        notifier.onOpenPanel = { [weak self] in self?.openPanelFromNotification() }
        Reopen.removeLeftovers(in: Paths.reopenDir, now: Date())        // scripts a cancelled prompt left
        Reopen.removeLeftovers(in: Reopen.tempFolder(), now: Date())    // and those of 0.1.18 and earlier, in the temporary folder
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
                let before = panelTab   // the copied line too: a snapshot never clears what the user sees
                tab = 2; render()
                try? await Task.sleep(for: .seconds(1))
                defer { panelTab = before; render() }
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
        if folderClock.due(now: now) { refreshFolders() }
        if hook.stamp() != hookStamp { readHookStatus() }
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
        transcriptsRootsExist = result.rootsExist
        transcriptsError = result.error; faults.transcripts = result.error == nil ? nil : ReportFaults.transcripts(result.cause)
        if TokenRefresh.rebuild(plan: plan, versionMoved: result.version != transcriptsVersion) {
            let records = result.records
            let summary = await Task.detached(priority: .utility) { Aggregator.summarize(records, now: now) }.value
            // a pass that ran before the one on screen never replaces it (0.1.19)
            if transcriptOrder.accept(result.sequence) {
                transcriptsVersion = result.version
                tokensDay = day
                tokens = summary
            }
        }
        transcriptsBusy = false   // only after the summary is in: a pass started meanwhile is not built on the old one
        render()
    }

    /// A settings folder made since launch (a second account with CLAUDE_CONFIG_DIR) joins the set; Install then offers it,
    /// and its transcripts are counted from the next pass on (0.1.19). Looked for at most once a minute and at each open.
    func refreshFolders() {
        let found = ConfigFolders.scan()
        let roots = ConfigFolders.transcriptRoots(usual: TranscriptLocator.roots(), folders: found.transcripts)
        transcriptRoots = roots
        Task { if await store.setRoots(roots) { await refreshTranscripts() } }
        guard found.install != folders else { return }
        folders = found.install
        hook = HookSet(folders: found.install, dataDir: Paths.dataDir)
        readHookStatus()
    }

    /// settings.json, the one statusLine key, read at launch and again only when a file's modification time moves or a
    /// script comes or goes.
    func readHookStatus() {
        hookStamp = hook.stamp()
        hookStatus = hook.status()
    }

    func sampleMac(full: Bool) async {
        let s = await sampler.sample(full: full, readHealth: BatteryHealthReader.mayRead(tab: tab))
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
    static func setLogin(on: Bool) -> (message: String, fault: Fault)? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return ("Could not turn it \(on ? "on" : "off"): " + error.localizedDescription, ReportFaults.login(on: on, error))
        }
    }

    /// The row's click: while the system waits for the user's OK, it opens Login Items; otherwise it flips the system's state.
    func clickLogin() {
        login = Self.loginStatus()
        if login == .needsApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        let failed = Self.setLogin(on: login == .off)
        loginError = failed?.message; faults.login = failed?.fault
        login = Self.loginStatus()
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
        i.reportCopied = reportCopied
        i.transcriptFolders = ScreenBuilder.folderNames(TranscriptLocator.unique(transcriptRoots))
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
        case .tab(let t): panelTab.select(t); lineView.scroll(.zero); macTabShown()   // a new tab starts at the top
        case .section(let s): section = s
        case .toggle(let key) where key == Grammar.loginKey: clickLogin()
        case .toggle(let key):
            Settings.toggle(key)
            if key == Settings.nudges, Settings.bool(key) { notifier.requestIfNeeded() }
            if key == Settings.keepAwake || key == Settings.keepAwakeWhileOpen { updateAwake(now: Date()) }
            if key == Settings.restoreSessions {
                if Settings.bool(key) { notifier.requestIfNeeded(); recordSessions(now: Date()) }
                else {
                    restore = nil; restoreSaved = []; restoreSavedAt = nil; launches = [:]; sessionWatch = SessionWatch()
                    try? FileManager.default.removeItem(at: Paths.restoreFile)
                }
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
            noteRemoveScript(hook.writeRemoveScriptError())
            readHookStatus()
        case .uninstall:
            do {
                try Self.removeEverywhere(hook)
                hookError = nil
                feedWatch?.stop()   // nothing watches until Install; the watch never makes the folder again
            } catch {
                hookFailed("remove", error)
            }
            noteRemoveScript(hook.writeRemoveScriptError())
            readHookStatus()
        case .quit: NSApp.terminate(nil)
        case .pickReopenApp:
            showReopenAppMenu()
        case .copyReport:
            copyProblemReport()
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
        hookError = "Could not \(what) the entry: " + message; faults.hook = ReportFaults.hook(install: what == "install", error)
        log.error("status line \(what, privacy: .public) failed: \(message, privacy: .private)")
    }

    // MARK: popover

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = item.button else { return }
        login = Self.loginStatus()
        if folderClock.due(now: Date(), force: true) { refreshFolders() }   // a settings folder made since the last look
        repeatOfferIfDue()
        notifier.refreshState { [weak self] in self?.render() }   // a change in System Settings shows at once
        let screen = ScreenBuilder.screen(input)
        lastScreen = screen
        lineView.lines = Grammar.popover(screen)
        popover.contentSize = fitPanel()
        lineView.scroll(.zero)   // every open starts at the top, with the header and the tabs in view
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(lineView)
        startTimers(open: true)
        Task { await sampleMac(full: true); await refreshTranscripts() }; macTabShown()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastScreen = nil
        reportCopied = nil
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
            panelTab.step(back: e.modifierFlags.contains(.shift)); render(); macTabShown()
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
