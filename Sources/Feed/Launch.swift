// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Darwin

// How each open Claude Code session was started, so a restart can reopen it the same way: its name and the options
// it was started with (extra folders, start prompt, model and the rest). Read only for session restore, on this Mac.
//
// Claude Code keeps one small file per running session in <settings folder>/sessions/<pid>.json with the session id,
// folder and name. Not documented by Anthropic: if those files stop appearing, sessions still reopen, with a plain resume.

/// One running session as Claude Code's own session file describes it.
public struct LiveSession: Sendable, Equatable {
    public var pid: Int32
    public var sessionId: String
    public var folder: String?
    public var name: String?          // set by the user with -n or /rename; nil for an unnamed session
    public init(pid: Int32, sessionId: String, folder: String?, name: String?) {
        self.pid = pid; self.sessionId = sessionId; self.folder = folder; self.name = name
    }

    /// Parses one <pid>.json. Only an interactive session started from the command line counts: print runs, the SDK
    /// and the desktop app have nothing to reopen in Terminal.
    public static func parse(_ data: Data) -> LiveSession? {
        guard let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sid = d["sessionId"] as? String, Reopen.isSessionId(sid),
              let pid = (d["pid"] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        if let kind = d["kind"] as? String, kind != "interactive" { return nil }
        if let entry = d["entrypoint"] as? String, entry != "cli" { return nil }
        var name = d["name"] as? String
        if let source = d["nameSource"] as? String, source != "user" { name = nil }
        if let n = name, n.trimmingCharacters(in: .whitespaces).isEmpty { name = nil }
        return LiveSession(pid: pid, sessionId: sid, folder: d["cwd"] as? String, name: name)
    }

    /// The sessions whose process is still running, from the sessions folder of each settings folder.
    public static func read(settingsFolders: [URL]) -> [LiveSession] {
        let fm = FileManager.default
        var out: [LiveSession] = []
        var seen = Set<Int32>()
        for f in settingsFolders {
            let dir = f.appendingPathComponent("sessions", isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in names where n.hasSuffix(".json") {
                // the size is checked before the read: a session file is a few hundred bytes
                guard let d = SafeFile.read(dir.appendingPathComponent(n), maxBytes: 64 * 1024 - 1),
                      let s = parse(d), !seen.contains(s.pid), ProcessTable.isRunning(s.pid) else { continue }
                seen.insert(s.pid)
                out.append(s)
            }
        }
        return out
    }
}

/// The process facts the restore needs, read with sysctl: whether a process runs, its parent, its arguments.
public enum ProcessTable {
    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    public static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let p = info.kp_eproc.e_ppid
        return p > 0 ? p : nil
    }

    /// The arguments a process was started with (argv, without the environment), from KERN_PROCARGS2.
    public static func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buf.prefix(size)))
    }

    /// KERN_PROCARGS2 layout: argc (Int32), the executable path, NUL padding, then argc NUL terminated strings.
    public static func parseProcArgs(_ buf: [UInt8]) -> [String]? {
        guard buf.count > 4 else { return nil }
        let argc = Int(buf.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        guard argc > 0, argc < 4096 else { return nil }
        var i = 4
        while i < buf.count, buf[i] != 0 { i += 1 }     // executable path
        while i < buf.count, buf[i] == 0 { i += 1 }     // padding
        var args: [String] = []
        while args.count < argc, i < buf.count {
            var j = i
            while j < buf.count, buf[j] != 0 { j += 1 }
            args.append(String(decoding: buf[i..<j], as: UTF8.self))
            i = j + 1
        }
        return args.count == argc ? args : nil
    }
}

/// Which of a session's start options a reopen keeps. Built from `claude --help` (2.1.316). Options that start a new or
/// different session, run once and exit, or only matter with --print are left out, and so is a start prompt typed after
/// the options, so a reopen never sends it again. An option this list does not know is kept on its own; a word after it
/// is taken for a start prompt and left out.
public enum LaunchOptions {
    enum Kind { case flag, value, optional, variadic }

    /// Kept: the session's setup.
    static let keep: [String: Kind] = [
        "--add-dir": .variadic, "--agent": .value, "--agents": .value, "--allow-dangerously-skip-permissions": .flag,
        "--allowedTools": .variadic, "--allowed-tools": .variadic, "--append-system-prompt": .value, "--append-system-prompt-file": .value,
        "--autocompact": .value, "--ax-screen-reader": .flag, "--bare": .flag, "--betas": .variadic, "--brief": .flag, "--chrome": .flag,
        "--dangerously-skip-permissions": .flag, "-d": .optional, "--debug": .optional, "--debug-file": .value,
        "--disable-slash-commands": .flag, "--disallowedTools": .variadic, "--disallowed-tools": .variadic, "--effort": .value,
        "--exclude-dynamic-system-prompt-sections": .flag, "--fallback-model": .value, "--ide": .flag, "--max-budget-usd": .value,
        "--mcp-config": .variadic, "--model": .value, "--no-chrome": .flag, "--permission-mode": .value, "--permission-prompts": .value,
        "--plugin-dir": .value, "--plugin-url": .value, "--remote-control-session-name-prefix": .value, "--restricted": .flag,
        "--safe-mode": .flag, "--setting-sources": .value, "--settings": .value, "--strict-mcp-config": .flag,
        "--system-prompt": .value, "--system-prompt-file": .value, "--system-prompt-snapshot": .value, "--tools": .variadic,
        "--verbose": .flag,
    ]
    /// Left out: they pick, fork or name the session (the reopen sets those itself), or belong to a one off run.
    static let drop: [String: Kind] = [
        "-c": .flag, "--continue": .flag, "-r": .optional, "--resume": .optional, "--session-id": .value, "--fork-session": .flag,
        "-n": .value, "--name": .value, "--remote-control": .optional, "--from-pr": .optional, "--bg": .flag, "--background": .flag,
        "--desktop": .flag, "--tmux": .optional, "-w": .optional, "--worktree": .optional, "--file": .variadic,
        "--prompt-suggestions": .optional, "--input-format": .value, "--output-format": .value, "--json-schema": .value,
        "--include-hook-events": .flag, "--include-partial-messages": .flag, "--replay-user-messages": .flag,
        "--forward-subagent-text": .flag,
    ]
    /// A session started with one of these is not reopened from its options at all: there is no Terminal session to resume.
    static let notResumable: Set<String> = ["-p", "--print", "--no-session-persistence", "--cloud", "--teleport", "--environment",
                                            "-h", "--help", "-v", "--version"]

    /// The options to start the reopened session with, from the process arguments (argv[0] first). Nil when the session
    /// cannot be reopened from them, or when argv[0] is not claude.
    public static func kept(fromArguments argv: [String]) -> [String]? {
        guard let first = argv.first else { return nil }
        var i = 1
        // the npm install runs as node with the CLI script as its first argument
        if (first as NSString).lastPathComponent == "node", argv.count > 1, argv[1].contains("claude") { i = 2 }
        else if (first as NSString).lastPathComponent != "claude" { return nil }
        var out: [String] = []
        var optionsEnded = false
        while i < argv.count {
            let a = argv[i]
            i += 1
            if optionsEnded || !a.hasPrefix("-") || a == "-" { continue }          // a start prompt or a subcommand word
            if a == "--" { optionsEnded = true; continue }
            let name = a.hasPrefix("--") ? String(a.split(separator: "=", maxSplits: 1)[0]) : a
            let inline = a.hasPrefix("--") && a.contains("=")
            if notResumable.contains(name) { return nil }
            // the values that follow the option
            func values(_ kind: Kind) -> [String] {
                if inline { return [] }
                var v: [String] = []
                switch kind {
                case .flag: break
                case .value: if i < argv.count { v.append(argv[i]); i += 1 }
                case .optional: if i < argv.count, !argv[i].hasPrefix("-") { v.append(argv[i]); i += 1 }
                case .variadic: while i < argv.count, !argv[i].hasPrefix("-") { v.append(argv[i]); i += 1 }
                }
                return v
            }
            if let k = keep[name] { out.append(a); out += values(k) }
            else if let k = drop[name] { _ = values(k) }
            else if a.hasPrefix("--") { out.append(a) }                             // unknown: kept alone
        }
        return out
    }
}

extension Reopen {
    /// How long a failed start may take for the script to try the next, plainer one. A session that ran longer and then
    /// ended with an error is not started again.
    public static let fallbackWithin = 20

    /// The script that reopens a session as it was started: its options, its name, and Remote Control when it had it.
    /// If that start fails within a few seconds, the same without Remote Control, then a plain resume. When the session
    /// ends, the window keeps a shell, as a window where claude was typed does, so an end on its own is told apart from
    /// a closed window.
    public static func script(id: String, folder: String, name: String?, options: [String]?, remoteControl: Bool) -> String? {
        var isDir: ObjCBool = false
        guard isSessionId(id), FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else { return nil }
        let plain = ["claude", "--resume", id]
        var full = plain + (options ?? [])
        if let n = name { full += ["--name", n] }
        var tries: [[String]] = []
        if remoteControl { tries.append(full + ["--remote-control"]) }
        tries.append(full)
        if full != plain { tries.append(plain) }
        var s = "#!/bin/zsh -l\nrm -f -- \"$0\"\ncd " + quote(folder) + " || exit 1\n"
        var depth = 0
        for (k, t) in tries.enumerated() {
            let pad = String(repeating: "  ", count: depth)
            let line = t.map(quote).joined(separator: " ")
            if k == tries.count - 1 { s += pad + line + "\n"; break }
            s += pad + "t=$SECONDS\n" + pad + line + "\n" + pad + "if (( $? != 0 && SECONDS - t < \(fallbackWithin) )); then\n"
            depth += 1
        }
        while depth > 0 { depth -= 1; s += String(repeating: "  ", count: depth) + "fi\n" }
        return s + "exec \"${SHELL:-/bin/zsh}\" -l\n"
    }
}

/// Watches the running sessions by process, to tell when one ends. A session that ends while the process that started
/// it (the Terminal window's shell, or a script) still runs ended on its own or was quit in a window that stays open;
/// one whose window closed too, or that ends during a shutdown, is not reported.
public struct SessionWatch: Sendable, Equatable {
    public struct Watched: Sendable, Equatable {
        public var sessionId: String
        public var folder: String?
        public var name: String?
        public var parent: Int32?
        public init(sessionId: String, folder: String?, name: String?, parent: Int32?) {
            self.sessionId = sessionId; self.folder = folder; self.name = name; self.parent = parent
        }
    }
    public private(set) var byPid: [Int32: Watched] = [:]
    public init() {}

    /// Applies one read of the running sessions, with each new one's parent. Returns the sessions that are gone since
    /// the last read. A session id that runs again under a new process is not gone.
    public mutating func apply(_ live: [LiveSession], parent: (Int32) -> Int32?) -> [Watched] {
        var next: [Int32: Watched] = [:]
        for s in live {
            var w = byPid[s.pid] ?? Watched(sessionId: s.sessionId, folder: s.folder, name: s.name, parent: parent(s.pid))
            w.name = s.name; w.folder = s.folder ?? w.folder
            next[s.pid] = w
        }
        let running = Set(live.map(\.sessionId))
        let gone = byPid.filter { next[$0.key] == nil && !running.contains($0.value.sessionId) }.map(\.value)
        byPid = next
        return gone.sorted { $0.sessionId < $1.sessionId }
    }
}

/// The names a notification lists: each session's name, or its folder when it has none, a folder counted when several
/// unnamed sessions share it, the first few and how many more.
public enum SessionNames {
    public static func list(_ labels: [String], named: Set<String>, max: Int = 5) -> String {
        var order: [String] = []
        var count: [String: Int] = [:]
        for l in labels { if count[l] == nil { order.append(l) }; count[l, default: 0] += 1 }
        let items = order.map { l -> String in
            let n = count[l] ?? 1
            return n > 1 && !named.contains(l) ? "\(l) (\(n))" : l
        }
        guard items.count > max else { return join(items) }
        let shown = Array(items.prefix(max - 1))
        return shown.joined(separator: ", ") + " and \(items.count - shown.count) more"
    }

    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
