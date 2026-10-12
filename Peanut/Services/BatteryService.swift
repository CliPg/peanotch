import Combine
import Foundation
import IOKit.ps

/// Battery percentage/charging state from IOKit power sources, polled every 30s.
final class BatteryService: ObservableObject {
    @Published var level: Int?
    @Published var charging = false

    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let percentage = min(100, Int((Double(current) / Double(max) * 100).rounded()))
            DispatchQueue.main.async {
                self.level = percentage
                self.charging = isCharging || state == kIOPSACPowerValue
            }
            return
        }
    }
}
