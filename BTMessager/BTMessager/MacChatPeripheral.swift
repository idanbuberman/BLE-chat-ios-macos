//
//  MacChatPeripheral.swift
//  BTMessager
//
//  Created by Idan Buberman on 19/11/2025.
//

import Foundation
import CoreBluetooth

/// A Bluetooth LE peripheral manager used by the macOS app to:
/// - Advertise a BLE service compatible with the iOS central.
/// - Expose two characteristics:
///   - TX characteristic (notify): used to send messages to the iOS device.
///   - RX characteristic (write): used to receive messages from the iOS device.
/// - Track connected centrals, advertising status, and received messages.
/// - Publish status/logs for UI consumption.
///
/// This class provides a simple "chat-over-BLE" interface that works with the
/// iOS `BluetoothService` central implementation.
final class MacChatPeripheral: NSObject, ObservableObject {
    
    /// Indicates whether the Mac's Bluetooth hardware is powered on.
    @Published var isPoweredOn: Bool = false
    
    /// Reflects whether the peripheral is currently advertising its service.
    @Published var isAdvertising: Bool = false
    
    /// A running log of BLE-related state changes, events, and errors.
    @Published var log: [String] = []
    
    /// Messages received from the iOS central via the RX characteristic.
    @Published var receivedMessages: [String] = []
    
    /// Core Bluetooth peripheral manager handling advertising and requests.
    private var peripheralManager: CBPeripheralManager!
    
    /// Notify characteristic used to send data to iOS.
    private var txCharacteristic: CBMutableCharacteristic!
    
    /// Write characteristic used to receive data from iOS.
    private var rxCharacteristic: CBMutableCharacteristic!
    
    /// List of centrals currently subscribed to the TX characteristic.
    private var subscribedCentrals: [CBCentral] = []
    
    /// UUID identifying the chat BLE service (must match iOS).
    private let chatServiceUUID  = CBUUID(string: "7E57C000-2C8F-4F3C-9F91-8577E1891234")
    
    /// UUID identifying the notify characteristic for sending messages to iOS.
    private let chatTxCharUUID   = CBUUID(string: "7E57C001-2C8F-4F3C-9F91-8577E1891234")
    
    /// UUID identifying the write characteristic for receiving messages from iOS.
    private let chatRxCharUUID   = CBUUID(string: "7E57C002-2C8F-4F3C-9F91-8577E1891234")
    
    /// Initializes the peripheral manager and sets itself as the delegate.
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    /// Appends a line to the internal log as well as printing to the console.
    /// - Parameter message: The text log entry.
    private func appendLog(_ message: String) {
        print(message)
        DispatchQueue.main.async {
            self.log.append(message)
        }
    }
    
    // MARK: - Public API
    
    /// Starts advertising the BLE service if Bluetooth is powered on.
    ///
    /// This is intended to be called when the app UI appears. If the peripheral
    /// manager is already powered on, advertising begins immediately.
    func start() {
        if peripheralManager.state == .poweredOn, !isAdvertising {
            setupServiceAndStartAdvertising()
        }
    }
    
    /// Stops advertising the BLE service.
    func stop() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
        appendLog("🛑 Stopped advertising")
    }
    
    /// Sends a UTF-8 text message to all subscribed centrals via the TX characteristic.
    /// - Parameter text: The message to send to the connected iOS device(s).
    func sendToCentrals(_ text: String) {
        guard !subscribedCentrals.isEmpty else {
            appendLog("⚠️ No subscribed centrals to send to")
            return
        }
        guard let data = text.data(using: .utf8) else {
            appendLog("⚠️ Could not encode text as UTF-8")
            return
        }
        
        let success = peripheralManager.updateValue(
            data,
            for: txCharacteristic,
            onSubscribedCentrals: nil
        )
        
        if success {
            appendLog("➡️ Sent to iOS: \(text)")
        } else {
            appendLog("⚠️ updateValue returned false (buffer full?)")
        }
    }
    
    // MARK: - Internal Setup
    
    /// Configures the BLE service, characteristics, and starts advertising.
    ///
    /// This method:
    /// - Creates the TX (notify) and RX (write) characteristics.
    /// - Creates and registers the service containing them.
    /// - Begins advertising the service UUID and local device name.
    private func setupServiceAndStartAdvertising() {
        guard !isAdvertising else { return }
        
        appendLog("🔧 Setting up service & advertising…")
        
        txCharacteristic = CBMutableCharacteristic(
            type: chatTxCharUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )
        
        rxCharacteristic = CBMutableCharacteristic(
            type: chatRxCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )
        
        let service = CBMutableService(type: chatServiceUUID, primary: true)
        service.characteristics = [txCharacteristic, rxCharacteristic]
        
        peripheralManager.add(service)
        
        let advertisement: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [chatServiceUUID],
            CBAdvertisementDataLocalNameKey: "MacChat"
        ]
        
        peripheralManager.startAdvertising(advertisement)
        isAdvertising = true
        appendLog("📣 Started advertising MacChat")
    }
}

// MARK: - CBPeripheralManagerDelegate

extension MacChatPeripheral: CBPeripheralManagerDelegate {
    
    /// Called when the Bluetooth state of the Mac changes.
    /// Sets published state flags and auto-starts advertising when possible.
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .unknown:      appendLog("State: unknown")
        case .resetting:    appendLog("State: resetting")
        case .unsupported:  appendLog("State: unsupported")
        case .unauthorized: appendLog("State: unauthorized (check sandbox + plist!)")
        case .poweredOff:
            appendLog("State: poweredOff")
            isPoweredOn = false
            isAdvertising = false
        case .poweredOn:
            appendLog("State: poweredOn")
            isPoweredOn = true
            setupServiceAndStartAdvertising()
        @unknown default:
            appendLog("State: unknown default")
        }
    }
    
    /// Called after the service is added to the peripheral manager.
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService,
                           error: Error?) {
        if let error = error {
            appendLog("❌ Failed to add service: \(error)")
        } else {
            appendLog("✅ Service added: \(service.uuid)")
        }
    }
    
    /// Called when a central subscribes to the TX notify characteristic.
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        guard characteristic.uuid == chatTxCharUUID else { return }
        subscribedCentrals.append(central)
        appendLog("✅ Central subscribed: \(central)")
    }
    
    /// Called when a central unsubscribes from the TX characteristic.
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard characteristic.uuid == chatTxCharUUID else { return }
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        appendLog("ℹ️ Central unsubscribed: \(central)")
    }
    
    /// Called when the iOS central writes data to the RX characteristic.
    ///
    /// Each request is decoded into a UTF-8 string and added to the published
    /// `receivedMessages` list.
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests where req.characteristic.uuid == chatRxCharUUID {
            if let data = req.value,
               let text = String(data: data, encoding: .utf8) {
                appendLog("⬅️ Received from iOS: \(text)")
                DispatchQueue.main.async {
                    self.receivedMessages.append(text)
                }
            } else {
                appendLog("⚠️ Received non-UTF8 data")
            }
            
            peripheralManager.respond(to: req, withResult: .success)
        }
    }
}
