//
//  BTListView.swift
//  BTFinder
//
//  Created by jenkins on 16/11/2025.
//

import SwiftUI

/// Root screen of the iOS app.
///
/// Responsibilities:
/// - Starts / stops periodic BLE scans (via `BluetoothScanViewModel`).
/// - Shows a list of nearby peripherals with RSSI.
/// - Manages a single active BLE connection:
///   - Selecting a device connects to it (disconnecting any previous one).
///   - Provides a manual “disconnect” button.
/// - Navigates to `DeviceDetailView` (chat screen) for the currently connected device.
/// - Displays a badge on the “Open chat” button for unread messages received
///   while the user is on this screen.
struct BluetoothScanView: View {
    
    /// View-model that owns scan logic, current connection and unread messages.
    @StateObject private var viewModel = BluetoothScanViewModel()
    
    /// Controls navigation to the chat screen (`DeviceDetailView`).
    @State private var isChatActive: Bool = false

    /// Available scan interval options (seconds) for the user to pick from.
    private let intervals: [TimeInterval] = [5, 10, 15, 30]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                VStack(alignment: .leading, spacing: 8) {
                    
                    // MARK: Connected device
                    HStack {
                        // Connected device name / placeholder
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connected device")
                                .font(.headline)
                            
                            if let connected = viewModel.connectedDevice {
                                Text(connected.name)
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            } else {
                                Text("None")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        
                        // Open chat with floating unread badge
                        Button {
                            if viewModel.connectedDevice != nil {
                                // Reset badge when entering chat
                                viewModel.clearUnreadMessages()
                                isChatActive = true
                            }
                        } label: {
                            let hasConnectedDevice = (viewModel.connectedDevice != nil)
                            let count = viewModel.unreadMessagesCount
                            
                            Text("Open chat")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(hasConnectedDevice ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                                .cornerRadius(10)
                                // Extra padding gives overlay badge room to “float” outside
                                .padding(.top, 6)
                                .padding(.trailing, 6)
                                .overlay(alignment: .topTrailing) {
                                    // Floating badge for unread messages
                                    if count > 0 {
                                        let badgeText: String = (count <= 99) ? "\(count)" : "..."
                                        
                                        Text(badgeText)
                                            .font(.caption2)
                                            .padding(5)
                                            .background(Color.red)
                                            .foregroundColor(.white)
                                            .clipShape(Circle())
                                            .offset(x: 6, y: -6)
                                    }
                                }
                        }
                        .disabled(viewModel.connectedDevice == nil)
                        
                        // Manual disconnect button for current connection
                        Button {
                            viewModel.disconnectCurrent()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        .disabled(viewModel.connectedDevice == nil)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // MARK: Interval picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scan interval")
                        .font(.headline)
                    
                    Picker("Scan interval", selection: $viewModel.scanInterval) {
                        ForEach(intervals, id: \.self) { interval in
                            Text("\(Int(interval))s").tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
                
                // MARK: Start / Stop periodic scan
                Button {
                    viewModel.toggleAutoScan()
                } label: {
                    HStack {
                        Image(systemName: viewModel.isAutoScanning
                              ? "stop.fill"
                              : "dot.radiowaves.left.and.right")
                        Text(viewModel.isAutoScanning ? "Stop scanning" : "Start scanning")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isAutoScanning ? Color.red.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                // MARK: Devices list
                List(viewModel.devices) { device in
                    let isConnected = viewModel.connectedDevice?.id == device.id
                    
                    // Selecting a device connects to it (and disconnects any previous one).
                    Button {
                        viewModel.selectDevice(device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                Text("RSSI: \(device.rssi)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(isConnected ? "Connected" : "Connect")
                                .font(.caption)
                                .padding(6)
                                .background(isConnected ? Color.green.opacity(0.2) : Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Nearby Bluetooth")
            
            // MARK: Navigation
            // When `isChatActive` is toggled on, push the chat screen for the
            // currently connected device. On dismiss, reattach the unread handler
            // so the badge continues to work while on this screen.
            .navigationDestination(isPresented: $isChatActive) {
                if let connected = viewModel.connectedDevice {
                    DeviceDetailView(device: connected)
                        .onDisappear {
                            // When chat is closed, reattach unread handler for badge
                            viewModel.attachMessageHandler()
                        }
                } else {
                    Text("No device connected")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
