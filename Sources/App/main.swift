// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import AppKit
import Text
import UI
import Transcripts
import MacStats
import ServiceManagement
import Feed

// Entry point of tokenpanda. Debug builds also take four flags that print or render and exit:
//   tokenpanda --snapshot <dir> [--snapshot-stage white]   every tab and state of the sample data to PNG through the view's bitmap
//   tokenpanda --read-transcripts       one full pass over the transcripts: counts and seconds
//   tokenpanda --sample-mac <rounds>    the Mac sampler alone at 2 s, its own CPU time
//   tokenpanda --login-item on|off|status   the Open at login row's own calls, from inside an app bundle; prints the system's status
// Release builds contain none of them.

// tokenpanda --remove-status-line: Remove, as the Settings row does, in every settings folder, then exit. The cask's
// zap runs it before it trashes the data folder, so settings.json never points at a deleted script. In release builds too.
if CommandLine.arguments.contains("--remove-status-line") {
    MainActor.assumeIsolated {
        let hook = HookSet(folders: ConfigFolders.find(), dataDir: Paths.dataDir)
        let had = zip(hook.hooks, hook.targets).filter { h, _ in let st = h.status(); return st.installed || st.scriptMissing }.map(\.1)
        do {
            try Controller.removeEverywhere(hook)
            print(had.isEmpty ? "tokenpanda: no status line entry of tokenpanda's found"
                              : "tokenpanda: status line entry removed from " + had.joined(separator: ", "))
        } catch {
            print("tokenpanda: " + ((error as? HookError)?.description ?? error.localizedDescription))
            exit(1)
        }
    }
    exit(0)
}

#if DEBUG
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        // --snapshot-stage white: the tint over white, the brightest desktop the glass can sit on, for the contrast check
        if let j = args.firstIndex(of: "--snapshot-stage"), j + 1 < args.count, args[j + 1] == "white" { LineView.stageOverride = Tokens.white }
        // --snapshot-light: the light palette over the light stage
        if args.contains("--snapshot-light") { LineView.lightOverride = true }
        var written: [String] = []
        for (name, input) in Fixtures.all() {
            let url = dir.appendingPathComponent(name + ".png")
            do { try SnapshotWriter.writeScreen(ScreenBuilder.screen(input), to: url); written.append(name) } catch { print("failed \(name): \(error)") }
        }
        let items: [(String, ItemState)] = [
            ("closed", ScreenBuilder.item(Fixtures.input(weekly: 61))),
            ("item-ahead", ScreenBuilder.item(Fixtures.input(weekly: 45))),
            ("item-stale", ScreenBuilder.item(Fixtures.input(weekly: 61, stale: true))),
            ("item-warning", ScreenBuilder.item(Fixtures.input(weekly: 61, warn: true))),
            ("item-nofeed", ScreenBuilder.item(Fixtures.input(feedState: .init()))),
            ("item-weekly-limit", ScreenBuilder.item(Fixtures.input(weekly: 100))),
            ("item-five-limit", ScreenBuilder.item(Fixtures.input(feedState: .init(limits: Fixtures.limits(weekly: 61, five: 100), sessions: Fixtures.openSessions,
                                                                                   lastWriteAt: Fixtures.now.addingTimeInterval(-2))))),
        ]
        for (name, st) in items {
            do { try SnapshotWriter.writeItem(st, to: dir.appendingPathComponent(name + ".png")); written.append(name) } catch { print("failed \(name): \(error)") }
        }
        print("wrote \(written.count) PNGs to \(dir.path)")
    }
    exit(0)
}

if let i = args.firstIndex(of: "--login-item"), i + 1 < args.count {
    MainActor.assumeIsolated {
        print("before \(Controller.loginStatus())  raw \(SMAppService.mainApp.status.rawValue)  bundle \(Bundle.main.bundlePath)")
        let what = args[i + 1]
        if what == "on" || what == "off" {
            print(Controller.setLogin(on: what == "on")?.message ?? "no error")
            print("after \(Controller.loginStatus())  raw \(SMAppService.mainApp.status.rawValue)")
        }
    }
    exit(0)
}

if args.contains("--read-transcripts") {
    // one full pass over the transcripts, counts and time, then exit (no UI)
    let t0 = Date()
    let store = TranscriptStore(roots: TranscriptLocator.roots())
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let r = await store.refresh()
        let s = Aggregator.summarize(r.records)
        print("files \(r.fileCount) records \(r.records.count) tokens7d \(s.tokens7d) tokens30d \(s.tokens30d) error \(r.error ?? "none") in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
        sem.signal()
    }
    sem.wait()
    exit(0)
}

if let i = args.firstIndex(of: "--transcript-passes"), i + 1 < args.count, let rounds = Int(args[i + 1]) {
    // the open panel's transcript pass, rounds times every 2 s: refresh for changes, sum again when a record came,
    // as Controller.refreshTranscripts does; time per pass and the process' own CPU time, then exit (no UI, reads only)
    let selfCPU: @Sendable () -> Double = { var ru = rusage(); getrusage(RUSAGE_SELF, &ru); return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6 }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let store = TranscriptStore(roots: TranscriptLocator.roots())
        let first = await store.refresh()
        _ = Aggregator.summarize(first.records)
        var version = first.version, took: [Double] = [], summed = 0
        let wall0 = Date(), cpu0 = selfCPU()
        for _ in 0..<rounds {
            let t = Date()
            let r = await store.refresh(onlyIfChanged: true)
            if r.version != version { version = r.version; _ = Aggregator.summarize(r.records); summed += 1 }
            took.append(Date().timeIntervalSince(t) * 1000)
            try? await Task.sleep(for: .seconds(2))
        }
        let wall = Date().timeIntervalSince(wall0), cpu = selfCPU() - cpu0
        print(String(format: "files %d records %d: %d passes, %d summed, pass %.1f ms average, %.1f ms longest; CPU %.3f s in %.1f s = %.2f%% of one core",
                     first.fileCount, first.records.count, rounds, summed, took.reduce(0, +) / Double(max(1, took.count)), took.max() ?? 0, cpu, wall, 100 * cpu / wall))
        sem.signal()
    }
    sem.wait()
    exit(0)
}

if let i = args.firstIndex(of: "--sample-mac"), i + 1 < args.count, let rounds = Int(args[i + 1]) {
    // the Mac sampler alone, every 2 s, its own CPU time by getrusage, then exit
    let selfCPU: @Sendable () -> Double = { var ru = rusage(); getrusage(RUSAGE_SELF, &ru); return Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6 + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6 }
    let sem = DispatchSemaphore(value: 0)
    Task.detached {
        let sampler = MacSampler()
        let wall0 = Date(), cpu0 = selfCPU()
        for r in 0..<rounds {
            let t = Date()
            let s = await sampler.sample(full: true, readHealth: true)
            let took = Date().timeIntervalSince(t)
            let health = s.battery?.health.map { "\($0)" } ?? "none"
            if r == 0 || r == rounds - 1 { print("round \(r): cpu \(Int(s.cpuBusy))% gpu \(s.gpuUtilisation ?? -1) health \(health) procs \(s.processes.count) total \(Int(s.processTotalCPU)) \(String(format: "%.1f", took * 1000)) ms") }
            try? await Task.sleep(for: .seconds(max(0, 2 - took)))
        }
        let wall = Date().timeIntervalSince(wall0), cpu = selfCPU() - cpu0
        print(String(format: "sampling every 2 s for %.1f s: process CPU time %.3f s = %.2f%% of one core", wall, cpu, 100 * cpu / wall))
        sem.signal()
    }
    sem.wait()
    exit(0)
}
#endif

// the battery's tool never outlives the app
NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in BatteryHealthReader.stopRunning() }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.delegate = controller
app.run()
