@preconcurrency import CoreBluetooth
import Foundation

/// The Bluetooth remote protocol Sony cameras share with the RMT-P1BT remote
/// commander (a6600, a7 and ZV models, among others). Sony hasn't published
/// it; this follows the community's reverse engineering (Greg Leeds,
/// freemote, furble).
enum SonyRemote {
    static let service = CBUUID(string: "8000FF00-FF00-FFFF-FFFF-FFFFFFFFFFFF")
    /// Button presses go here.
    static let command = CBUUID(string: "FF01")
    /// The camera says what it's doing here (focus, shutter, recording).
    static let status = CBUUID(string: "FF02")
    /// Sony's Bluetooth company ID, 0x012D, little endian.
    static let companyID: [UInt8] = [0x2D, 0x01]

    static let halfPress: [UInt8] = [0x01, 0x07]
    static let halfRelease: [UInt8] = [0x01, 0x06]
    static let fullPress: [UInt8] = [0x01, 0x09]
    static let fullRelease: [UInt8] = [0x01, 0x08]

    /// A full press and release of the shutter button, as the remote sends it.
    static let shutterClick = [halfPress, fullPress, fullRelease, halfRelease]

    /// Whether an advertisement's manufacturer data is a Sony camera's.
    static func isSonyCamera(manufacturerData data: Data?) -> Bool {
        guard let data, data.count >= 4 else { return false }
        // Company ID, then the product type: 0x0003 is a camera.
        return Array(data.prefix(2)) == companyID && data[data.startIndex + 2] == 0x03
    }
}

/// Fires a Sony camera's shutter over Bluetooth, the way its remote
/// commander does, so frames captured over HDMI also take a full-size
/// picture on the camera's card. One for the whole app: a camera takes one
/// remote at a time.
@MainActor
final class ShutterRemote: NSObject, ObservableObject {
    static let shared = ShutterRemote()

    enum State: Equatable {
        /// Not turned on yet; Bluetooth isn't touched until it is.
        case off
        case unavailable(String)
        /// Looking for a camera in pairing mode.
        case searching
        case connecting(String)
        case connected(String)
    }

    struct FoundCamera: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    @Published private(set) var state: State = .off
    /// Sony cameras seen while searching.
    @Published private(set) var found: [FoundCamera] = []
    /// When the camera last said its shutter fired.
    @Published private(set) var lastShutter: Date?
    /// Why the last shutter press didn't go through, if it didn't.
    @Published private(set) var problem: String?

    /// Fire the camera's shutter with every capture.
    @Published var isEnabled = UserDefaults.standard.bool(forKey: ShutterRemote.enabledKey) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if isEnabled { start() } else { stop() }
        }
    }

    var isConnected: Bool {
        if case .connected = state { true } else { false }
    }

    var savedCameraName: String? { UserDefaults.standard.string(forKey: Self.nameKey) }

    private static let enabledKey = "remoteShutterEnabled"
    private static let cameraKey = "remoteShutterCamera"
    private static let nameKey = "remoteShutterCameraName"

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var camera: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var firing = false

    override private init() {
        super.init()
    }

    /// Turns Bluetooth on if the shutter was left on last time.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    private func start() {
        if central == nil {
            // Asks for Bluetooth permission the first time.
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            reconnect()
        }
    }

    private func stop() {
        central?.stopScan()
        if let camera { central?.cancelPeripheralConnection(camera) }
        camera = nil
        commandCharacteristic = nil
        found = []
        state = .off
    }

    /// Looks for cameras in pairing mode, to pick one.
    func search() {
        guard let central, central.state == .poweredOn else { return }
        found = []
        state = .searching
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    /// Pairs with a camera found by `search`, and remembers it.
    func connect(to id: UUID) {
        guard let central, let peripheral = peripherals[id] else { return }
        central.stopScan()
        UserDefaults.standard.set(id.uuidString, forKey: Self.cameraKey)
        UserDefaults.standard.set(peripheral.name ?? "Sony Camera", forKey: Self.nameKey)
        connect(peripheral)
    }

    /// Forgets the camera, to pair another.
    func forget() {
        if let camera { central?.cancelPeripheralConnection(camera) }
        camera = nil
        commandCharacteristic = nil
        UserDefaults.standard.removeObject(forKey: Self.cameraKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        search()
    }

    /// Clicks the camera's shutter: half press, full press, then release.
    func fire() {
        guard let camera, let command = commandCharacteristic, !firing else { return }
        firing = true
        problem = nil
        let type: CBCharacteristicWriteType = command.properties.contains(.write) ? .withResponse : .withoutResponse
        Task {
            for bytes in SonyRemote.shutterClick {
                camera.writeValue(Data(bytes), for: command, type: type)
                try? await Task.sleep(for: .milliseconds(60))
            }
            firing = false
        }
    }

    private func reconnect() {
        guard let central, central.state == .poweredOn else { return }
        if let saved = UserDefaults.standard.string(forKey: Self.cameraKey).flatMap(UUID.init(uuidString:)),
           let peripheral = central.retrievePeripherals(withIdentifiers: [saved]).first {
            connect(peripheral)
        } else {
            search()
        }
    }

    private func connect(_ peripheral: CBPeripheral) {
        camera = peripheral
        commandCharacteristic = nil
        peripheral.delegate = self
        state = .connecting(peripheral.name ?? savedCameraName ?? "Sony Camera")
        // Waits as long as it takes for the camera to turn on.
        central?.connect(peripheral)
    }
}

extension ShutterRemote: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            switch central.state {
            case .poweredOn: if isEnabled { reconnect() }
            case .poweredOff: state = .unavailable("Bluetooth is off.")
            case .unauthorized: state = .unavailable("SwiftFrame isn't allowed to use Bluetooth. Allow it in System Settings → Privacy & Security → Bluetooth.")
            case .unsupported: state = .unavailable("This Mac doesn't support Bluetooth LE.")
            default: break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        guard SonyRemote.isSonyCamera(manufacturerData: data) else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Sony Camera"
        MainActor.assumeIsolated {
            peripherals[peripheral.identifier] = peripheral
            if !found.contains(where: { $0.id == peripheral.identifier }) {
                found.append(FoundCamera(id: peripheral.identifier, name: name))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([SonyRemote.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated {
            guard peripheral == camera, isEnabled else { return }
            connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: (any Error)?) {
        MainActor.assumeIsolated {
            // The camera turned off or went out of range: reconnect when it's back.
            guard peripheral == camera, isEnabled else { return }
            connect(peripheral)
        }
    }
}

extension ShutterRemote: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        MainActor.assumeIsolated {
            guard let service = peripheral.services?.first(where: { $0.uuid == SonyRemote.service }) else {
                state = .unavailable("The camera didn't offer remote control. Turn on Bluetooth Rmt Ctrl in its Network menu.")
                return
            }
            peripheral.discoverCharacteristics([SonyRemote.command, SonyRemote.status], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: (any Error)?) {
        MainActor.assumeIsolated {
            for characteristic in service.characteristics ?? [] {
                switch characteristic.uuid {
                case SonyRemote.command:
                    commandCharacteristic = characteristic
                    state = .connected(peripheral.name ?? savedCameraName ?? "Sony Camera")
                case SonyRemote.status:
                    // Subscribing is what asks the camera to pair, the first time.
                    peripheral.setNotifyValue(true, for: characteristic)
                default: break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: (any Error)?) {
        guard let value = characteristic.value else { return }
        MainActor.assumeIsolated {
            // 02 A0 20: the shutter fired.
            if Array(value) == [0x02, 0xA0, 0x20] { lastShutter = Date() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                error: (any Error)?) {
        guard let error else { return }
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            problem = "The camera didn't take the shutter press: \(message)"
        }
    }
}
