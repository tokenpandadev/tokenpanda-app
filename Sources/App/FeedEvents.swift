// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Feed

extension Controller {
    /// A write event in the sessions folder, paced by FeedPacer.
    func feedEvent() {
        let now = Date()
        switch pacer.event(now: now) {
        case .scanNow:
            Task { await refreshFeed() }
        case .scanAt(let at):
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, at.timeIntervalSince(now))))
                await self?.refreshFeed(trailing: true)
            }
        case .wait:
            break
        }
    }
}
