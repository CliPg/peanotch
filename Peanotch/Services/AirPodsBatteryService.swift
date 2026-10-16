import Combine
import CoreBluetooth
import Foundation

/// AirPods battery from two merged sources:
///
/// 1. `system_profiler SPBluetoothDataType` (primary, proven on modern macOS
///    where the Bluetooth plist carries no battery data and the GATT battery
///    service is absent from CoreBluetooth's connected-peripheral database).
///    Parses Left/Right/Case levels; polled every 30s on a background queue.
/// 2. CoreBluetooth GATT 0x180F/0x2A19 reads of system-connected peripherals
///    (secondary; instant when the service is present).
final class AirPodsBatteryService: NSObject, ObservableObject {
    struct AirPods: Equatable {
        var name: String
        var left: Int?
        var right: Int?
        var caseBattery: Int?
        var single: Int?
    }

    @Published private(set) var device: AirPods?

    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")

    private var manager: CBCentralManager?
    private var ready: [UUID: CBPeripheral] = [:]
    private var connecting: Set<UUID> = []
    private var pollTimer: Timer?
    private var tick = 0
    private var coreBluetoothDevice: AirPods?

    func start() {
        let manager = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        self.manager = manager
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick += 1
            self?.pollCoreBluetooth()
            if (self?.tick ?? 0) % 3 == 1 {   // every ~30s
                self?.querySystemProfiler()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.querySystemProfiler()
        }
    }

    private func publish() {
        device = profilerDevice ?? coreBluetoothDevice
    }

    private var profilerDevice: AirPods? {
        didSet { publish() }
    }
}

// MARK: - system_profiler parsing

extension AirPodsBatteryService {
    private func querySystemProfiler() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                Diagnostics.record("airpods: system_profiler failed to launch")
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard !text.isEmpty else { return }
            self.parseSystemProfiler(text)
        }
    }

    private func parseSystemProfiler(_ text: String) {
        var currentDeviceName: String?
        var committedName: String?
        var left: Int?, right: Int?, caseLevel: Int?, single: Int?

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":"), !trimmed.contains("="), !trimmed.contains("Battery") {
                let candidate = String(trimmed.dropLast())
                if !candidate.isEmpty, candidate.count < 40 {
                    if left != nil || right != nil || single != nil {
                        // battery already captured for the previous device — stop at first hit
                        break
                    }
                    currentDeviceName = candidate
                }
            }
            if trimmed.hasPrefix("Left Battery Level:") { left = Self.percent(in: trimmed) }
            else if trimmed.hasPrefix("Right Battery Level:") { right = Self.percent(in: trimmed) }
            else if trimmed.hasPrefix("Case Battery Level:") { caseLevel = Self.percent(in: trimmed) }
            else if trimmed.hasPrefix("Battery Level:") { single = Self.percent(in: trimmed) }
        }

        guard left != nil || right != nil || single != nil else {
            DispatchQueue.main.async {
                if self.profilerDevice != nil {
                    self.profilerDevice = nil
                    Diagnostics.record("airpods: profiler found no battery devices")
                }
            }
            return
        }
        let name = committedName ?? currentDeviceName ?? "Bluetooth 耳机"
        let parsed = AirPods(name: name, left: left, right: right, caseBattery: caseLevel, single: single)
        DispatchQueue.main.async {
            self.profilerDevice = parsed
            Diagnostics.record("airpods battery (profiler): \(name) L=\(left.map(String.init) ?? "-") R=\(right.map(String.init) ?? "-") C=\(caseLevel.map(String.init) ?? "-")")
        }
    }

    private static func percent(in line: String) -> Int? {
        let digits = line.compactMap { $0.isNumber ? String($0) : nil }.joined()
        guard let value = Int(digits), (1...100).contains(value) else { return nil }
        return value
    }
}

// MARK: - CoreBluetooth (secondary)

extension AirPodsBatteryService: CBCentralManagerDelegate {
    private func pollCoreBluetooth() {
        guard let manager, manager.state == .poweredOn else { return }
        let connected = manager.retrieveConnectedPeripherals(withServices: [Self.batteryServiceUUID])
        for peripheral in connected {
            if let known = ready[peripheral.identifier] {
                if let service = known.services?.first(where: { $0.uuid == Self.batteryServiceUUID }),
                   let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelUUID }) {
                    known.readValue(for: characteristic)
                } else {
                    known.discoverServices([Self.batteryServiceUUID])
                }
            } else if !connecting.contains(peripheral.identifier) {
                connecting.insert(peripheral.identifier)
                manager.connect(peripheral, options: nil)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Diagnostics.record("airpods: bluetooth state = \(central.state.rawValue)")
        if central.state == .poweredOn {
            pollCoreBluetooth()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connecting.remove(peripheral.identifier)
        ready[peripheral.identifier] = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([Self.batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connecting.remove(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready[peripheral.identifier] = nil
        connecting.remove(peripheral.identifier)
    }
}

extension AirPodsBatteryService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.batteryServiceUUID }) else { return }
        peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelUUID }) else { return }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == Self.batteryLevelUUID,
              let data = characteristic.value, let first = data.first else { return }
        let level = Int(first)
        let name = peripheral.name ?? "Bluetooth 耳机"
        DispatchQueue.main.async {
            self.coreBluetoothDevice = AirPods(name: name, left: nil, right: nil, caseBattery: nil, single: level)
            self.publish()
        }
    }
}
