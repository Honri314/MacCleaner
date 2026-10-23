import Foundation
import Darwin
import Combine
import SwiftUI

struct ProcessStat: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryMB: Double
    var id: Int32 { pid }
}

struct MemorySnapshot: Hashable {
    let totalGB: Double
    let usedGB: Double
    var usedPercent: Double { totalGB > 0 ? min(usedGB / totalGB * 100, 100) : 0 }
    var pressureDescription: String {
        switch usedPercent {
        case ..<60: return "원활"
        case ..<85: return "보통"
        default: return "높음"
        }
    }
}

struct DiskSnapshot: Hashable {
    let totalGB: Double
    let freeGB: Double
    var usedPercent: Double { totalGB > 0 ? min((totalGB - freeGB) / totalGB * 100, 100) : 0 }
}

struct SystemSnapshot {
    var cpuPercent: Double = 0
    var memory = MemorySnapshot(totalGB: 0, usedGB: 0)
    var disk = DiskSnapshot(totalGB: 0, freeGB: 0)
    var topProcesses: [ProcessStat] = []
}

struct SampleState {
    var processTimes: [pid_t: UInt64] = [:]
    var cpuActive: UInt = 0
    var cpuTotal: UInt = 0
    var lastWallUs: UInt64 = 0
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    private var state = SampleState()
    private var loop: Task<Void, Never>?

    init() { start() }

    deinit { loop?.cancel() }

    private func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let (snap, newState) = await Self.sample(previous: self.state)
                self.state = newState
                self.snapshot = snap
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    static func terminate(pid: Int32) { kill(pid, SIGTERM) }

    // MARK: - 샘플링 (오프메인)

    nonisolated static func sample(previous: SampleState) async -> (SystemSnapshot, SampleState) {
        let (result, next) = await Task.detached(priority: .userInitiated) {
            Self.sampleSync(previous: previous)
        }.value
        return (result, next)
    }

    nonisolated private static func sampleSync(previous: SampleState) -> (SystemSnapshot, SampleState) {
        var next = SampleState()
        let nowUs = UInt64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW_APPROX))
        let intervalUs = previous.lastWallUs > 0 ? nowUs &- previous.lastWallUs : 0
        next.lastWallUs = nowUs

        var stats: [ProcessStat] = []
        let cpuNorm = Double(max(1, activeCoreCount()))

        let count = proc_listallpids(nil, 0)
        if count > 0 {
            var pids = [pid_t](repeating: 0, count: Int(count) + 16)
            let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            for pid in pids.prefix(Int(max(n, 0))) where pid != getpid() {
                guard let (totalUs, rsize) = taskStat(pid: pid) else { continue }
                let prevTicks = previous.processTimes[pid] ?? totalUs
                let deltaUs = totalUs > prevTicks ? totalUs - prevTicks : 0
                // 단일코어 기준 %를 코어 수로 정규화 → 0~100%
                var cpu = intervalUs > 0
                    ? (Double(deltaUs) / Double(intervalUs)) * 100 / cpuNorm
                    : 0
                cpu = min(cpu, 100)
                next.processTimes[pid] = totalUs
                let memMB = Double(rsize) / 1_048_576
                if cpu > 0.1 || memMB > 20 {
                    stats.append(ProcessStat(pid: pid, name: name(of: pid), cpuPercent: cpu, memoryMB: memMB))
                }
            }
        }

        // CPU 전체 사용률 (틱 차분)
        var cpuPercent = 0.0
        if let cur = cpuCounters() {
            next.cpuActive = cur.active
            next.cpuTotal = cur.total
            if previous.cpuTotal > 0, cur.total > previous.cpuTotal {
                let dActive = Double(next.cpuActive - previous.cpuActive)
                let dTotal = Double(next.cpuTotal - previous.cpuTotal)
                if dTotal > 0 { cpuPercent = max(0, min(dActive / dTotal * 100, 100)) }
            }
        }

        var snapshot = SystemSnapshot()
        snapshot.cpuPercent = cpuPercent
        snapshot.memory = memorySnapshot()
        snapshot.disk = diskSnapshot()
        snapshot.topProcesses = Array(stats.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(25))
        for p in stats.sorted(by: { $0.memoryMB > $1.memoryMB }).prefix(10) {
            if !snapshot.topProcesses.contains(where: { $0.pid == p.pid }) {
                snapshot.topProcesses.append(p)
            }
        }
        snapshot.topProcesses = Array(snapshot.topProcesses.prefix(30))
        return (snapshot, next)
    }

    nonisolated private static func activeCoreCount() -> Int {
        var n: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.activecpu", &n, &size, nil, 0)
        return max(Int(n), 1)
    }

    nonisolated private static func taskStat(pid: pid_t) -> (totalUs: UInt64, resident: UInt64)? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = withUnsafeMutableBytes(of: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, ptr.baseAddress, size)
        }
        guard result == size, info.pti_resident_size > 0 else { return nil }
        return (info.pti_total_user + info.pti_total_system, info.pti_resident_size)
    }

    nonisolated private static func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 2_048)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        if n > 0, let s = String(cString: buf, encoding: .utf8), !s.isEmpty { return s }
        return "PID \(pid)"
    }

    nonisolated private static func cpuCounters() -> (active: UInt, total: UInt)? {
        var stats = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let ticks = stats.cpu_ticks
        let user = UInt(ticks.0)
        let system = UInt(ticks.1)
        let idle = UInt(ticks.2)
        let nice = UInt(ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    nonisolated private static func memorySnapshot() -> MemorySnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)

        guard kr == KERN_SUCCESS else {
            return MemorySnapshot(totalGB: Double(totalBytes) / 1_073_741_824, usedGB: 0)
        }
        let active = UInt64(stats.active_count)
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let usedBytes = (active + wired + compressed) * UInt64(pageSize)
        return MemorySnapshot(totalGB: Double(totalBytes) / 1_073_741_824,
                              usedGB: Double(min(usedBytes, totalBytes)) / 1_073_741_824)
    }

    nonisolated private static func diskSnapshot() -> DiskSnapshot {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return DiskSnapshot(totalGB: 0, freeGB: 0) }
        let total = Double(UInt64(fs.f_blocks) * UInt64(fs.f_bsize)) / 1_073_741_824
        let free = Double(UInt64(fs.f_bavail) * UInt64(fs.f_bsize)) / 1_073_741_824
        return DiskSnapshot(totalGB: total, freeGB: free)
    }
}
