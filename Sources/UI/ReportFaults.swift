// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
// The errors the app holds, turned into the problem report's fixed words (Text.Fault). Only codes leave an error here,
// never its description, file names or paths.
import AppKit
import Feed
import Text

public enum ReportFaults {
    /// Install or Remove of the status line entry failed.
    public static func hook(install: Bool, _ error: any Error) -> Fault {
        let verb: Fault.Verb = install ? .install : .remove
        let cause = (error as? HookError)?.cause
        switch (error as? HookError)?.inner {
        case .cannotReadSettings(let m)?:
            return Fault(.statusLine, verb, step: .readSettings, reason: readReason(m))
        case .cannotWriteSettings?:
            if let c = cause, SettingsFile.isMissingFolder(c) { return Fault(.statusLine, verb, step: .writeSettings, reason: .linkToMissingFolder) }
            return Fault(.statusLine, verb, step: .writeSettings, code: cause.map(ErrorCode.init))
        case .cannotWriteScript?:
            return Fault(.statusLine, verb, step: .writeScript, code: cause.map(ErrorCode.init))
        default:
            // not a HookError, or inFolder around another error (inner is nil then): the codes of the cause, never the wrapper's
            return Fault(.statusLine, verb, code: ErrorCode(cause ?? error))
        }
    }

    /// The four fixed texts Hook.unreadable says; anything else gets no reason.
    static func readReason(_ m: String) -> Fault.Reason? {
        if m.hasSuffix("is not valid JSON") { return .notJSON }
        if m.hasSuffix("is not a JSON object") { return .notObject }
        if m.hasSuffix("is over 1 MB") { return .tooLarge }
        if m.hasSuffix("is not a regular file") { return .notRegularFile }
        return nil
    }

    public static func removeScript(_ error: any Error) -> Fault { Fault(.removeScript, .write, code: ErrorCode(error)) }
    public static func login(on: Bool, _ error: any Error) -> Fault { Fault(.openAtLogin, on ? .register : .unregister, code: ErrorCode(error)) }
    public static func transcripts(_ error: (any Error)?) -> Fault { Fault(.transcripts, .read, code: error.map(ErrorCode.init)) }
    public static let processList = Fault(.processList, .read)
    public static let feedFormat = Fault(.feedFormat, .changed)
    public static let macWarning = Fault(.macWarning, .warning)

    /// The errors the app shows now, in the order Settings and the tabs show them. Only what is on screen: the session
    /// file scan error is never shown, so it is not here; the transcripts error shows only while no token figures are in
    /// (ScreenBuilder.tokensView), so it counts only then. "Errors shown" in the report stays true.
    public static func shown(hook: Fault?, login: Fault?, removeScript: Fault?, formatChanged: Bool, transcriptsError: Bool,
                             tokensIn: Bool, transcripts: Fault?, processError: Bool, macWarning warning: Bool) -> [Fault] {
        var out = [hook, login, removeScript].compactMap { $0 }
        if formatChanged { out.append(feedFormat) }
        if transcriptsError, !tokensIn { out.append(transcripts ?? Self.transcripts(nil)) }
        if processError { out.append(processList) }
        if warning { out.append(macWarning) }
        return out
    }
}

/// The report onto a pasteboard: cleared only to write it. Returns whether the write took.
public enum ReportClipboard {
    public static func write(_ text: String, to pb: NSPasteboard) -> Bool {
        pb.clearContents()
        return pb.writeObjects([text as NSString])
    }
}
