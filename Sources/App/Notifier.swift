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
    var state: State { available ? reader.state : .unavailable }
    private let available: Bool
    /// The order of reads and answers (PermissionReader, tested); the centre is asked only while available.
    private let reader = PermissionReader(
        read: { NotificationPermission.from(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus) },
        ask: { (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false })
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
        if !available { return }
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
        Task { @MainActor in
            // a reply that started before a newer read or a prompt's answer is stale: the reader drops it
            if await reader.refresh() { onChange?() }
        }
    }

    /// Posts, asking for permission first when the user was never asked: the prompt comes with the first notification
    /// that is due, not at launch.
    func postAsking(title: String, body: String, id: String, category: String? = nil) {
        Task { @MainActor in
            await authorize()
            post(title: title, body: body, id: id, category: category)
        }
    }

    /// Posts without asking and says whether the notification centre took it: false while notifications are off,
    /// outside the bundle, or when the centre refused it. A nudge is spent only on true (NudgeLedger).
    func deliver(title: String, body: String, id: String) async -> Bool {
        guard available, state == .allowed else { return false }
        do { try await UNUserNotificationCenter.current().add(request(title: title, body: body, id: id, category: nil)) } catch { return false }
        return true
    }

    /// Whether a feed pass may read the permission now: once a minute while it is off (PermissionReader.mayRead).
    func mayRead(now: Date) -> Bool { available && reader.mayRead(now: now) }

    func requestIfNeeded() {
        Task { @MainActor in await authorize() }
    }

    /// Asks only when the user was never asked; otherwise takes what System Settings says now, so a nudge after the
    /// user turned notifications back on is posted.
    func authorize() async {
        guard available else { return }
        await reader.authorize()
    }

    func post(title: String, body: String, id: String, category: String? = nil) {
        guard available, state == .allowed else { return }
        UNUserNotificationCenter.current().add(request(title: title, body: body, id: id, category: category))
    }

    func request(title: String, body: String, id: String, category: String?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
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
