import Combine
import CoreBluetooth
import Foundation

/// AirPods battery via CoreBluetooth (Sapphire's primary route): discover the
/// AirPods BLE peripheral, connect, and read the standard Battery service
/// (0x180F / 0x2A19). Requires Bluetooth permission on first use.
final class AirPodsBatteryService: NSObject, ObservableObject {
    struct AirPods: Equatable {
        var name: String
        var left: Int?
        var right: Int?
        var caseBattery: Int?
        var single: Int?
    }

    @Published var device: AirPods?

    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryLevelUUID = CBUUID(string: "2A19")

    private var manager: CBCentralManager?
    private var tracked: [(peripheral: CBPeripheral, name: String)] = []
    private var rescanTimer: Timer?

    func start() {
        let manager = CBCentralManager(delegate: self, queue: nil,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        self.manager = manager
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let manager = self.manager, manager.state == .poweredOn else { return }
            manager.scanForPeripherals(withServices: [Self.batteryServiceUUID],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }
}

extension AirPodsBatteryService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            if central.state == .unauthorized {
                Diagnostics.record("airpods: bluetooth permission denied")
            }
            return
        }
        central.scanForPeripherals(withServices: [Self.batteryServiceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? ""
        // AirPods / AirPods Pro / AirPods Max all carry "AirPods" in the name;
        // Beats siblings report a plain battery service too and are welcome.
        let isAirPods = name.localizedCaseInsensitiveContains("AirPods")
        let hasBatteryService = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .contains(Self.batteryServiceUUID) == true
        guard !name.isEmpty, isAirPods || hasBatteryService else { return }

        if !tracked.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            tracked.append((peripheral, name.isEmpty ? "AirPods" : name))
        }
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([Self.batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Reconnect next rescan cycle.
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
        let name = tracked.first(where: { $0.peripheral.identifier == peripheral.identifier })?.name ?? "AirPods"
        DispatchQueue.main.async {
            self.device = AirPods(name: name, left: nil, right: nil, caseBattery: nil, single: level)
            Diagnostics.record("airpods battery: \(name) \(level)%")
        }
    }
}
