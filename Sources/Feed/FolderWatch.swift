// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// Watches one folder for writes on a queue, and keeps watching when the folder is deleted or renamed: the watch is then
/// made again on the folder at the same path, tried every `retry` seconds until one is there again (the hook script
/// makes the sessions folder when it is missing). It never makes the folder itself, so Remove's delete holds. A watch
/// on the old folder alone went quiet for good once the folder was gone, until the app was started again (to 0.1.15).
public final class FolderWatch: @unchecked Sendable {
    // unchecked: `source` is read and written only on `queue`
    public let path: String
    let queue: DispatchQueue
    let retry: TimeInterval
    let onEvent: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var active = false
    private var generation = 0       // a retry set before a stop and a new start is dropped
    private var restarts = 0

    /// `onEvent` runs on `queue` for every event, and once more when the watch is made again, since the folder changed.
    public init(path: String, queue: DispatchQueue, retry: TimeInterval = 1, onEvent: @escaping @Sendable () -> Void) {
        self.path = path; self.queue = queue; self.retry = retry; self.onEvent = onEvent
    }

    /// An event that takes the folder away from its path: the watch is made again.
    public static func restarts(on event: DispatchSource.FileSystemEvent) -> Bool {
        !event.isDisjoint(with: [.delete, .rename])
    }

    public func start() { queue.async { self.active = true; self.generation += 1; self.watch(again: false) } }

    public func stop() { queue.async { self.active = false; self.generation += 1; self.source?.cancel(); self.source = nil } }

    /// Whether a watch is on, and how many times it was made again, read on the queue (for the tests).
    public var state: (watching: Bool, restarts: Int) { queue.sync { (source != nil, restarts) } }

    private func watch(again: Bool) {
        source?.cancel()
        source = nil
        guard active else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            let g = generation
            queue.asyncAfter(deadline: .now() + retry) { [weak self] in
                guard let self, self.active, self.generation == g, self.source == nil else { return }
                self.watch(again: again)
            }
            return
        }
        if again { restarts += 1 }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: queue)
        // both handlers run on the queue: nonisolated and Sendable, never main actor code (0.1.16)
        src.setEventHandler { @Sendable [weak self, weak src] in
            guard let self, let src else { return }
            if Self.restarts(on: src.data) { self.watch(again: true) }
            self.onEvent()
        }
        src.setCancelHandler { @Sendable in close(fd) }
        src.resume()
        source = src
        if again { onEvent() }
    }
}
