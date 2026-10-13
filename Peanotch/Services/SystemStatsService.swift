import Combine
import Foundation
import IOKit

/// Real-time system stats: memory, disk, CPU usage (tick deltas), network
/// throughput (interface counter deltas) and battery health (IOKit).
/// Refreshed every 2 seconds.
final class SystemStatsService: ObservableObject {
    struct Snapshot: Equatable {
        var memoryUsedBytes: Int64 = 0
        var memoryTotalBytes: Int64 = 0
        var diskUsedBytes: Int64 = 0
        var diskTotalBytes: Int64 = 0
        var cpuUsage: Double = 0          // 0...1
        var netDownBytesPerSec: Int64 = 0
        var netUpBytesPerSec: Int64 = 0
        var batteryHealthPercent: Int = 0 // 0 = unknown
        var batteryCycleCount: Int = 0
    }

    @Published var snapshot = Snapshot()

    private var timer: Timer?
    private var previousCPUTicks: (total: UInt64, idle: UInt64)?
    private var previousNetCounters: (time: Date, input: UInt64, output: UInt64)?
    private var batteryHealth: (healthPercent: Int, cycleCount: Int) = (0, 0)

    func start() {
        batteryHealth = readBatteryHealth()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let memory = readMemory()
        let disk = readDisk()
        let cpu = sampleCPU()
        let net = sampleNetwork()
        let next = Snapshot(memoryUsedBytes: memory.used,
                            memoryTotalBytes: memory.total,
                            diskUsedBytes: disk.used,
                            diskTotalBytes: disk.total,
                            cpuUsage: cpu,
                            netDownBytesPerSec: net.down,
                            netUpBytesPerSec: net.up,
                            batteryHealthPercent: batteryHealth.healthPercent,
                            batteryCycleCount: batteryHealth.cycleCount)
        DispatchQueue.main.async { self.snapshot = next }
    }

    // MARK: - Memory

    /// Used = wired + active + compressor pages (Activity-Monitor-like).
    private func readMemory() -> (used: Int64, total: Int64) {
        var totalBytes: Int64 = 0
        var byteValue: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &byteValue, &size, nil, 0) == 0 {
            totalBytes = Int64(bitPattern: byteValue)
        }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, totalBytes)
        }
        let pageSize = Int64(vm_kernel_page_size)
        let used = (Int64(stats.wire_count) + Int64(stats.active_count) + Int64(stats.compressor_page_count)) * pageSize
        return (used, totalBytes)
    }

    // MARK: - Disk

    private func readDisk() -> (used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity,
           let free = values.volumeAvailableCapacity {
            return (Int64(total - free), Int64(total))
        }
        return (0, 0)
    }

    // MARK: - CPU (delta between consecutive samples)

    private func sampleCPU() -> Double {
        var numCPU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &cpuInfo, &numCPUInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
        }

        var total: UInt64 = 0
        var idle: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(numCPU) {
            let base = core * states
            for state in 0..<states {
                let ticks = UInt64(info[base + state])
                total += ticks
                if state == Int(CPU_STATE_IDLE) { idle += ticks }
            }
        }

        var usage: Double = 0
        if let previous = previousCPUTicks, total > previous.total {
            let totalDelta = total - previous.total
            let idleDelta = idle - previous.idle
            if totalDelta > 0 {
                usage = Double(totalDelta - idleDelta) / Double(totalDelta)
            }
        }
        previousCPUTicks = (total, idle)
        return min(1, max(0, usage))
    }

    // MARK: - Network throughput (interface counter deltas)

    private func sampleNetwork() -> (down: Int64, up: Int64) {
        let counters = readNetworkCounters()
        let now = Date()
        defer { previousNetCounters = (now, counters.input, counters.output) }
        guard let previous = previousNetCounters else { return (0, 0) }
        let seconds = max(0.5, now.timeIntervalSince(previous.time))
        let down = Int64(Double(counters.input >= previous.input ? counters.input - previous.input : 0) / seconds)
        let up = Int64(Double(counters.output >= previous.output ? counters.output - previous.output : 0) / seconds)
        return (down, up)
    }

    private func readNetworkCounters() -> (input: UInt64, output: UInt64) {
        var mib: [Int32] = [CTL_NET, AF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size: Int = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return (0, 0) }
        guard let raw = malloc(size) else { return (0, 0) }
        defer { free(raw) }
        guard sysctl(&mib, u_int(mib.count), raw, &size, nil, 0) == 0 else { return (0, 0) }

        let buffer = UnsafeMutableRawPointer(raw)
        var totalInput: UInt64 = 0
        var totalOutput: UInt64 = 0
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= size {
            let header = buffer.load(fromByteOffset: offset, as: if_msghdr.self)
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0 else { break }

            if header.ifm_type == RTM_IFINFO2,
               offset + MemoryLayout<if_msghdr2>.size <= size {
                let message = buffer.load(fromByteOffset: offset, as: if_msghdr2.self)
                let linkOffset = offset + MemoryLayout<if_msghdr2>.size
                if linkOffset + MemoryLayout<sockaddr_dl>.size <= size {
                    let link = buffer.load(fromByteOffset: linkOffset, as: sockaddr_dl.self)
                    let nameLength = Int(link.sdl_nlen)
                    var name = ""
                    if nameLength > 0,
                       linkOffset + MemoryLayout<sockaddr_dl>.size + nameLength <= size {
                        let nameBytes = UnsafeRawBufferPointer(start: buffer + linkOffset + MemoryLayout<sockaddr_dl>.size,
                                                               count: nameLength)
                        name = String(bytes: nameBytes, encoding: .utf8) ?? ""
                    }
                    if name != "lo0" {
                        totalInput += message.ifm_data.ifi_ibytes
                        totalOutput += message.ifm_data.ifi_obytes
                    }
                }
            }
            offset += messageLength
        }
        return (totalInput, totalOutput)
    }

    // MARK: - Battery health

    private func readBatteryHealth() -> (healthPercent: Int, cycleCount: Int) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return (0, 0) }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return (0, 0) }
        let maxCapacity = dictionary["MaxCapacity"] as? Int ?? 0
        let designCapacity = dictionary["DesignCapacity"] as? Int ?? 0
        let cycles = dictionary["CycleCount"] as? Int ?? 0
        let health = designCapacity > 0
            ? Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
            : 0
        return (health, cycles)
    }
}
