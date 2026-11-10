// SPDX-FileCopyrightText: 2026 tokenpanda
// SPDX-License-Identifier: MIT
import Foundation
import Darwin
import IOKit
import IOKit.ps

// Every call is a public Mach, sysctl, IOKit or libproc call made in process. No tool is spawned, no root, no entitlement.
// GPU utilisation depends on a key Apple does not document, and battery health on what system_profiler answers: shown when present, omitted when absent.

public struct ProcessSample: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double      // of one core, over the sampling interval
    public var footprint: UInt64       // bytes
    public init(pid: Int32, name: String, cpuPercent: Double, footprint: UInt64) { self.pid = pid; self.name = name; self.cpuPercent = cpuPercent; self.footprint = footprint }
}

public struct BatterySample: Sendable, Equatable {
    public var percent: Int
    public var charging: Bool
    public var charged: Bool
    public var onAC: Bool
    public var minutesToFull: Int?     // nil when unknown (65535 or 0 while not charging)
    public var minutesToEmpty: Int?
    public var adapterWatts: Int?
    public var watts: Double?          // voltage times amperage; negative when discharging
    public var cycles: Int?
    public var health: BatteryHealth?  // nil until macOS has answered, or when it does not (BatteryHealth.swift)
    public init(percent: Int, charging: Bool, charged: Bool, onAC: Bool, minutesToFull: Int?, minutesToEmpty: Int?, adapterWatts: Int?, watts: Double?, cycles: Int?, health: BatteryHealth?) {
        self.percent = percent; self.charging = charging; self.charged = charged; self.onAC = onAC; self.minutesToFull = minutesToFull
        self.minutesToEmpty = minutesToEmpty; self.adapterWatts = adapterWatts; self.watts = watts; self.cycles = cycles; self.health = health
    }
}

public struct MacSample: Sendable, Equatable {
    public var cpuBusy: Double
    public var cpuUser: Double
    public var cpuSystem: Double
    public var cores: Int
    public var gpuUtilisation: Int?
    public var memoryUsed: UInt64
    public var memoryTotal: UInt64
    public var pressureLevel: Int      // 1 normal, 2 warn, 4 critical
    public var swapUsed: UInt64
    public var battery: BatterySample?
    public var processes: [ProcessSample]   // the five busiest by CPU
    public var processTotalCPU: Double = 0  // every sampled process summed, in the same per core units: the CPU in use
    public var processError: String?
    public var hogPid: Int32?          // a process over 80% CPU in this sample
    public init(cpuBusy: Double, cpuUser: Double, cpuSystem: Double, cores: Int, gpuUtilisation: Int?, memoryUsed: UInt64, memoryTotal: UInt64,
                pressureLevel: Int, swapUsed: UInt64, battery: BatterySample?, processes: [ProcessSample], processError: String?, hogPid: Int32?) {
        self.cpuBusy = cpuBusy; self.cpuUser = cpuUser; self.cpuSystem = cpuSystem; self.cores = cores; self.gpuUtilisation = gpuUtilisation
        self.memoryUsed = memoryUsed; self.memoryTotal = memoryTotal; self.pressureLevel = pressureLevel; self.swapUsed = swapUsed
        self.battery = battery; self.processes = processes; self.processError = processError; self.hogPid = hogPid
    }

    public var pressureWord: String {
        switch pressureLevel { case 2: return "warn"; case 4: return "critical"; default: return "normal" }
    }
}

/// The outcome of a read that ran; word nil means it gave no answer.
public struct HealthRead: Sendable, Equatable {
    public let word: BatteryHealth?
}

public actor MacSampler {
    public static let hogThreshold = 80.0
    var previousTicks: [UInt32]? = nil   // per core: user, system, idle, nice
    var previousProc: [Int32: (UInt64, Date)] = [:]
    var lastSampleAt: Date? = nil
    var healthCache = BatteryHealthCache()
    var healthRead: Task<Void, Never>? = nil   // the one read in flight; never on this actor, so a slow tool never holds a sample
    let healthReader: @Sendable () -> Data?
    let powerSource: @Sendable () -> BatterySample?
    let clock: @Sendable () -> ContinuousClock.Instant
    let cores: Int
    let ticksToNanos: Double   // rusage times are Mach absolute time ticks, not nanoseconds

    public init(healthReader: @escaping @Sendable () -> Data? = BatteryHealthReader.runTool,
                powerSource: @escaping @Sendable () -> BatterySample? = MacSampler.readPower,
                clock: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.healthReader = healthReader
        self.powerSource = powerSource
        self.clock = clock
        var n: Int32 = 0; var len = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &n, &len, nil, 0)
        cores = Int(max(n, 1))
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        ticksToNanos = tb.denom == 0 ? 1 : Double(tb.numer) / Double(tb.denom)
    }

    /// full: the whole table (popover open). Otherwise CPU, pressure and one libproc pass for the warning rule.
    /// readHealth: the Mac tab shows, so the battery's word may be read; at most once an hour per launch, never without a
    /// battery. The sample never waits for it: it holds the last word, the next one holds the new word.
    /// The time is taken here, inside the actor: a call that waited its turn still measures its own interval.
    public func sample(full: Bool, readHealth: Bool = false, now: Date? = nil) -> MacSample {
        let now = now ?? Date()
        let cpu = sampleCPU()
        let (used, total, pressure, swap) = sampleMemory()
        let procs = sampleProcesses(now: now)
        var s = MacSample(cpuBusy: cpu.busy, cpuUser: cpu.user, cpuSystem: cpu.system, cores: cores, gpuUtilisation: nil,
                          memoryUsed: used, memoryTotal: total, pressureLevel: pressure, swapUsed: swap,
                          battery: nil, processes: procs.top, processError: procs.error, hogPid: procs.hog)
        s.processTotalCPU = procs.total
        if full {
            s.gpuUtilisation = sampleGPU()
            s.battery = sampleBattery(readHealth: readHealth)
        }
        lastSampleAt = now
        return s
    }

    // MARK: CPU, host_processor_info tick deltas

    func sampleCPU() -> (busy: Double, user: Double, system: Double) {
        var ncpu: natural_t = 0
        var info: processor_info_array_t? = nil
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) == KERN_SUCCESS, let info else {
            return (0, 0, 0)
        }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.size)) }
        let states = Int(CPU_STATE_MAX)
        var ticks: [UInt32] = []
        ticks.reserveCapacity(Int(ncpu) * states)
        for i in 0..<Int(ncpu) * states { ticks.append(UInt32(bitPattern: info[i])) }
        defer { previousTicks = ticks }
        guard let prev = previousTicks, prev.count == ticks.count else { return (0, 0, 0) }
        var user = 0.0, sys = 0.0, total = 0.0
        for c in 0..<Int(ncpu) {
            let base = c * states
            let du = Double(ticks[base + Int(CPU_STATE_USER)] &- prev[base + Int(CPU_STATE_USER)])
            let ds = Double(ticks[base + Int(CPU_STATE_SYSTEM)] &- prev[base + Int(CPU_STATE_SYSTEM)])
            let di = Double(ticks[base + Int(CPU_STATE_IDLE)] &- prev[base + Int(CPU_STATE_IDLE)])
            let dn = Double(ticks[base + Int(CPU_STATE_NICE)] &- prev[base + Int(CPU_STATE_NICE)])
            user += du + dn; sys += ds; total += du + ds + di + dn
        }
        guard total > 0 else { return (0, 0, 0) }
        return ((user + sys) / total * 100, user / total * 100, sys / total * 100)
    }

    // MARK: memory, host_statistics64, Activity Monitor style used

    func sampleMemory() -> (UInt64, UInt64, Int, UInt64) {
        var vm = vm_statistics64_data_t()
        var c = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c) }
        }
        var page: vm_size_t = 0
        host_page_size(mach_host_self(), &page)
        var memsize: UInt64 = 0; var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memsize, &len, nil, 0)
        var used: UInt64 = 0
        if kr == KERN_SUCCESS {
            let app = Int64(vm.internal_page_count) - Int64(vm.purgeable_count)
            let pages = max(app, 0) + Int64(vm.wire_count) + Int64(vm.compressor_page_count)
            used = UInt64(pages) * UInt64(page)
        }
        var lvl: Int32 = 1; var l1 = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &lvl, &l1, nil, 0)
        var sw = xsw_usage(); var l2 = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &sw, &l2, nil, 0)
        return (used, memsize, Int(lvl), sw.xsu_used)
    }

    // MARK: GPU, IOAccelerator PerformanceStatistics (undocumented key, best effort)

    func sampleGPU() -> Int? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var result: Int? = nil
        var e = IOIteratorNext(it)
        while e != 0 {
            var props: Unmanaged<CFMutableDictionary>? = nil
            if IORegistryEntryCreateCFProperties(e, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any], let ps = d["PerformanceStatistics"] as? [String: Any] {
                if let u = ps["Device Utilization %"] as? Int { result = u }
                else if let u = ps["GPU Activity(%)"] as? Int { result = u }
            }
            IOObjectRelease(e)
            e = IOIteratorNext(it)
        }
        return result
    }

    // MARK: battery, IOPowerSources plus the AppleSmartBattery registry entry

    func sampleBattery(readHealth: Bool) -> BatterySample? {
        guard var b = powerSource() else { return nil }
        if readHealth { startHealthRead() }
        b.health = healthCache.value
        return b
    }

    /// Waits for the word, so the Mac tab has it at once when it opens. Reads only if one is due; a Mac without a battery never
    /// does. nil when no read ran, so the caller changes nothing. Takes no sample: a second one right after the first would
    /// measure a few milliseconds, in which the app itself looks like the top process (review 09.11.2026).
    public func refreshHealth() async -> HealthRead? {
        if powerSource() != nil { startHealthRead() }
        guard let read = healthRead else { return nil }
        await read.value
        return HealthRead(word: healthCache.value)
    }

    func startHealthRead() {
        let now = clock()
        guard healthRead == nil, healthCache.due(now: now) else { return }
        healthCache.begin(now: now)
        let reader = healthReader
        healthRead = Task {
            let answer = await withCheckedContinuation { (done: CheckedContinuation<BatteryHealth?, Never>) in
                DispatchQueue.global(qos: .utility).async { done.resume(returning: reader().flatMap(BatteryHealthReader.parse)) }
            }
            healthCache.finish(answer)
            healthRead = nil
        }
    }

    @Sendable public static func readPower() -> BatterySample? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var out: BatterySample? = nil
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType, let pct = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let state = d[kIOPSPowerSourceStateKey] as? String
            var b = BatterySample(percent: pct, charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                                  charged: d[kIOPSIsChargedKey] as? Bool ?? false, onAC: state == kIOPSACPowerValue,
                                  minutesToFull: nil, minutesToEmpty: nil, adapterWatts: nil, watts: nil, cycles: nil, health: nil)
            if let t = d[kIOPSTimeToFullChargeKey] as? Int, t > 0, t != 65535 { b.minutesToFull = t }
            if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0, t != 65535 { b.minutesToEmpty = t }
            out = b
        }
        guard var b = out else { return nil }
        if let ad = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any], let w = ad[kIOPSPowerAdapterWattsKey] as? Int {
            b.adapterWatts = w
        }
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if entry != 0 {
            defer { IOObjectRelease(entry) }
            var props: Unmanaged<CFMutableDictionary>? = nil
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let d = props?.takeRetainedValue() as? [String: Any] {
                b.cycles = d["CycleCount"] as? Int
                if let v = d["Voltage"] as? Int, let a = d["Amperage"] as? Int {
                    let amps = Int64(Int32(truncatingIfNeeded: a))   // the registry stores a signed value in an unsigned slot
                    b.watts = Double(v) / 1000 * Double(amps) / 1000
                }
            }
        }
        return b
    }

    // MARK: processes, libproc rusage deltas between two samples

    func sampleProcesses(now: Date) -> (top: [ProcessSample], error: String?, hog: Int32?, total: Double) {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return ([], "proc_listallpids returned nothing", nil, 0) }
        var pids = [pid_t](repeating: 0, count: Int(n) * 2)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard got > 0 else { return ([], "proc_listallpids failed", nil, 0) }
        var next: [Int32: (UInt64, Date)] = [:]
        var samples: [ProcessSample] = []
        var ok = 0
        var ri = rusage_info_v6()
        for i in 0..<Int(got) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let r = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard r == 0 else { continue }
            ok += 1
            let cpuTime = ri.ri_user_time &+ ri.ri_system_time
            next[pid] = (cpuTime, now)
            guard let (prevTime, prevAt) = previousProc[pid], cpuTime >= prevTime else { continue }
            let wall = now.timeIntervalSince(prevAt)
            guard wall > 0 else { continue }
            let pct = Double(cpuTime - prevTime) * ticksToNanos / 1e9 / wall * 100
            samples.append(ProcessSample(pid: pid, name: "", cpuPercent: pct, footprint: ri.ri_phys_footprint))
        }
        previousProc = next
        guard ok > 0 else { return ([], "proc_pid_rusage failed for every process", nil, 0) }
        samples.sort { $0.cpuPercent > $1.cpuPercent }
        let hog = samples.first.flatMap { $0.cpuPercent > MacSampler.hogThreshold ? $0.pid : nil }
        var top = Array(samples.prefix(5))
        for i in top.indices { top[i].name = Self.name(of: top[i].pid) }
        return (top, nil, hog, samples.reduce(0) { $0 + $1.cpuPercent })
    }

    static func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let n = proc_name(pid, &buf, UInt32(buf.count))
        let short = n > 0 ? String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        var pathBuf = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)   // PROC_PIDPATHINFO_MAXSIZE
        let pn = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        let path = pn > 0 ? String(decoding: pathBuf.prefix(Int(pn)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        return displayName(procName: short, executablePath: path, argv0: argv0(of: pid)) ?? "pid \(pid)"
    }

    /// The name the process list shows. proc_name gives the file name of the executable after links resolve, which for
    /// Claude Code's native install is its version (~/.local/bin/claude links to ~/.local/share/claude/versions/2.1.317).
    /// So Claude Code is told by where its executable sits, a versions folder inside a claude folder, or by the command it
    /// was started as, claude; any other process keeps its proc_name.
    static func displayName(procName: String?, executablePath: String?, argv0: String?) -> String? {
        if let path = executablePath {
            let parts = path.split(separator: "/")
            if parts.count >= 3, parts[parts.count - 2] == "versions", parts[parts.count - 3] == "claude" { return "Claude Code" }
        }
        if let a = argv0, (a as NSString).lastPathComponent == "claude" { return "Claude Code" }
        if let n = procName, !n.isEmpty { return n }
        return executablePath.map { ($0 as NSString).lastPathComponent }
    }

    /// argv[0] from KERN_PROCARGS2: argc, the executable path, NUL padding, then the arguments. nil when it cannot be read
    /// (another user's process).
    static func argv0(of pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }
        return argv0(fromProcArgs: Array(buf.prefix(size)))
    }

    static func argv0(fromProcArgs buf: [UInt8]) -> String? {
        guard buf.count > 4 else { return nil }
        var i = 4
        while i < buf.count, buf[i] != 0 { i += 1 }     // executable path
        while i < buf.count, buf[i] == 0 { i += 1 }     // padding
        var j = i
        while j < buf.count, buf[j] != 0 { j += 1 }
        return j > i ? String(decoding: buf[i..<j], as: UTF8.self) : nil
    }
}
