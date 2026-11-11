// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Testing
import Foundation
import AppKit
import Feed
import Text
import UI

/// "Copy a problem report": what the text holds, and what it never holds (05.11.2026). Since the second review of 00b5982
/// no error text reaches the report: each error is a Fault in fixed words plus its codes. These tests feed the leak cases of
/// both reviews in as real errors (description, file path, URL, underlying error, domain) and check nothing of them shows.
struct ProblemReportTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func report(faults: [Fault] = [], folders: [ProblemReport.Folder]? = nil, keepAwake: Bool = true,
                       userNames: [String] = [], version: String = "0.1.17") -> ProblemReport {
        ProblemReport(version: version, macOS: "26.1 (25B78)", model: "Mac15,6", openAtLogin: .on, macInBar: false, nudges: true, listPrice: true,
                      keepAwake: keepAwake, keepAwakeWhileOpen: false, restoreSessions: true, reopenApp: .ghostty,
                      folders: folders ?? [.init(name: "~/.claude", installed: true), .init(name: "~/.claude-work", installed: false, scriptMissing: true)],
                      lastData: Date(timeIntervalSince1970: 1_793_000_000), sessions: 3, faults: faults, userNames: userNames, timeZone: utc)
    }

    @Test func theTextHoldsTheAgreedSet() {
        #expect(Self.report().text == """
        tokenpanda problem report
        tokenpanda 0.1.17
        macOS 26.1 (25B78)
        Mac model Mac15,6

        Open at login: on
        Mac figures in the bar: off
        Nudges: on
        List price equivalent: on
        Keep the Mac awake: on
          also while a session waits: off
        Reopen sessions after a restart: on, in Ghostty

        Status line entry in ~/.claude: set up
        Status line entry in ~/.claude-(name): not set up, the hook script is gone
        Last status line data: 2026-10-26 07:33
        Sessions running: 3

        Errors shown: none

        """)
    }

    @Test func errorsAreFixedWordsWithCodes() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
        let t = Self.report(faults: [Fault(.statusLine, .install, step: .writeSettings, code: ErrorCode(denied)),
                                     ReportFaults.transcripts(NSError(domain: NSPOSIXErrorDomain, code: 1)),
                                     Fault(.statusLine, .install, step: .readSettings, reason: .notJSON),
                                     ReportFaults.feedFormat, ReportFaults.macWarning]).text
        #expect(t.hasSuffix("""
        Errors shown:
        - Status line entry: could not install, could not write the settings file (NSCocoaErrorDomain 513, POSIX 13 EACCES)
        - Transcripts: could not read (POSIX 1 EPERM)
        - Status line entry: could not install, could not read the settings file: not valid JSON
        - Feed format: changed, update tokenpanda
        - Mac tab: shows its warning: memory pressure or a process holding the CPU

        """))
    }

    @Test func theSecondAwakeRowShowsOnlyWithTheFirst() {
        #expect(!Self.report(keepAwake: false).text.contains("also while"))
    }

    @Test func folderRowsAreFixedNamesNumberedWhenTheyRepeat() {
        let t = Self.report(folders: [.init(name: "~/.claude", installed: true), .init(name: "~/.config/claude", installed: true),
                                      .init(name: "~/.claude-acmebank", installed: true, hooksDisabled: true), .init(name: "~/.claude-b", installed: false),
                                      .init(name: "/Volumes/Work/claude-config", installed: true), .init(name: "~/work/acme-bank/.claude", installed: true),
                                      .init(name: "~/.claude/../work", installed: false), .init(name: "~/.claude-x/sub", installed: false)]).text
        #expect(t.contains("""
        Status line entry in ~/.claude: set up
        Status line entry in ~/.config/claude: set up
        Status line entry in ~/.claude-(name): set up, disableAllHooks is on
        Status line entry in ~/.claude-(name) 2: not set up
        Status line entry in other folder: set up
        Status line entry in other folder 2: set up
        Status line entry in other folder 3: not set up
        Status line entry in other folder 4: not set up
        """))
        #expect(Self.leaks(t, ["acme", "Volumes", "work", "sub"]).isEmpty)
    }

    @Test func noFolderAndNoDataAreSaidPlainly() {
        var r = Self.report(folders: [])
        r.lastData = nil
        #expect(r.text.contains("Status line entry: no settings folder found"))
        #expect(r.text.contains("Last status line data: none read since the app started"))
    }

    @Test func aDomainThatIsNotAnIdentifierIsNotPrinted() {
        for d in ["/Users/someone/acme-bank", "Client Work", "acme “bank”", String(repeating: "a", count: 70), "domain\nacme"] {
            #expect(ErrorCode(domain: d, code: 1).domain == "other domain")
        }
        #expect(ErrorCode(domain: "SMAppServiceErrorDomain", code: 1).text == "SMAppServiceErrorDomain 1")
        #expect(ErrorCode(domain: "Feed.SettingsFile.MissingFolder", code: 1).domain == "Feed.SettingsFile.MissingFolder")
    }

    @Test func thePosixErrnoIsFoundUnderNestedErrors() {
        let e = NSError(domain: "A", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: "B", code: 2, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 28)])])
        #expect(ErrorCode(e).text == "A 1, POSIX 28 ENOSPC")
        #expect(ErrorCode(NSError(domain: NSPOSIXErrorDomain, code: 99)).text == "POSIX 99")
    }

    @Test func theUserNameIsCheckedInTheSystemFields() {
        let t = Self.report(userNames: ["zoe", "Zoë Muster-Bank"], version: "0.1.17 zoe Muster-Bank").text
        #expect(t.contains("tokenpanda 0.1.17 (user) (user)"))
        // NFD in the text, NFC in the name, and the other way round
        let nfd = ProblemReport.hideUser("hi Zoe\u{0308} there", names: ["Zoë"])
        #expect(nfd == "hi (user) there")
        let nfc = ProblemReport.hideUser("hi Zoë there", names: ["Zoe\u{0308}"])
        #expect(nfc == "hi (user) there")
        // a part of one character is not a name to hide
        #expect(ProblemReport.hideUser("Mac model a", names: ["a"]) == "Mac model a")
    }

    @Test func aNameThatIsAlsoAFixedWordLeavesTheReportAlone() {
        // third review of 1e22148: the guard ran over the joined text, so "List price equivalent" read "List (user) equivalent"
        // for a user named Price, which gave the name away
        let f = [Fault(.statusLine, .install, step: .readSettings, code: ErrorCode(domain: NSCocoaErrorDomain, code: 13, posix: 13))]
        let plain = Self.report(faults: f).text
        for names in [["Price"], ["Read"], ["Mac"], ["In"], ["13"], ["in", "Mac In Status 13 Open Price Read Line Keep Last"]] {
            #expect(Self.report(faults: f, userNames: names).text == plain, "names \(names)")
        }
    }

    @Test func aDomainThatIsTheUserNameIsNotPrinted() {
        let f = [Fault(.openAtLogin, .register, code: ErrorCode(domain: "Zoe", code: 1))]
        let t = Self.report(faults: f, userNames: ["zoe"]).text
        #expect(t.contains("Open at login: could not register (other domain 1)"))
        #expect(!t.lowercased().contains("zoe"))
        // a domain that only holds a name part inside a longer word is a different word
        #expect(Self.report(faults: [Fault(.openAtLogin, .register, code: ErrorCode(domain: "Zoetrope", code: 1))], userNames: ["zoe"])
                .text.contains("(Zoetrope 1)"))
    }

    @Test func aFolderNameWithANewlineIsReadTrimmed() {
        #expect(ProblemReport.folderNames(["~/.claude\n", "~/.claude-acme\n", "~/.claude-a\nb"]) == ["~/.claude", "~/.claude-(name)", "other folder"])
    }

    @Test func errorsShownAreOnlyWhatTheAppShows() {
        let hook = Fault(.statusLine, .install)
        let tr = ReportFaults.transcripts(NSError(domain: NSPOSIXErrorDomain, code: 1))
        // the transcripts error shows only while no token figures are in
        #expect(ReportFaults.shown(hook: nil, login: nil, removeScript: nil, formatChanged: false, transcriptsError: true, tokensIn: true,
                                   transcripts: tr, processError: false, macWarning: false).isEmpty)
        #expect(ReportFaults.shown(hook: nil, login: nil, removeScript: nil, formatChanged: false, transcriptsError: true, tokensIn: false,
                                   transcripts: tr, processError: false, macWarning: false) == [tr])
        // no error held: nothing listed; a cleared hook error (faults.hook nil) is not listed
        #expect(ReportFaults.shown(hook: nil, login: nil, removeScript: nil, formatChanged: false, transcriptsError: false, tokensIn: false,
                                   transcripts: nil, processError: false, macWarning: false).isEmpty)
        #expect(ReportFaults.shown(hook: hook, login: nil, removeScript: nil, formatChanged: true, transcriptsError: false, tokensIn: false,
                                   transcripts: nil, processError: true, macWarning: true)
                == [hook, ReportFaults.feedFormat, ReportFaults.processList, ReportFaults.macWarning])
    }

    @Test func inFolderAroundAnotherErrorKeepsItsCodes() {
        #expect(ReportFaults.hook(install: true, HookError.inFolder("~/acme", POSIXError(.EACCES)))
                == Fault(.statusLine, .install, code: ErrorCode(domain: NSPOSIXErrorDomain, code: 13, posix: 13)))
    }

    @Test func theReportGoesOntoThePasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("dev.tokenpanda.test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.setString("old", forType: .string)
        #expect(ReportClipboard.write("tokenpanda problem report\n", to: pb))
        #expect(pb.string(forType: .string) == "tokenpanda problem report\n")
    }

    @Test func systemStringsAreKeptPlain() {
        #expect(ProblemReport.plain("26.1 (25B78)") == "26.1 (25B78)")
        #expect(ProblemReport.plain("/Users/someone/“acme”\n") == "Userssomeoneacme")
        #expect(ProblemReport.plain("") == "unknown")
    }

    @Test func theRowSaysCopiedOnlyAfterAClick() {
        let before = Grammar.reportRow(copied: nil).map(\.plain)
        let after = Grammar.reportRow(copied: true).map(\.plain)
        #expect(before.first == " \u{29C9} Copy a problem report")
        #expect(!before.contains { $0.contains(Grammar.reportCopied) })
        #expect(after.last == "     copied")
        // the help line is said once, as the button's help, not again as text
        let help = Grammar.reportRow(copied: nil).dropFirst()
        #expect(help.allSatisfy { $0.hidden })
    }

    @Test func theRowSaysWhenTheClipboardRefused() {
        #expect(Grammar.reportRow(copied: false).last?.plain == "     could not copy")
        #expect(!Grammar.reportRow(copied: false).contains { $0.plain.contains("     copied") })
    }

    // MARK: the Controller's mapping, ReportFaults

    @Test func hookErrorsMapToFixedStepsAndReasons() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSFilePathErrorKey: "/Users/someone/acme/.claude/settings.json",
                                                                               NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13)])
        #expect(ReportFaults.hook(install: true, HookError.cannotWriteSettings("x", cause: denied))
                == Fault(.statusLine, .install, step: .writeSettings, code: ErrorCode(domain: NSCocoaErrorDomain, code: 513, posix: 13)))
        #expect(ReportFaults.hook(install: false, HookError.cannotReadSettings("settings.json is over 1 MB"))
                == Fault(.statusLine, .remove, step: .readSettings, reason: .tooLarge))
        #expect(ReportFaults.hook(install: true, HookError.inFolder("~/Client Work/acme", HookError.cannotWriteScript("y", cause: denied)))
                == Fault(.statusLine, .install, step: .writeScript, code: ErrorCode(domain: NSCocoaErrorDomain, code: 513, posix: 13)))
        #expect(ReportFaults.hook(install: true, NSError(domain: NSPOSIXErrorDomain, code: 30))
                == Fault(.statusLine, .install, code: ErrorCode(domain: NSPOSIXErrorDomain, code: 30, posix: 30)))
        #expect(ReportFaults.hook(install: true, HookError.cannotReadSettings("whatever /Users/someone/acme"))
                == Fault(.statusLine, .install, step: .readSettings))
    }

    @Test func aLinkIntoAMissingFolderIsSaidAsSuch() throws {
        let dir = TestTemp.root.appendingPathComponent("tp-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(atPath: settings.path, withDestinationPath: dir.appendingPathComponent("gone/acme/settings.json").path)
        let hook = Hook(settingsURL: settings, dataDir: dir.appendingPathComponent("data"))
        do { _ = try hook.install(); Issue.record("install should refuse") } catch {
            #expect(ReportFaults.hook(install: true, error) == Fault(.statusLine, .install, step: .writeSettings, reason: .linkToMissingFolder))
        }
    }

    // MARK: every leak case of both reviews, as real errors through the real mapping

    /// The leak strings of the reviews of c59da93 and 00b5982.
    static let leakTexts: [String] = [
        "cannot write /Users/someone/Client Work/acme/.claude/settings.json", "/Volumes/Data/Acme Corp/x",
        "~/Client Work/acme-bank/.claude: cannot read",
        "You don’t have permission to save the file “settings.json” in the folder “acme-bank”.",
        "“settings.json” couldn’t be removed because you don’t have permission to access “acme-bank”.",
        "The file “-Users-someone-acme-bank” couldn’t be opened.", "~/.claude/projects;-Users-someone-acme",
        "~/.claude/../work/acme-bank/x", "~/.claudeX/../../secret-proj/x", "~/Code/acme,inc/x.swift",
        "3F2B8C1E9A4D4E7BB1C20D9E8F7A6B5C", "session payroll-fix (3f2b8c1e-9a4d-4e7b-b1c2-0d9e8f7a6b5c) could not reopen",
        "/Users/someone and /Users/someone/Client Work/acme: denied", "cannot read /Users/someone /Volumes/AcmeDisk/x",
        "home ~ then /Volumes/Secret/acme-bank/x: denied", "cannot write /Users/someone/Client:Acme/settings.json",
        "cannot write /Users/someone/Bob’s Acme Files/x.json", "x/Users/someone/acme-bank: denied", "--dir-/Users/someone/acme-bank: denied",
        "Operation not permitted for user someone", "user zoe\u{0308}", "~/.claude-acmebank: cannot write settings.json",
        "the folder “.claude-acmebank” is locked", "/Users/someone/.claude/agents/acme-deploy.md: denied", ".claude/plans/payroll-migration.md",
        "-System-Volumes-Data-Users-bob-acme-bank", "projects/-tmp-acme-bank/s.jsonl", "the folder -opt-acme-bank is gone", "x_-Users-bob-acme",
        "/Users/someone/acme-old: denied", "/Users/someone/work then Secret Plans: denied", "/Users/someone/acme\nsecretproj/x.json",
        "Sa\u{0308}ntis", "payroll  fix", "the folder “acme-bank couldn’t be opened", "«acme-bank»", "„acme-bank“",
        "cannot open acme-bank/src/main.swift", "file:///Users/someone/Client%20Work/acme/x", "/private/var/folders/xx/acme/T",
        "/System/Volumes/Data/Users/someone/acme", "/var/folders/acme", "-Users-someone-acme",
    ]
    static let leakWords = ["someone", "acme", "Acme", "secret", "Secret", "payroll", "Client", "Bob", "bob", "zoe", "Säntis", "work", "Code", "inc", "Plans", "3F2B8C1E", "3f2b8c1e"]

    /// Errors of every kind the app meets, each carrying the text in every field an error has.
    static func errors(carrying s: String) -> [any Error] {
        let info: [String: Any] = [NSLocalizedDescriptionKey: s, NSFilePathErrorKey: s, NSLocalizedFailureReasonErrorKey: s,
                                   NSURLErrorKey: URL(fileURLWithPath: s), NSUnderlyingErrorKey: NSError(domain: s, code: 13, userInfo: [NSLocalizedDescriptionKey: s])]
        let ns = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: info)
        let odd = NSError(domain: s, code: 1, userInfo: info)
        return [ns, odd, HookError.cannotWriteSettings(s, cause: ns), HookError.cannotWriteScript(s, cause: odd), HookError.cannotReadSettings(s),
                HookError.inFolder(s, HookError.cannotWriteSettings(s, cause: ns)), HookError.inFolder(s, odd)]
    }

    static func fullReport(carrying s: String, folder: String) -> String {
        var faults: [Fault] = []
        for e in errors(carrying: s) {
            faults += [ReportFaults.hook(install: true, e), ReportFaults.hook(install: false, e), ReportFaults.removeScript(e),
                       ReportFaults.login(on: true, e), ReportFaults.transcripts(e)]
        }
        return report(faults: faults, folders: [.init(name: folder, installed: true)], userNames: ["someone", "Zoë Muster"]).text
    }

    static func leaks(_ t: String, _ words: [String]) -> [String] {
        let n = t.precomposedStringWithCanonicalMapping
        return words.filter { n.localizedCaseInsensitiveContains($0.precomposedStringWithCanonicalMapping) }
    }

    @Test func noLeakCaseOfEitherReviewShows() {
        for s in Self.leakTexts {
            let t = Self.fullReport(carrying: s, folder: s)
            #expect(Self.leaks(t, Self.leakWords).isEmpty, "\(s) gave \(t)")
        }
    }

    /// Every user name, project name and shape, all of them (no random draw): neither name may show anywhere.
    @Test func noUserOrProjectNameEverShows() {
        let users = ["someone", "jane.doe", "Ann-Marie", "zoë"], projects = ["acme-bank", "Client Work", "payroll_v2", "x,y", "Säntis"]
        let shapes: [(String, String) -> String] = [
            { u, p in "/Users/\(u)/\(p)/main.swift" }, { u, p in "/Users/\(u)/Code/\(p)" }, { _, p in "/Volumes/\(p)/data" },
            { u, p in "file:///Users/\(u)/\(p)/a.txt" }, { u, p in "/Users/\(u)/.claude/projects/-Users-\(u)-\(p)/s.jsonl" },
            { _, p in "the folder “\(p)”" }, { u, p in "-Users-\(u)-\(p.replacingOccurrences(of: " ", with: "-"))" },
            { u, p in "/Users/\(u)/.claude/../\(p)/x" }, { _, p in "~/\(p)/x" }, { _, p in "/private/var/folders/\(p)/T" },
        ]
        for u in users {
            for p in projects {
                for shape in shapes {
                    let s = "Could not install the entry: " + shape(u, p) + ": denied"
                    let t = Self.fullReport(carrying: s, folder: "~/" + p)
                    let words = p.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 } + [u]
                    #expect(Self.leaks(t, words).isEmpty, "\(s) gave \(t)")
                }
            }
        }
    }
}
