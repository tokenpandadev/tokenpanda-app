// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import UserNotifications
import Text
import UI

/// The nudges and the session restore offer through the macOS notification centre. UNUserNotificationCenter needs an
/// app bundle; from a bare executable (swift run) the centre cannot be created, so the notifier stays silent and says so.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    typealias State = NotificationPermission
    private(set) var state: State = .undecided
    private let available: Bool
    nonisolated static let reopenCategory = "reopen"
    nonisolated static let reopenAction = "reopen"
    nonisolated static let endedCategory = "ended"
    /// Called on the main actor when the user clicks Reopen, or the restore notification itself.
    var onReopen: (() -> Void)?
    /// Called with the notification's id when the user clicks Reopen on a session's end notification, or the notification.
    var onReopenEnded: ((String) -> Void)?

    override init() {
        available = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
        super.init()
        if !available { state = .unavailable; return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reopen = UNNotificationAction(identifier: Self.reopenAction, title: "Reopen", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.reopenCategory, actions: [reopen], intentIdentifiers: []),
                                          UNNotificationCategory(identifier: Self.endedCategory, actions: [reopen], intentIdentifiers: [])])
    }

    var noteForSettings: String? {
        switch state {
        case .denied: return Grammar.notificationsOff
        case .unavailable: return "Notifications need the app bundle"
        default: return nil
        }
    }

    /// Reads what the user decided, without asking: at launch, and each time the popover opens, so turning
    /// notifications on or off in System Settings counts at once (0.1.12 to 0.1.13 kept a denial until a restart).
    /// onChange runs when the state moved, for the Settings note.
    func refreshState(onChange: (() -> Void)? = nil) {
        guard available else { return }
        reads += 1
        let mine = reads
        Task { @MainActor in
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            // a reply that started before a newer read or a prompt's answer is stale: it must not write over them
            guard mine == reads else { return }
            let before = state
            state = NotificationPermission.from(status)
            if state != before { onChange?() }
        }
    }

    /// Counts reads and answers, so only the newest one sets the state.
    private var reads = 0

    /// Posts, asking for permission first when the user was never asked: the prompt comes with the first notification
    /// that is due, not at launch.
    func postAsking(title: String, body: String, id: String, category: String? = nil) {
        Task { @MainActor in
            await authorize()
            post(title: title, body: body, id: id, category: category)
        }
    }

    func requestIfNeeded() {
        Task { @MainActor in await authorize() }
    }

    /// Asks only when the user was never asked; otherwise takes what System Settings says now, so a nudge after the
    /// user turned notifications back on is posted.
    func authorize() async {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        reads += 1
        state = NotificationPermission.from(await center.notificationSettings().authorizationStatus)
        guard state == .undecided else { return }
        let ok = (try? await center.requestAuthorization(options: [.alert])) ?? false
        reads += 1   // the answer is newer than any read that started while the prompt was up
        state = ok ? .allowed : .denied
    }

    func post(title: String, body: String, id: String, category: String? = nil) {
        guard available, state == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        if category == Self.reopenCategory, action == Self.reopenAction || action == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.onReopen?() }
        }
        if category == Self.endedCategory, action == Self.reopenAction || action == UNNotificationDefaultActionIdentifier {
            let id = response.notification.request.identifier
            Task { @MainActor in self.onReopenEnded?(id) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
