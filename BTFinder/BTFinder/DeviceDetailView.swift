//
//  DeviceDetailView.swift
//  BTFinder
//
//  Created by jenkins on 18/11/2025.
//

import SwiftUI

/// Chat screen for a single connected BLE device.
///
/// Responsibilities:
/// - Displays the chat history for the given `DiscoveredDevice`.
/// - Shows a simple connection status indicator.
/// - Sends new messages via `DeviceDetailViewModel`.
///
/// The actual Bluetooth connection lifecycle is owned by `BluetoothScanViewModel`:
/// this screen assumes the device is already connected when it is presented.
struct DeviceDetailView: View {
    
    /// The BLE device this screen is bound to (used mainly for the title).
    let device: DiscoveredDevice
    
    /// View model providing chat messages and send logic.
    @StateObject private var viewModel: DeviceDetailViewModel
    
    /// Creates a new chat view for the given device.
    /// - Parameters:
    ///   - device: The device to show messages for.
    ///   - service: Bluetooth service implementation (defaults to the shared singleton).
    init(device: DiscoveredDevice,
         service: BluetoothServiceProtocol = BluetoothService.shared) {
        self.device = device
        _viewModel = StateObject(
            wrappedValue: DeviceDetailViewModel(device: device, service: service)
        )
    }
    
    var body: some View {
        VStack(spacing: 12) {
            
            // Connection / status row
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                
                Text(viewModel.status)
                    .font(.subheadline)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Chat messages history
            List(viewModel.messages, id: \.self) { msg in
                Text(msg)
            }
            
            // Input bar
            HStack {
                TextField("Type a message…", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                
                Button("Send") {
                    viewModel.send()
                }
                .disabled(
                    viewModel.inputText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
            .padding()
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
