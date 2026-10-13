import Combine
import Foundation

/// Real-time system stats: memory pressure via Mach host statistics,
/// disk capacity via URL resource values. Refreshed every 5 seconds.
final class SystemStatsService: ObservableObject {
    struct Snapshot: Equatable {
        var memoryUsedBytes: Int64 = 0
        var memoryTotalBytes: Int64 = 0
        var diskUsedBytes: Int64 = 0
        var diskTotalBytes: Int64 = 0
    }

    @Published var snapshot = Snapshot()

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let memory = readMemory()
        let disk = readDisk()
        let next = Snapshot(memoryUsedBytes: memory.used,
                            memoryTotalBytes: memory.total,
                            diskUsedBytes: disk.used,
                            diskTotalBytes: disk.total)
        DispatchQueue.main.async { self.snapshot = next }
    }

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

    private func readDisk() -> (used: Int64, total: Int64) {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity,
           let free = values.volumeAvailableCapacity {
            return (Int64(total - free), Int64(total))
        }
        return (0, 0)
    }
}
