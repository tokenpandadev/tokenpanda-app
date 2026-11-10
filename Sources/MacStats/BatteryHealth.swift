// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Darwin
import Foundation

/// The battery's condition in one word, as macOS itself reports it. macOS 27 holds no usable capacity key in the registry
/// (NominalChargeCapacity over DesignCapacity read 83% where System Settings said 89%), so the word comes from Apple's own
/// system_profiler, and only the word: its output also holds the battery's serial number, which is never kept.
public enum BatteryHealth: Sendable, Equatable {
    case normal   // system_profiler says "Good" (the one word seen, macOS 27); "Normal" counts too, as System Settings words it, unseen from the tool
    case other    // any other word: the app does not interpret it, it points to System Settings
}

public enum BatteryHealthReader {
    static let tool = "/usr/sbin/system_profiler"
    static let limit = 1_048_576   // the real output is a few KB

    /// Takes one key from system_profiler's JSON and lets go of everything else.
    public static func parse(_ data: Data) -> BatteryHealth? {
        guard data.count <= limit,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            guard let info = item["sppower_battery_health_info"] as? [String: Any],
                  let word = info["sppower_battery_health"] as? String, !word.isEmpty else { continue }
            return word == "Good" || word == "Normal" ? .normal : .other
        }
        return nil
    }

    /// Which tab reads the word: the Mac tab, the only one that shows it.
    public static func mayRead(tab: Int) -> Bool { tab == 1 }

    /// A word that came after the Mac tab opened goes on screen only if the panel still shows that tab.
    public static func mayShow(panelShown: Bool, tab: Int) -> Bool { panelShown && mayRead(tab: tab) }

    /// The real read: Apple's tool for this one key. Whole limit 5 s: 3.9 s for the answer and the exit, 1 s to stop it, so the kill goes out inside the limit.
    @Sendable public static func runTool() -> Data? { run(tool: tool, arguments: ["SPPowerDataType", "-json"]) }
    static let answerSeconds = 3.9, stopSeconds = 1.0

    /// Runs a tool with no shell and the C locale. One deadline covers the answer and the exit together. nil on a failure,
    /// a timeout or too much output; a tool still running at the deadline is stopped.
    static func run(tool: String, arguments: [String], answerSeconds: Double = answerSeconds, stopSeconds: Double = stopSeconds,
                    tools: RunningTools = running) -> Data? {
        guard !tools.stopping else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.environment = ["LC_ALL": "C", "LANG": "C"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch {
            try? pipe.fileHandleForWriting.close()
            try? pipe.fileHandleForReading.close()
            return nil
        }
        // A quit between the start and this line finds nothing to stop, so the tool is stopped here instead.
        if !tools.add(process) { kill(process.processIdentifier, SIGKILL) }
        defer { tools.remove(process) }
        // Read on another thread, so a full pipe never holds the tool and the limit still holds.
        let reading = DispatchSemaphore(value: 0)
        let box = OutputBox()
        let handle = pipe.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            box.read(handle, limit: limit)
            try? handle.close()
            reading.signal()
        }
        let deadline = DispatchTime.now() + answerSeconds
        let answered = reading.wait(timeout: deadline) == .success
        let done = answered && !box.overflowed && exited.wait(timeout: deadline) == .success
        box.cancel()   // a child of the tool may still hold the pipe; the reading thread lets go of it within 0.1 s
        guard done else {
            stop(process, exited: exited, seconds: stopSeconds)
            return nil
        }
        guard process.terminationStatus == 0, !box.failed else { return nil }
        return box.data
    }

    static func stop(_ process: Process, exited: DispatchSemaphore, seconds: Double) {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + seconds) == .timedOut { kill(process.processIdentifier, SIGKILL) }
    }

    /// The tool at quit: never left behind.
    public static func stopRunning() { running.killAll() }
    static let running = RunningTools()
}

/// The tools that run at this moment, so a quit can stop them.
final class RunningTools: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var quitting = false
    var count: Int { lock.withLock { processes.count } }
    var stopping: Bool { lock.withLock { quitting } }
    /// false once a quit has begun: the caller stops its tool itself.
    func add(_ p: Process) -> Bool {
        lock.withLock {
            processes[ObjectIdentifier(p)] = p
            return !quitting
        }
    }
    func remove(_ p: Process) { lock.withLock { processes[ObjectIdentifier(p)] = nil } }
    func killAll() {
        let now = lock.withLock { () -> [Process] in
            quitting = true
            return Array(processes.values)
        }
        for p in now where p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }
}

/// The tool's output, handed from the reading thread once the semaphore says it is done. Polls, so a cancel ends the read
/// even while a child of the tool holds the pipe open.
private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var over = false
    private var error = false
    private var cancelled = false
    var data: Data { lock.withLock { bytes } }
    var overflowed: Bool { lock.withLock { over } }
    var failed: Bool { lock.withLock { error } }
    func cancel() { lock.withLock { cancelled = true } }

    func read(_ handle: FileHandle, limit: Int) {
        let fd = handle.fileDescriptor
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !lock.withLock({ cancelled }) {
            var wait = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&wait, 1, 100)
            if ready == 0 || (ready < 0 && errno == EINTR) { continue }
            if ready < 0 { lock.withLock { error = true }; return }
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n == 0 { return }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                lock.withLock { error = true }
                return
            }
            let full = lock.withLock { () -> Bool in
                bytes.append(contentsOf: buffer[0..<n])
                if bytes.count > limit { over = true; bytes = Data() }
                return over
            }
            if full { return }
        }
    }
}

/// The last answer and when its read began. At most one read an hour per launch, a failed one too, so a tool that does not
/// answer costs nothing. A read that fails drops the word: no answer leaves it out. Timed on the continuous clock: setting
/// the Mac's clock neither brings a read forward nor holds one back.
struct BatteryHealthCache {
    static let interval: Duration = .seconds(3600)
    private(set) var value: BatteryHealth?
    private(set) var readAt: ContinuousClock.Instant?

    func due(now: ContinuousClock.Instant) -> Bool { readAt.map { $0.duration(to: now) >= Self.interval } ?? true }
    mutating func begin(now: ContinuousClock.Instant) { readAt = now }
    mutating func finish(_ answer: BatteryHealth?) { value = answer }
}
