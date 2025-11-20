//
//  DeviceDetailViewModel.swift
//  BTFinder
//
//  Created by jenkins on 18/11/2025.
//

import SwiftUI
import Combine

/// View model for the per-device chat screen (`DeviceDetailView`).
///
/// Responsibilities:
/// - Exposes the message history for a specific `DiscoveredDevice`.
/// - Listens for live incoming messages for that device.
/// - Sends new messages through the `BluetoothServiceProtocol`.
///
/// Note:
/// While this view model is active, it assigns `service.onMessageReceived`
/// to handle live updates for its specific device, temporarily overriding
/// the handler used by the scan view model. When the chat screen is dismissed,
/// the scan view reattaches its own handler to resume unread badge counting.
final class DeviceDetailViewModel: ObservableObject {
    
    /// Chat messages for this device, including restored history and live updates.
    @Published var messages: [String] = []
    
    /// Simple textual status shown in the UI (e.g. "Connected").
    @Published var status: String = "Connected"
    
    /// Indicates whether the view considers the device connected. For this exercise,
    /// this is kept simple and always `true` while the screen is shown.
    @Published var isConnected: Bool = true
    
    /// Text currently being typed in the input field.
    @Published var inputText: String = ""
    
    
    // MARK: - Private State
    
    /// The BLE device this view model is bound to.
    private let device: DiscoveredDevice
    
    /// Bluetooth service used for sending messages and loading history.
    private let service: BluetoothServiceProtocol
    
    
    // MARK: - Init
    
    /// Creates a new view model for a given device.
    /// - Parameters:
    ///   - device: The device whose chat history and messages will be displayed.
    ///   - service: The Bluetooth service implementation (defaults to the shared singleton).
    init(device: DiscoveredDevice,
         service: BluetoothServiceProtocol = BluetoothService.shared) {
        self.device = device
        self.service = service
        
        // Load existing message history for this device.
        self.messages = service.messages(for: device.id)
        
        // Subscribe to live messages for this device.
        service.onMessageReceived = { [weak self] deviceID, text in
            guard let self = self,
                  deviceID == self.device.id else { return }
            
            DispatchQueue.main.async {
                self.messages.append(text)
            }
        }
    }
    
    
    // MARK: - Actions
    
    /// Sends the current input text to the device and appends a local “Me:” entry.
    ///
    /// Leading and trailing whitespace is trimmed. Empty messages are ignored.
    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        service.sendMessage(text, to: device)
        messages.append("Me: \(text)")
        inputText = ""
    }
}
