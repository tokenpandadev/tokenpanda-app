// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// The one folder every test writes under, removed when the test process exits. Before, each test made its own folder
/// and left it: 792 under /tmp by 09.11.2026. Under /tmp on purpose: /tmp is itself a link to /private/tmp, so paths
/// also walk a linked folder at the root, as the real temp folder does.
enum TestTemp {
    static let root: URL = {
        let url = URL(fileURLWithPath: "/tmp/tokenpanda-test-run-\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = strdup(url.path)
        atexit {
            if let p = TestTemp.path { try? FileManager.default.removeItem(atPath: String(cString: p)) }
        }
        return url
    }()
    nonisolated(unsafe) private static var path: UnsafeMutablePointer<CChar>?
}
