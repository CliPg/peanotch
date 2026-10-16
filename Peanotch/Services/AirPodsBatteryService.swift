import Combine
import Foundation

/// AirPods battery (left / right / case) parsed from the system Bluetooth
/// preference plist — the same source Sapphire reads. Works without any
/// Bluetooth permission prompt; values are fresh while the AirPods are
/// connected to this Mac.
final class AirPodsBatteryService: ObservableObject {
    struct AirPods: Equatable {
        var name: String
        var left: Int?
        var right: Int?
        var caseBattery: Int?
        var single: Int?
    }

    @Published var device: AirPods?

    private static let plistPath = "/Library/Preferences/com.apple.Bluetooth.plist"
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let next = parse()
        DispatchQueue.main.async {
            if self.device != next {
                self.device = next
            }
        }
    }

    private func parse() -> AirPods? {
        guard let data = FileManager.default.contents(atPath: Self.plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let cache = plist["DeviceCache"] as? [String: [String: Any]] else {
            return nil
        }

        for (_, info) in cache {
            let name = info["Name"] as? String ?? ""
            let left = intValue(info["BatteryPercentLeft"])
            let right = intValue(info["BatteryPercentRight"])
            let caseBattery = intValue(info["BatteryPercentCase"])
            let single = intValue(info["BatteryPercentSingle"]) ?? intValue(info["BatteryPercent"])

            let looksLikeAirPods = name.localizedCaseInsensitiveContains("AirPods")
                || left != nil || right != nil || caseBattery != nil
            guard looksLikeAirPods, left != nil || right != nil || single != nil else { continue }

            return AirPods(name: name.isEmpty ? "AirPods" : name,
                           left: left, right: right,
                           caseBattery: caseBattery, single: single)
        }
        return nil
    }

    /// Plist numbers may surface as NSNumber or String.
    private func intValue(_ any: Any?) -> Int? {
        if let number = any as? NSNumber { return number.intValue }
        if let string = any as? String { return Int(string) }
        return nil
    }
}
