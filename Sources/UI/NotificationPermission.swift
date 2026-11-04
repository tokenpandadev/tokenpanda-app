// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import UserNotifications
import Feed
import Pace

/// What the app knows about its notification permission, from what System Settings says now.
public enum NotificationPermission: Sendable, Equatable {
    case unavailable, undecided, allowed, denied

    /// notDetermined (never asked, or reset with tccutil) is undecided and is asked again at the next nudge;
    /// provisional counts as allowed; a denial is never asked again, the Settings note points to System Settings.
    public static func from(_ status: UNAuthorizationStatus) -> NotificationPermission {
        switch status {
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        default: return .undecided
        }
    }
}

/// The permission as the newest read or answer says it. A read of System Settings is asynchronous, so a reply that
/// started before a newer read, or before the answer to the prompt, is stale and must not write over them; a counter
/// orders them. The Notifier gives it the notification centre's read and prompt; the tests give it their own, to play
/// the orders out (0.1.15, audit F-4).
@MainActor
public final class PermissionReader {
    public private(set) var state: NotificationPermission
    private let read: @MainActor () async -> NotificationPermission
    private let ask: @MainActor () async -> Bool
    /// Counts reads and answers, so only the newest one sets the state.
    private var ticket = 0
    /// When the last read started; while notifications are off the feed passes read again at most this often.
    public private(set) var lastRead: Date?
    public static let deniedReread: TimeInterval = 60

    public init(state: NotificationPermission = .undecided, read: @escaping @MainActor () async -> NotificationPermission,
                ask: @escaping @MainActor () async -> Bool) {
        self.state = state
        self.read = read
        self.ask = ask
    }

    /// Whether a feed pass may read the permission now: always, except while it is off, then once a minute. The panel's
    /// open reads it anyway (0.1.15, spec 20.6.7).
    public func mayRead(now: Date) -> Bool {
        guard state == .denied, let last = lastRead else { return true }
        return now.timeIntervalSince(last) >= Self.deniedReread
    }

    /// Reads what the user decided, without asking. True when the state moved; a stale reply changes nothing.
    @discardableResult
    public func refresh(now: Date = Date()) async -> Bool {
        lastRead = now
        ticket += 1
        let mine = ticket
        let now = await read()
        guard mine == ticket else { return false }
        let before = state
        state = now
        return state != before
    }

    /// Asks only when the user was never asked; otherwise takes what System Settings says now.
    public func authorize(now: Date = Date()) async {
        lastRead = now
        ticket += 1
        state = await read()
        guard state == .undecided else { return }
        let ok = await ask()
        ticket += 1   // the answer is newer than any read that started while the prompt was up
        state = ok ? .allowed : .denied
    }
}

/// One nudge the rule asks for now: its preference key, its window (the reset, seconds since 1970) and its text.
public struct NudgeOffer: Sendable, Equatable {
    public var key: String
    public var window: Double
    public var title: String
    public var body: String
    public var id: String
    /// The notification's id, which is also what makes the window's nudge one notification.
    public init(key: String, window: Double, title: String, body: String, id: String) {
        self.key = key; self.window = window; self.title = title; self.body = body; self.id = id
    }
}

/// When a nudge is due (spec section 9, 20.6.8): Nudge ticked and the feed fresh; the weekly at 80% or more before
/// its reset; the 5h window from 15 minutes before its reset until the reset. Retired and hidden windows never nudge.
public enum NudgeRules {
    public static let weeklyAt = 80.0
    public static let fiveHourLead: TimeInterval = 15 * 60
    /// The preference keys of the marks, the names every version used.
    public static let weeklyKey = "nudgedWeeklyWindow"
    public static let fiveHourKey = "nudgedFiveHourWindow"

    public static func due(limits: Limits?, now: Date, enabled: Bool) -> [NudgeOffer] {
        guard enabled, let l = limits, !OpenSessionsRule.isStale(asOf: l.asOf, now: now) else { return [] }
        var out: [NudgeOffer] = []
        if let w = l.active("seven_day"), let length = WindowKind.length(forKey: "seven_day"), w.used >= weeklyAt, now < w.resetsAt {
            let start = w.resetsAt.addingTimeInterval(-length)
            let body = PaceModel.reading(used: w.used, start: start, reset: w.resetsAt, now: now).map { PaceModel.nudgeBody($0) } ?? ""
            out.append(NudgeOffer(key: weeklyKey, window: w.resetsAt.timeIntervalSince1970, title: "Weekly at \(Int(w.used.rounded()))%",
                                  body: body, id: "weekly-\(Int(w.resetsAt.timeIntervalSince1970))"))
        }
        if let f = l.active("five_hour"), now >= f.resetsAt.addingTimeInterval(-fiveHourLead), now < f.resetsAt {
            out.append(NudgeOffer(key: fiveHourKey, window: f.resetsAt.timeIntervalSince1970, title: "5h window ends in 15 min",
                                  body: "\(Int(f.used.rounded()))% used.", id: "five-\(Int(f.resetsAt.timeIntervalSince1970))"))
        }
        return out
    }
}

/// Each nudge once per window, and spent only when it was posted. Until 0.1.14 the window was marked right after the
/// post was asked for, so a nudge due while notifications were off was lost for that window (0.1.15, flow test 04.10).
/// The order: ask for the permission, check the rule again with that moment's clock and feed (a prompt may have been
/// up for hours), mark, post, and take the mark back when the post was refused. Marking first means an app quit
/// between the post and the mark never posts the window twice. The marks stay in the preferences as before.
@MainActor
public final class NudgeLedger {
    private let mark: (String) -> Double?
    private let setMark: (String, Double?) -> Void
    /// Windows whose post is on its way, by key and window: a second check of the same window waits for it, the next
    /// window does not.
    private var inFlight: Set<String> = []

    public init(mark: @escaping (String) -> Double?, setMark: @escaping (String, Double?) -> Void) {
        self.mark = mark
        self.setMark = setMark
    }

    func slot(_ key: String, _ window: Double) -> String { key + "@" + String(window) }

    /// Whether the window still has its nudge to give: not marked, and no post of it on its way.
    public func isDue(_ key: String, window: Double) -> Bool { mark(key) != window && !inFlight.contains(slot(key, window)) }

    /// Gives the offer's window its nudge unless it was given or is on its way. ask settles the permission (it may
    /// prompt), stillDue checks the rule again after it, post says whether the centre took the notification.
    /// Returns the task, or nil when nothing was started.
    @discardableResult
    public func offer(_ o: NudgeOffer, ask: @escaping @MainActor () async -> Void, stillDue: @escaping @MainActor (NudgeOffer) -> Bool,
                      post: @escaping @MainActor () async -> Bool) -> Task<Bool, Never>? {
        guard isDue(o.key, window: o.window) else { return nil }
        let s = slot(o.key, o.window)
        inFlight.insert(s)
        return Task { @MainActor in
            defer { inFlight.remove(s) }
            await ask()
            guard stillDue(o), mark(o.key) != o.window else { return false }
            let before = mark(o.key)
            setMark(o.key, o.window)
            let posted = await post()
            if !posted, mark(o.key) == o.window { setMark(o.key, before) }
            return posted
        }
    }
}
