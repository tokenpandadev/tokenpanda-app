// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Feed
import MacStats

extension Controller {
    /// The Mac tab came up: the battery's word now, not on the next 2 s tick. Only the word changes; the figures stay on their tick.
    func macTabShown() {
        guard BatteryHealthReader.mayRead(tab: tab) else { return }
        Task {
            guard let read = await sampler.refreshHealth(), BatteryHealthReader.mayShow(panelShown: popover.isShown, tab: tab) else { return }
            mac?.battery?.health = read.word
            render()
        }
    }

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
