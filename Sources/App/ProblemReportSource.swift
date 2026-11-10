// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import Feed
import Text
import UI

/// The errors the Controller holds, in the problem report's fixed words. Set where each error is set, cleared with it.
struct FaultState {
    var hook: Fault?
    var removeScript: Fault?
    var login: Fault?
    var transcripts: Fault?
}

extension Controller {
    /// remove.sh: the dim line under the status line row says the error's text; the report keeps only its codes.
    func noteRemoveScript(_ error: (any Error)?) {
        removeScriptError = error?.localizedDescription
        faults.removeScript = error.map(ReportFaults.removeScript)
    }

    /// The click: the report on the clipboard, the dim line, and the same said to VoiceOver on every click, so a second
    /// click and a refusal are heard too (a changed dim line alone is not announced). The clipboard is cleared only to
    /// write the report: clearContents then writeObjects, the standard AppKit pattern. If the write is refused after the
    /// clear, the old clipboard is gone; that failure is very rare, and it is said as "could not copy".
    func copyProblemReport() {
        let ok = ReportClipboard.write(problemReport().text, to: .general)
        reportCopied = ok
        // After the render that follows the click: the rebuilt lines make VoiceOver read the button again, which cut an
        // announcement posted at once (heard on a real Mac, 09.11.2026). Posted on the panel's window, which outlives the lines.
        let said = ok ? Grammar.reportCopied : Grammar.reportFailed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let element: Any = self.lineView.window ?? self.lineView
            NSAccessibility.post(element: element, notification: .announcementRequested,
                                 userInfo: [.announcement: said, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// What "Copy a problem report" puts on the clipboard: the set agreed 05.11.2026, in fixed words (Text.ProblemReport).
    func problemReport() -> ProblemReport {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "").replacingOccurrences(of: "Build ", with: "")
        var size = 0
        var model = "unknown"
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 { model = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        }
        let folders = zip(hook.hooks, hook.targets).map { h, name in
            let st = h.status()
            return ProblemReport.Folder(name: name, installed: st.installed, scriptMissing: st.scriptMissing, hooksDisabled: st.hooksDisabled)
        }
        return ProblemReport(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, macOS: os, model: model,
                             openAtLogin: login, macInBar: Settings.bool(Settings.macFiguresInBar), nudges: Settings.bool(Settings.nudges),
                             listPrice: Settings.bool(Settings.listPriceEquivalent), keepAwake: Settings.bool(Settings.keepAwake),
                             keepAwakeWhileOpen: Settings.bool(Settings.keepAwakeWhileOpen), restoreSessions: Settings.bool(Settings.restoreSessions),
                             reopenApp: ReopenApp.current, folders: folders, lastData: feedState.lastWriteAt ?? feedState.limits?.asOf,
                             sessions: feedState.sessions.count, faults: shownFaults(),
                             userNames: [NSUserName(), NSFullUserName()])
    }

    /// One fault per error the app shows now (ReportFaults.shown has the rule and its tests).
    func shownFaults() -> [Fault] {
        ReportFaults.shown(hook: faults.hook, login: faults.login, removeScript: faults.removeScript, formatChanged: feedState.formatChanged,
                           transcriptsError: transcriptsError != nil, tokensIn: tokens != nil, transcripts: faults.transcripts,
                           processError: mac?.processError != nil, macWarning: warning)
    }
}
