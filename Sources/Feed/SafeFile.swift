// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// Reads of files other programs write (the feed, Claude Code's session files, settings.json): only a regular file, and
/// only up to a size, checked before a byte is read. A FIFO or a huge file is skipped instead of blocking or filling memory.
public enum SafeFile {
    /// The cap for the small JSON files the app reads: snapshots, session files, settings.json, its own records.
    public static let jsonLimit = 1 << 20

    /// The size of a regular file at the path, following links. nil for anything else or nothing.
    public static func regularFileSize(_ path: String) -> Int? {
        var st = stat()
        guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int(st.st_size)
    }

    public static func isRegularFile(_ path: String) -> Bool { regularFileSize(path) != nil }

    /// The file's bytes when it is a regular file of at most maxBytes; nil otherwise.
    public static func read(_ url: URL, maxBytes: Int = jsonLimit) -> Data? {
        guard let size = regularFileSize(url.path), size <= maxBytes, let d = try? Data(contentsOf: url) else { return nil }
        return d.count <= maxBytes ? d : nil
    }
}
