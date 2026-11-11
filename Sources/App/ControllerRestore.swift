// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// Session restore: the offer after a restart, the end notice, and Reopen. Split from Controller.swift so the class body
// stays within its length rule; the state it uses lives in Controller.
import AppKit
import os
import Text
import Pace
import Feed
import Transcripts
import UI

extension Controller {
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
            let o = (title: "\(n) Claude Code session\(n == 1 ? " was" : "s were") open before the restart",
                     body: "\(names). Reopen opens \(n == 1 ? "it" : "each") in \(app) as \(n == 1 ? "it was" : "they were") started.",
                     id: "reopen-\(Int(boot.timeIntervalSince1970))")
            offer = o
            notifier.post(title: o.title, body: o.body, id: o.id, category: Notifier.reopenCategory)
            offerRepeat.didPost()
        }
    }

    /// The first open of the panel after the restart notice: said once more, with the same id, so a notice that went under
    /// macOS's "Login Item Added" banner at login comes up again while the user looks (0.1.19, flow test 11.2).
    func repeatOfferIfDue() {
        guard offerRepeat.panelOpened(pending: !pendingReopen.isEmpty), let o = offer else { return }
        restoreLog.info("restore: the offer once more, at the first panel open")
        notifier.post(title: o.title, body: o.body, id: o.id, category: Notifier.reopenCategory)
    }

    /// A click on the restore or end notification itself: the panel opens, nothing starts (only Reopen starts sessions).
    func openPanelFromNotification() {
        NSApp.activate()
        _ = offerRepeat.panelOpened(pending: true)   // the notice was just seen and clicked: no repeat of it now
        if !popover.isShown { togglePopover() }
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
        // written when a session comes or goes, or a name, the options or the settings folder change, and every few
        // minutes for the last scan alone, which the offer after a restart goes by
        let key = r.saveKey
        if RestoreRecord.shouldSave(key: key, savedKey: restoreSaved, lastScan: r.lastScan, savedScan: restoreSavedAt) {
            restoreSaved = key; restoreSavedAt = r.lastScan; r.save(to: Paths.restoreFile)
        }
        watchEnds(live, now: now, launchesBefore: before)
    }

    /// Reads the start options of each session process not seen before, once per process; the name is read every time,
    /// as /rename changes it.
    func readLaunches(_ live: [LiveSession]) {
        var next: [Int32: (id: String, launch: RestoreRecord.Launch)] = [:]
        for s in live {
            var options = launches[s.pid]?.launch.options
            if launches[s.pid]?.id != s.sessionId || options == nil {
                let read = ProcessTable.arguments(of: s.pid).flatMap { LaunchOptions.keptNoting(fromArguments: $0) }
                options = read?.options
                // an inline JSON value can hold a key or a token: never kept, only its option's name is logged
                if let d = read?.dropped, !d.isEmpty {
                    restoreLog.info("restore: left out \(d.count, privacy: .public) start options given as inline JSON (\(d.joined(separator: " "), privacy: .public))")
                }
            }
            next[s.pid] = (s.sessionId, RestoreRecord.Launch(name: s.name, options: options, configDir: s.settingsFolder))
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
            if let l = launchesBefore.values.first(where: { $0.id == w.sessionId }) {
                if e.options == nil { e.options = l.launch.options }
                if e.configDir == nil { e.configDir = l.launch.configDir }
            }
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

    /// Reopen: one .command file per session in a private folder under the data folder, opened in the picked app
    /// (Terminal, iTerm or Ghostty) through Launch Services so no Automation permission is needed. Each file deletes
    /// itself when it runs, the last one its folder; a folder left over is deleted after ten minutes, at the next Reopen
    /// or launch, and by the zap with the data folder.
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
    /// A session it cannot write a script for is logged with its code, and one notification says how many were skipped
    /// and why, also when others opened.
    func openSessions(_ entries: [RestoreRecord.Entry]) {
        let done = ReopenWrite.write(entries, into: Paths.reopenDir, now: Date())
        for s in done.skipped { restoreLog.error("reopen: skipped a session: \(s.code.rawValue, privacy: .public)") }
        if !done.skipped.isEmpty {
            restoreLog.error("reopen: \(done.skipped.count, privacy: .public) of \(entries.count, privacy: .public) sessions skipped (\(done.counts, privacy: .public))")
        }
        if let notice = done.notice() {
            notifier.postAsking(title: notice.title, body: notice.body, id: "reopen-failed-\(Int(Date().timeIntervalSince1970))")
        }
        let files = done.files
        guard !files.isEmpty else { return }
        restoreLog.info("reopen: \(files.count, privacy: .public) start scripts written")
        Task { @MainActor in
            // Remote Control connects once, when a session starts, so the sessions wait for the network; without one they still open
            await Self.waitForNetwork(timeout: Rules.restoreNetworkWait)
            await ReopenApp.open(files)
        }
    }
}
