// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation

/// A transcript file: a session at depth 1 under a project, or a subagent file under <session>/subagents/.
public struct TranscriptFile: Sendable, Hashable {
    public var url: URL
    public var projectFolder: String      // the project folder name as Claude Code wrote it
    public var sessionId: String          // the session file name, or the parent session of a subagent file
    public var isAgent: Bool
    public var size: UInt64
    public var modified: Date
    public var id = FileID(device: 0, inode: 0)   // the file itself, whatever path reached it (0.1.19)
}

/// A file's device and inode: the same file reached through a linked folder has one id under every path.
public struct FileID: Sendable, Hashable {
    public var device: UInt64
    public var inode: UInt64
    public init(device: UInt64, inode: UInt64) { self.device = device; self.inode = inode }
}

/// Finds the transcript roots and enumerates only the two patterns. Never walks a directory recursively,
/// never lists a session folder, never names memory/ or tool-results/.
public enum TranscriptLocator {
    public static let keepDays: TimeInterval = 32 * 24 * 3600

    public static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                             environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var out = [home.appendingPathComponent(".claude/projects", isDirectory: true),
                   home.appendingPathComponent(".config/claude/projects", isDirectory: true)]
        // one path, as Claude Code reads it: a comma is part of the path (0.1.19; until 0.1.18 it was split at commas)
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true).appendingPathComponent("projects", isDirectory: true))
        }
        return unique(out)
    }

    /// The roots with every folder reached through a link kept once, the first spelling wins: ~/.config/claude linking to
    /// ~/.claude, or a CLAUDE_CONFIG_DIR that is a link to another root, read every file twice until 0.1.18.
    public static func unique(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.filter { seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted }
    }

    public static func files(under roots: [URL], now: Date = Date()) -> [TranscriptFile] {
        let fm = FileManager.default
        var out: [TranscriptFile] = []
        var seen = Set<FileID>()   // a file reached twice (a linked project folder, a root linked after launch) is listed once
        let cutoff = now.addingTimeInterval(-keepDays)
        for root in roots {
            guard let projects = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for project in projects where !project.hasPrefix(".") {
                let projectURL = root.appendingPathComponent(project, isDirectory: true)
                guard let entries = try? fm.contentsOfDirectory(atPath: projectURL.path) else { continue }
                for entry in entries {
                    if entry == "memory" || entry.hasPrefix(".") { continue }
                    let url = projectURL.appendingPathComponent(entry)
                    if entry.hasSuffix(".jsonl") {
                        if let f = describe(url, project: project, session: String(entry.dropLast(6)), agent: false, cutoff: cutoff),
                           seen.insert(f.id).inserted { out.append(f) }
                        continue
                    }
                    // a session folder: only its subagents/ is looked at, by name, without listing the folder itself
                    let sub = url.appendingPathComponent("subagents", isDirectory: true)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue,
                          let agents = try? fm.contentsOfDirectory(atPath: sub.path) else { continue }
                    for a in agents where a.hasSuffix(".jsonl") {
                        if let f = describe(sub.appendingPathComponent(a), project: project, session: entry, agent: true, cutoff: cutoff),
                           seen.insert(f.id).inserted { out.append(f) }
                    }
                }
            }
        }
        return out
    }

    /// stat(2) rather than attributesOfItem: this runs for every file every 10 s while the popover is open.
    static func describe(_ url: URL, project: String, session: String, agent: Bool, cutoff: Date) -> TranscriptFile? {
        var st = stat()
        guard stat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        let mtime = Date(timeIntervalSince1970: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
        guard mtime >= cutoff else { return nil }
        return TranscriptFile(url: url, projectFolder: project, sessionId: session, isAgent: agent, size: UInt64(st.st_size), modified: mtime,
                              id: FileID(device: UInt64(UInt32(bitPattern: st.st_dev)), inode: UInt64(st.st_ino)))
    }

    /// The project folder's last dash segment, the fallback when no line carried a working directory.
    public static func projectName(fromFolder folder: String) -> String {
        String(folder.split(separator: "-").last ?? Substring(folder))
    }
}
