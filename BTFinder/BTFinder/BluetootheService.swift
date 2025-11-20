//
//  DiscoveredPeripheral.swift
//  BTFinder
//
//  Created by jenkins on 16/11/2025.
//

import Foundation
import CoreBluetooth

// MARK: - Models & Protocol

/// Represents a single discovered BLE peripheral.
///
/// This struct is used by the UI and view models to display device information
/// and to pass the corresponding `CBPeripheral` to the Bluetooth service.
struct DiscoveredDevice: Identifiable, Equatable {
    /// Stable identifier derived from the underlying `CBPeripheral.identifier`.
    let id: UUID
    /// Human–readable name, either the peripheral’s name, advertised local name, or `"Unknown"`.
    var name: String
    /// Last received RSSI value (signal strength).
    var rssi: Int
    /// Underlying CoreBluetooth peripheral reference.
    var peripheral: CBPeripheral
    /// Timestamp of the last time this device was seen during scanning.
    var lastSeen: Date
}

/// Abstraction over the Bluetooth layer used by the iOS app.
///
/// This protocol allows the UI and view models to interact with Bluetooth
/// without directly depending on CoreBluetooth, which keeps the app testable
/// and the BLE implementation swappable.
protocol BluetoothServiceProtocol: AnyObject {
    
    /// Called whenever the internal list of discovered devices changes.
    var onDevicesUpdated: (([DiscoveredDevice]) -> Void)? { get set }
    
    /// Called when the scanning state changes (true = scanning).
    var onScanningChanged: ((Bool) -> Void)? { get set }
    
    /// Called when a new chat message is received from a connected device.
    /// The first parameter is the device UUID, the second is the decoded text.
    var onMessageReceived: ((UUID, String) -> Void)? { get set }
    
    /// Called when a previously connected device is disconnected by CoreBluetooth.
    /// The UUID identifies the peripheral; `Error?` carries the disconnection reason (if any).
    var onDeviceDisconnected: ((UUID, Error?) -> Void)? { get set }

    /// Starts scanning for nearby BLE peripherals.
    func startScanning()
    
    /// Stops an active scan, if any.
    func stopScanning()
    
    /// Removes devices that have not been seen since `cutoff`.
    /// Used to model a “left outer join” between scans.
    func pruneDevices(lastSeenBefore cutoff: Date)
    
    /// Initiates a connection to the given device.
    func connect(to device: DiscoveredDevice)
    
    /// Cancels an active or pending connection to the given device.
    func disconnect(from device: DiscoveredDevice)
    
    /// Sends a UTF-8 encoded text message to the given device using its write characteristic.
    func sendMessage(_ text: String, to device: DiscoveredDevice)
    
    /// Returns the stored chat history (messages received from the Mac) for a given device.
    func messages(for deviceID: UUID) -> [String]
}


// MARK: - Service (Central)

/// Concrete CoreBluetooth central–side implementation of `BluetoothServiceProtocol`.
///
/// Responsibilities:
/// - Manages a single `CBCentralManager`.
/// - Scans for nearby devices and maintains a pruned `devicesById` map.
/// - Connects to peripherals that expose a custom “chat” service.
/// - Discovers characteristics used for bidirectional text chat.
/// - Sends messages (iOS → Mac) and receives messages (Mac → iOS).
/// - Persists per-device message history so chat screens can show backlog.
final class BluetoothService: NSObject, BluetoothServiceProtocol {
    
    /// Shared singleton instance.
    ///
    /// For this exercise, a singleton keeps wiring simple. In production code,
    /// dependency injection is usually preferred to make the service mockable
    /// and easier to test.
    static let shared = BluetoothService()
    
    
    // MARK: Public callbacks
    
    var onDevicesUpdated: (([DiscoveredDevice]) -> Void)?
    var onScanningChanged: ((Bool) -> Void)?
    var onMessageReceived: ((UUID, String) -> Void)?
    var onDeviceDisconnected: ((UUID, Error?) -> Void)?
    
    
    // MARK: Private state
    
    /// Currently connected peripherals, keyed by device UUID.
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    
    /// TX characteristics (notify) per device (Mac → iOS messages).
    private var txCharacteristics: [UUID: CBCharacteristic] = [:]
    
    /// RX characteristics (write) per device (iOS → Mac messages).
    private var rxCharacteristics: [UUID: CBCharacteristic] = [:]
    
    /// In-memory chat history per device (messages received from Mac).
    private var messagesByDevice: [UUID: [String]] = [:]

    /// Discovered devices (after pruning), keyed by UUID.
    /// Whenever this dictionary changes, `onDevicesUpdated` is called on the main queue.
    private var devicesById: [UUID: DiscoveredDevice] = [:] {
        didSet {
            let devices = devicesById.values
                .sorted { $0.name < $1.name }
            
            DispatchQueue.main.async { [devices, weak self] in
                self?.onDevicesUpdated?(devices)
            }
        }
    }
    
    /// Current scanning state.
    private var isScanning: Bool = false {
        didSet {
            DispatchQueue.main.async { [isScanning, weak self] in
                self?.onScanningChanged?(isScanning)
            }
        }
    }
    
    /// CoreBluetooth central manager.
    private var centralManager: CBCentralManager!
    
    /// Custom chat service UUID (must match macOS app).
    private let chatServiceUUID  = CBUUID(string: "7E57C000-2C8F-4F3C-9F91-8577E1891234")
    
    /// TX (notify) characteristic UUID (Mac → iOS messages).
    private let chatTxCharUUID   = CBUUID(string: "7E57C001-2C8F-4F3C-9F91-8577E1891234")
    
    /// RX (write) characteristic UUID (iOS → Mac messages).
    private let chatRxCharUUID   = CBUUID(string: "7E57C002-2C8F-4F3C-9F91-8577E1891234")
    
    
    // MARK: Init

    /// Private initializer to enforce singleton usage.
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    
    // MARK: Scanning
    
    /// Starts scanning for peripherals. If the central is not yet powered on,
    /// the request is ignored and a warning is printed.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("⚠️ Central not powered on, state = \(centralManager.state.rawValue)")
            return
        }
        
        isScanning = true
        
        centralManager.scanForPeripherals(
            withServices: nil, // or [chatServiceUUID] to filter only the chat service
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    /// Stops an active scan, if any.
    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
    }
    
    /// Retains only devices that have been seen since the given cutoff date.
    /// This behaves like a “left outer join” between scan cycles: any device
    /// that was not seen in the latest window is removed.
    /// - Parameter cutoff: Minimum `lastSeen` allowed for devices to remain.
    func pruneDevices(lastSeenBefore cutoff: Date) {
        devicesById = devicesById.filter { _, device in
            device.lastSeen >= cutoff
        }
    }
    
    
    // MARK: Messaging
    
    /// Sends a UTF-8 encoded text message to a given device using its RX (write) characteristic.
    /// - Parameters:
    ///   - text: The message to send.
    ///   - device: The target device, which must be currently connected.
    func sendMessage(_ text: String, to device: DiscoveredDevice) {
        guard let peripheral = connectedPeripherals[device.id],
              let rxChar = rxCharacteristics[device.id] else {
            print("⚠️ No connected peripheral / RX characteristic for \(device.id)")
            return
        }
        
        guard let data = text.data(using: .utf8) else {
            print("⚠️ Could not encode text to UTF-8")
            return
        }
        
        peripheral.writeValue(data, for: rxChar, type: .withResponse)
    }
    
    
    // MARK: Connections
    
    /// Requests a connection to the given device and sets up delegation.
    /// - Parameter device: The discovered device to connect to.
    func connect(to device: DiscoveredDevice) {
        device.peripheral.delegate = self
        connectedPeripherals[device.id] = device.peripheral
        centralManager.connect(device.peripheral, options: nil)
    }
    
    /// Cancels the connection to the given device and clears cached characteristics.
    /// - Parameter device: The device to disconnect from.
    func disconnect(from device: DiscoveredDevice) {
        guard let peripheral = connectedPeripherals[device.id] else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        connectedPeripherals[device.id] = nil
        txCharacteristics[device.id] = nil
        rxCharacteristics[device.id] = nil
    }
    
    
    // MARK: Storage
    
    /// Returns a copy of the stored message history for the given device.
    /// - Parameter deviceID: Identifier of the device.
    func messages(for deviceID: UUID) -> [String] {
        messagesByDevice[deviceID] ?? []
    }
}


// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    
    /// Handles central manager state changes (powered on/off, unsupported, etc.).
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:      print("Central state is .unknown")
        case .resetting:    print("Central state is .resetting")
        case .unsupported:  print("Central state is .unsupported")
        case .unauthorized: print("Central state is .unauthorized")
        case .poweredOff:   print("Central state is .poweredOff")
        case .poweredOn:
            print("Central state is .poweredOn")
            // Optional: auto-start scanning here if desired.
        @unknown default:
            print("Central state is unknown default")
        }
    }
    
    /// Called when a peripheral is discovered during scanning.
    /// Updates or inserts the corresponding `DiscoveredDevice` in `devicesById`.
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown"
        
        let id = peripheral.identifier
        let now = Date()
        
        if var existing = devicesById[id] {
            existing.name = name
            existing.rssi = RSSI.intValue
            existing.lastSeen = now
            existing.peripheral = peripheral
            devicesById[id] = existing
        } else {
            let newDevice = DiscoveredDevice(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral,
                lastSeen: now
            )
            devicesById[id] = newDevice
        }
    }
    
    /// Called when a connection to a peripheral has been established.
    /// Discovery is continued by looking for the chat service.
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print("✅ Connected to \(peripheral.name ?? "Unknown") – \(peripheral.identifier)")
        peripheral.delegate = self
        peripheral.discoverServices([chatServiceUUID])
    }
    
    /// Called when a connection attempt fails.
    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("❌ Failed to connect: \(String(describing: error))")
    }
    
    /// Called when a previously connected peripheral is disconnected.
    /// Clears cached state and forwards the event to higher layers.
    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("ℹ️ Disconnected from \(peripheral.identifier): \(String(describing: error))")
        let id = peripheral.identifier
        connectedPeripherals[id] = nil
        txCharacteristics[id] = nil
        rxCharacteristics[id] = nil
        
        onDeviceDisconnected?(id, error)
    }
}


// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    
    /// Called when services are discovered on a connected peripheral.
    /// Filters for the chat service and then requests its characteristics.
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard error == nil else {
            print("didDiscoverServices error: \(error!)")
            return
        }
        
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == chatServiceUUID {
            print("🔹 Found chat service on \(peripheral.identifier)")
            peripheral.discoverCharacteristics([chatTxCharUUID, chatRxCharUUID], for: service)
        }
    }
    
    /// Called when characteristics are discovered for a given service.
    /// Captures TX (notify) and RX (write) characteristics and subscribes to TX updates.
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            print("didDiscoverCharacteristics error: \(error!)")
            return
        }
        guard let characteristics = service.characteristics else { return }
        
        let id = peripheral.identifier
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case chatTxCharUUID:
                print("   • Found TX (notify) characteristic")
                txCharacteristics[id] = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                
            case chatRxCharUUID:
                print("   • Found RX (write) characteristic")
                rxCharacteristics[id] = characteristic
                
            default:
                break
            }
        }
    }
    
    /// Called when a subscribed characteristic’s value changes.
    /// In this app, this is the TX (notify) characteristic carrying messages from Mac → iOS.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil else {
            print("didUpdateValue error: \(error!)")
            return
        }
        
        guard characteristic.uuid == chatTxCharUUID,
              let data = characteristic.value else { return }
        
        let id = peripheral.identifier
        let text = String(data: data, encoding: .utf8)
            ?? "<non-UTF8 data \(data as NSData)>"
        
        print("💬 Received from \(id): \(text)")
        
        // Persist message in history.
        var arr = messagesByDevice[id] ?? []
        arr.append(text)
        messagesByDevice[id] = arr
        
        // Forward message to any listener (e.g. chat view model).
        onMessageReceived?(id, text)
    }
}
