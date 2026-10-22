// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import UserNotifications

/// The nudges and the session restore offer through the macOS notification centre. UNUserNotificationCenter needs an
/// app bundle; from a bare executable (swift run) the centre cannot be created, so the notifier stays silent and says so.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum State { case unavailable, undecided, allowed, denied }
    private(set) var state: State = .undecided
    private let available: Bool
    nonisolated static let reopenCategory = "reopen"
    nonisolated static let reopenAction = "reopen"
    /// Called on the main actor when the user clicks Reopen, or the restore notification itself.
    var onReopen: (() -> Void)?

    override init() {
        available = Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
        super.init()
        if !available { state = .unavailable; return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reopen = UNNotificationAction(identifier: Self.reopenAction, title: "Reopen", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.reopenCategory, actions: [reopen], intentIdentifiers: [])])
    }

    var noteForSettings: String? {
        switch state {
        case .denied: return "Notifications are off for this app in System Settings"
        case .unavailable: return "Notifications need the app bundle, not swift run"
        default: return nil
        }
    }

    func requestIfNeeded() {
        Task { @MainActor in await authorize() }
    }

    func authorize() async {
        guard available, state == .undecided else { return }
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional: state = .allowed
        case .denied: state = .denied
        default:
            let ok = (try? await center.requestAuthorization(options: [.alert])) ?? false
            state = ok ? .allowed : .denied
        }
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
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
