// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
@testable import Feed
import Text
import Transcripts

/// 0.1.19, second review: the zap's write of settings.json, the bytes the member edit keeps (a byte order mark, CRLF,
/// the spacing, a missing final line break), keycap emoji and a transcript pass asked for while one runs. Every file is
/// made under TestTemp.root.
struct SettingsBytesTests {
    func dir(_ name: String) throws -> URL {
        let u = TestTemp.root.appendingPathComponent("settingsbytes-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    struct Setup { let claude: URL; let file: URL; let set: HookSet }

    /// A settings folder holding `text`, tokenpanda installed into it.
    func installed(_ text: String) throws -> Setup {
        let home = try dir("home"), data = try dir("data").appendingPathComponent("Application Support/dev.tokenpanda.app")
        let claude = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        let file = claude.appendingPathComponent("settings.json")
        try Data(text.utf8).write(to: file)
        let set = HookSet(folders: [claude], dataDir: data, home: home)
        _ = try set.install()
        return Setup(claude: claude, file: file, set: set)
    }

    /// Runs remove.sh as brew's zap does: its exit status and what it printed.
    func zap(_ s: Setup) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [try #require(s.set.removeScriptPath).path]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }

    func statusLine(_ url: URL) throws -> Any? {
        (try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["statusLine"]
    }

    // MARK: 24.54 the zap writes a temporary file and renames it, and says when the entry is still there

    @Test func theZapReplacesAReadOnlySettingsFileInAWritableFolder() throws {
        let s = try installed("{\n  \"a\": 1\n}\n")
        chmod(s.file.path, 0o444)
        let r = try zap(s)
        #expect(r.status == 0)
        #expect(try statusLine(s.file) == nil)   // until now: "Permission denied", the entry kept, still "removed"
        #expect(try String(contentsOf: s.file, encoding: .utf8) == "{\n  \"a\": 1\n}\n")
        var st = stat()
        #expect(stat(s.file.path, &st) == 0 && st.st_mode & 0o777 == 0o444)   // the mode kept
        // no temporary file left next to it
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.claude.path).filter { $0.contains("tokenpanda") }.isEmpty)
    }

    @Test func aZapThatCannotWriteSaysTheEntryIsStillThereAndFails() throws {
        let s = try installed("{\n  \"a\": 1\n}\n")
        let before = try Data(contentsOf: s.file)
        chmod(s.file.path, 0o444); chmod(s.claude.path, 0o555)
        defer { chmod(s.claude.path, 0o755); chmod(s.file.path, 0o644) }
        let r = try zap(s)
        #expect(r.status != 0)
        #expect(r.out.contains("still there"))
        #expect(!r.out.contains("status line entry removed"))
        #expect(try Data(contentsOf: s.file) == before)
    }

    @Test func theZapWritesTheFileALinkPointsAtAndKeepsTheLink() throws {
        let s = try installed("{\n  \"a\": 1\n}\n")
        let dots = try dir("dots").appendingPathComponent("settings.json")
        try FileManager.default.moveItem(at: s.file, to: dots)
        try FileManager.default.createSymbolicLink(at: s.file, withDestinationURL: dots)
        #expect(try zap(s).status == 0)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: s.file.path)) == dots.path)
        #expect(try String(contentsOf: dots, encoding: .utf8) == "{\n  \"a\": 1\n}\n")
    }

    // MARK: 24.55 a byte order mark is kept and the member placed by text

    @Test func aByteOrderMarkIsKeptAndTheMemberPlacedByText() throws {
        let text = "\u{FEFF}{\n  \"zeta\": 1.50,\n  \"a\": 1\n}\n"
        let edited = try #require(SettingsText.edit(Data(text.utf8), to: ["zeta": 1.5, "a": 1, "statusLine": ["type": "command"]]))
        #expect(Array(edited.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: edited, as: UTF8.self) == "\u{FEFF}{\n  \"zeta\": 1.50,\n  \"a\": 1,\n  \"statusLine\": {\n    \"type\": \"command\"\n  }\n}\n")
        // and Install, then Remove, give the very bytes back
        let s = try installed(text)
        #expect(try Data(contentsOf: s.file).prefix(3) == Data([0xEF, 0xBB, 0xBF]))
        try s.set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        #expect(try Data(contentsOf: s.file) == Data(text.utf8))
    }

    // MARK: 24.56 inserted values take the file's line ending and member spacing

    @Test func insertedValuesUseTheFilesLineEndingAndSpacing() throws {
        let crlf = "{\r\n  \"a\": 1\r\n}\r\n"
        let s = try installed(crlf)
        let bytes = [UInt8](try Data(contentsOf: s.file))
        for (i, c) in bytes.enumerated() where c == 0x0a { #expect(i > 0 && bytes[i - 1] == 0x0d) }   // no bare LF
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("\" : "))   // the file's "key": value, not the system writer's "key" : value
        #expect(text.contains("\r\n    \"refreshInterval\": 5,\r\n"))
        try s.set.uninstall(previousCommand: { _ in nil }, previousRefresh: { _ in nil })
        #expect(try String(contentsOf: s.file, encoding: .utf8) == crlf)
        // a file that spells "key" : value keeps that in what is added
        let spaced = "{\n  \"a\" : 1\n}\n"
        let out = String(decoding: try #require(SettingsText.edit(Data(spaced.utf8), to: ["a": 1, "statusLine": ["type": "command", "padding": 0]])), as: UTF8.self)
        #expect(out == "{\n  \"a\" : 1,\n  \"statusLine\" : {\n    \"padding\" : 0,\n    \"type\" : \"command\"\n  }\n}\n")
    }

    // MARK: 24.57 the zap keeps a file without a final line break as it was

    @Test func theZapAddsNoFinalLineBreak() throws {
        for text in ["{\"a\":1}", "{\r\n  \"a\": 1\r\n}", "{\n  \"a\": 1\n}\n\n"] {
            let s = try installed(text)
            #expect(try zap(s).status == 0)
            #expect(try String(contentsOf: s.file, encoding: .utf8) == text)
        }
    }

    // MARK: 24.58 keycaps and copyright or registered as emoji take two cells

    @Test func keycapsAndEmojiStyleSymbolsTakeTwoCells() {
        #expect(Cells.width("1\u{FE0F}\u{20E3}") == 2)
        #expect(Cells.width("#\u{FE0F}\u{20E3}") == 2)
        #expect(Cells.width("1\u{20E3}") == 2)
        #expect(Cells.width("\u{A9}\u{FE0F}") == 2)
        #expect(Cells.width("\u{AE}\u{FE0F}") == 2)
        #expect(Cells.width("\u{A9}") == 1)   // plain copyright stays one cell
        #expect(Cells.prefix("ab1\u{FE0F}\u{20E3}", 3) == "ab")
    }

    // MARK: 24.59 a pass asked for while one runs is run when it ends

    @Test func aPassAskedForWhileOneRunsRunsWhenItEnds() {
        var g = PassGate()
        let started = g.begin()           // a pass starts
        let refused = g.begin()           // the new folder's pass is refused while it runs...
        let refusedAgain = g.begin()      // ...however often it is asked for
        let runsAfter = g.end()           // ...and runs once when the running one ends
        let stillBusy = g.busy
        let ranOut = g.end()              // nothing asked for meanwhile: the gate opens
        #expect(started && !refused && !refusedAgain && runsAfter && stillBusy && !ranOut && !g.busy)
        let again = g.begin(), endsQuietly = g.end()
        #expect(again && !endsQuietly && !g.busy)
    }

    // MARK: 24.60 a backup copy of the settings folder never doubles the token figures

    func transcript(_ folder: URL, ids: [String], tokens: Int) throws {
        let project = folder.appendingPathComponent("projects/-Users-someone-work", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let lines = ids.map {
            #"{"type":"assistant","timestamp":"2026-11-10T10:00:00.000Z","cwd":"/Users/someone/work","sessionId":"s-1","message":{"id":"\#($0)","model":"claude-opus-5-5","usage":{"input_tokens":\#(tokens),"output_tokens":0}}}"#
        }
        try (lines.joined(separator: "\n") + "\n").write(to: project.appendingPathComponent("s-1.jsonl"), atomically: true, encoding: .utf8)
    }

    @Test func aBackupCopyOfTheSettingsFolderIsNotReadForTranscripts() throws {
        let home = try dir("home")
        try transcript(home.appendingPathComponent(".claude"), ids: ["m1"], tokens: 150)
        try transcript(home.appendingPathComponent(".claude-backup"), ids: ["m1"], tokens: 150)
        try transcript(home.appendingPathComponent(".claude-work"), ids: ["w1"], tokens: 10)
        try "{}".write(to: home.appendingPathComponent(".claude-work/settings.json"), atomically: true, encoding: .utf8)
        let found = ConfigFolders.scan(home: home, environment: [:])
        #expect(found.transcripts.map(\.lastPathComponent) == [".claude", ".claude-work"])
        #expect(found.install.map(\.lastPathComponent) == [".claude", ".claude-work"])
    }

    @Test func aReplyCountedInOneFileIsNotCountedAgainInAnother() async throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!
        let home = try dir("home")
        let main = home.appendingPathComponent(".claude"), copy = home.appendingPathComponent("copy")
        try transcript(main, ids: ["m1", "m2"], tokens: 150)
        try transcript(copy, ids: ["m1", "m2", "m3"], tokens: 150)   // a copy that went on, or a resumed session
        let store = TranscriptStore(roots: [main.appendingPathComponent("projects"), copy.appendingPathComponent("projects")])
        let r = await store.refresh(now: now)
        #expect(r.records.count == 3)
        #expect(Aggregator.summarize(r.records, now: now).tokens7d == 450)   // until now 750: m1 and m2 twice
        // the same answer on the next pass, and when the first copy goes the other still counts
        #expect(await store.refresh(now: now).records.count == 3)
        try FileManager.default.removeItem(at: main.appendingPathComponent("projects"))
        #expect(await store.refresh(now: now).records.count == 3)
    }

    // MARK: 24.61 the zap puts a saved entry back member by member, in the file's own layout

    @Test func theZapPutsASavedEntryBackInTheFilesOwnLayout() throws {
        let texts = [
            "{\n    \"model\": \"opus\",\n    \"statusLine\": {\n        \"type\": \"command\",\n        \"command\": \"echo hi\",\n        \"padding\": 1\n    },\n    \"z\": [1, 2]\n}\n",
            "{\r\n\t\"statusLine\" : {\"type\" : \"command\", \"command\" : \"echo hi\"},\r\n\t\"a\" : 1.50\r\n}",
            "\u{FEFF}{\"statusLine\":{\"command\":\"echo hi\",\"type\":\"command\"}}",
        ]
        for text in texts {
            let s = try installed(text)
            let sl = try #require(try statusLine(s.file) as? [String: Any])
            #expect((sl["command"] as? String)?.contains("hook") == true)
            #expect(try zap(s).status == 0)
            #expect(try Data(contentsOf: s.file) == Data(text.utf8))   // as Data: reading a String drops a byte order mark
        }
    }

    // MARK: 24.62 a Reopen click that skips some sessions says so also when others open

    @Test func aPartlySkippedReopenSaysHowManyAndWhy() throws {
        let gone = RestoreRecord.Entry(id: "3f1a9c2e-0000-4000-8000-000000000001", folder: "/x", transcript: nil, lastSeen: Date(), name: "api work")
        let other = RestoreRecord.Entry(id: "3f1a9c2e-0000-4000-8000-000000000002", folder: "/x", transcript: nil, lastSeen: Date())
        var w = ReopenWrite()
        w.files = [URL(fileURLWithPath: "/x/a.command")]
        w.skipped = [ReopenWrite.Skip(id: gone.id, label: gone.label, code: .folderGone)]
        var n = try #require(w.notice())
        #expect(n.title == "api work did not reopen" && n.body == "Its folder is gone. The other session reopened.")
        w.files.append(URL(fileURLWithPath: "/x/b.command"))
        w.skipped.append(ReopenWrite.Skip(id: other.id, label: other.label, code: .folderGone))
        n = try #require(w.notice())
        #expect(n.title == "2 of 4 sessions did not reopen" && n.body == "Their folders are gone. The other 2 sessions reopened.")
        w.skipped[1].code = .scriptWrite
        #expect(try #require(w.notice()).body == "Some folders are gone or their start scripts could not be written. The other 2 sessions reopened.")
        // none opened: the wording of nothingOpened, unchanged; nothing skipped: no notice
        w.files = []
        let none = try #require(w.notice()), nothing = try #require(w.nothingOpened())
        #expect(none == nothing)
        #expect(ReopenWrite().notice() == nil)
    }
}
