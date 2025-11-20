//
//  BTFinderApp.swift
//  BTFinder
//
//  Created by jenkins on 16/11/2025.
//

import SwiftUI
import Combine

/// View model responsible for:
/// - Managing BLE scanning cycles (start/stop, intervals, pruning).
/// - Tracking the list of discovered devices.
/// - Managing the currently connected device.
/// - Tracking unread message counts for the badge on the main screen.
/// - Reacting to disconnect events from `BluetoothService`.
final class BluetoothScanViewModel: ObservableObject {
    
    // MARK: - Published UI State
    
    /// List of devices currently displayed in the UI.
    @Published var devices: [DiscoveredDevice] = []
    
    /// Whether periodic “scan every X seconds” mode is active.
    @Published var isAutoScanning: Bool = false
    
    /// The interval between scan windows (seconds).
    /// When changed while auto-scanning is enabled, the timer is restarted
    /// to use the new value.
    @Published var scanInterval: TimeInterval = 10 {
        didSet {
            onScanIntervalChanged()
        }
    }
    
    /// The currently connected BLE device, if any.
    @Published var connectedDevice: DiscoveredDevice?
    
    /// Number of unread chat messages received for the currently connected device
    /// while the user is on the main screen (used for the badge on “Open chat”).
    @Published var unreadMessagesCount: Int = 0
    
    
    // MARK: - Private State
    
    /// BLE service abstraction used by this view model.
    private let service: BluetoothServiceProtocol
    
    /// Periodic scan timer.
    private var timer: Timer?
    
    /// Length of each scan window (seconds).
    private let scanWindow: TimeInterval = 3
    
    /// Indicates whether the VM is currently inside a scan window.
    private var isScanWindowActive = false
    
    /// Snapshot of discovered devices from the last completed scan window.
    private var lastDevicesSnapshot: [DiscoveredDevice] = []
    
    
    // MARK: - Init
    
    /// Creates a new scan view model.
    /// - Parameter service: BLE service implementation. Defaults to the shared singleton.
    init(service: BluetoothServiceProtocol = BluetoothService.shared) {
        self.service = service
        
        attachDeviceUpdated()
        
        attachMessageHandler()
        
        attachDeviceDisconnected()
    }
    
    func attachDeviceUpdated() {
        service.onDevicesUpdated = { [weak self] devices in
            guard let self = self else { return }
            
            self.lastDevicesSnapshot = devices
            
            guard self.isScanWindowActive == false else { return }
            
            DispatchQueue.main.async {
                withAnimation(.none) {
                    self.devices = devices
                }
            }
        }
    }
    
    func attachDeviceDisconnected() {
        service.onDeviceDisconnected = { [weak self] deviceID, error in
            guard let self = self else { return }
            guard let current = self.connectedDevice,
                  current.id == deviceID else { return }
            
            DispatchQueue.main.async {
                self.connectedDevice = nil
                self.unreadMessagesCount = 0
            }
        }
    }
    
    // MARK: - Message Handling (Unread Badge)
    
    /// Starts listening for messages from the BLE service and increments
    /// the unread count for the currently connected device.
    func attachMessageHandler() {
        service.onMessageReceived = { [weak self] deviceID, text in
            guard let self = self else { return }
            guard deviceID == self.connectedDevice?.id else { return }
            
            DispatchQueue.main.async {
                self.unreadMessagesCount += 1
                self.updateBadgeAndNotification(for: text)
            }
        }
    }
    
    /// Updates the app icon badge and, if the app is backgrounded, triggers a local notification.
    /// Keep app icon badge in sync with unreadMessagesCount
    /// Only show a notification if the app is not active
    private func updateBadgeAndNotification(for text: String) {
        UNUserNotificationCenter.current().setBadgeCount(unreadMessagesCount)
        
        if !AppLifecycle.shared.isActive {
            let content = UNMutableNotificationContent()
            content.title = connectedDevice?.name ?? "New BLE message"
            content.body = text
            content.badge = NSNumber(value: unreadMessagesCount)
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil // deliver immediately
            )
            
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
    /// Resets the unread messages counter (typically when entering the chat view).
    func clearUnreadMessages() {
        unreadMessagesCount = 0
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    
    // MARK: - Public Actions
    
    /// Toggles the periodic scanning loop on or off.
    func toggleAutoScan() {
        if isAutoScanning {
            stopAutoScan()
        } else {
            startAutoScan()
        }
    }
    
    /// Handles user selection of a device from the list.
    /// Disconnects the previous device (if any) and connects to the new selection.
    /// - Parameter device: The device the user selected.
    func selectDevice(_ device: DiscoveredDevice) {
        if let current = connectedDevice, current.id == device.id {
            return
        }
        
        if let current = connectedDevice {
            service.disconnect(from: current)
        }
        
        connectedDevice = device
        clearUnreadMessages()
        service.connect(to: device)
    }
    
    /// Disconnects the currently connected device, if present, and clears unread count.
    func disconnectCurrent() {
        guard let current = connectedDevice else { return }
        service.disconnect(from: current)
        connectedDevice = nil
        clearUnreadMessages()
    }
    
    
    // MARK: - Scanning Logic
    
    /// Starts periodic scanning: runs an immediate scan, then repeats every `scanInterval`.
    private func startAutoScan() {
        guard timer == nil else { return }
        
        isAutoScanning = true
        runSingleScan()
        createTimer()
    }
    
    /// Stops periodic scanning and resets the UI to the last known snapshot.
    private func stopAutoScan() {
        isAutoScanning = false
        invalidateTimer()
        service.stopScanning()
        
        isScanWindowActive = false
        
        DispatchQueue.main.async {
            withAnimation(.none) {
                self.devices = self.lastDevicesSnapshot
            }
        }
    }
    
    /// Reacts to changes in `scanInterval`. If auto-scanning is active,
    /// the timer is recreated with the new interval.
    private func onScanIntervalChanged() {
        guard isAutoScanning else { return }
        restartTimerWithNewInterval()
    }
    
    /// Creates the repeating timer that triggers scan cycles.
    private func createTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: scanInterval,
            repeats: true
        ) { [weak self] _ in
            self?.runSingleScan()
        }
    }
    
    /// Invalidates and clears the periodic scan timer, if present.
    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Recreates the periodic scan timer using the current `scanInterval`.
    private func restartTimerWithNewInterval() {
        invalidateTimer()
        createTimer()
    }
    
    /// Executes a single scan cycle:
    /// - Ensures any previous scan is stopped.
    /// - Starts a new scan.
    /// - After `scanWindow` seconds stops scanning, prunes devices,
    ///   and publishes the final list to the UI.
    private func runSingleScan() {
        service.stopScanning()
        
        isScanWindowActive = true
        let scanStart = Date()
        
        service.startScanning()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + scanWindow) { [weak self] in
            guard let self = self else { return }
            
            self.service.stopScanning()
            self.service.pruneDevices(lastSeenBefore: scanStart)
            
            self.isScanWindowActive = false
            
            DispatchQueue.main.async {
                withAnimation(.none) {
                    self.devices = self.lastDevicesSnapshot
                }
            }
        }
    }
}
