// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import UserNotifications

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
