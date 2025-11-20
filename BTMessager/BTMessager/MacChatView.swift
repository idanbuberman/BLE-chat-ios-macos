//
//  MacChatView.swift
//  BTMessager
//
//  Created by Idan Buberman on 19/11/2025.
//

import SwiftUI

/// Main UI for the macOS BLE chat peripheral.
///
/// This view displays:
/// - Bluetooth power state and advertising status
/// - A collapsible debug log (messages about BLE state, connections, etc.)
/// - A list of all messages received from the iOS device
/// - A text field for typing messages to send back to the connected central
///
/// When the view appears, it automatically starts the peripheral manager.
struct MacChatView: View {
    
    /// The BLE peripheral manager handling advertising, subscriptions,
    /// received messages and log output.
    @StateObject private var peripheral = MacChatPeripheral()
    
    /// Text currently typed into the outgoing message input field.
    @State private var outgoingText: String = ""
    
    /// Controls whether the debug log section is expanded.
    @State private var isLogExpanded: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            
            statusHeader
            
            List {
                logSection
                receivedMessagesSection
            }
            
            inputBar
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            peripheral.start()
        }
    }
}

private extension MacChatView {
    
    /// Displays the Bluetooth power and advertising state at the top of the screen.
    var statusHeader: some View {
        HStack {
            Circle()
                .fill(peripheral.isPoweredOn ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            
            Text(peripheral.isPoweredOn ? "Bluetooth ON" : "Bluetooth OFF")
            
            Spacer()
            
            Text(peripheral.isAdvertising ? "Advertising" : "Not advertising")
                .foregroundColor(peripheral.isAdvertising ? .green : .secondary)
        }
        .padding(.horizontal)
        .padding(.top)
    }
    
    /// Displays a collapsible section containing all log lines generated
    /// by the BLE peripheral manager. Users may expand, read, copy, or clear the log.
    var logSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isLogExpanded) {
                
                ForEach(peripheral.log, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                if !peripheral.log.isEmpty {
                    Button("Clear log") {
                        peripheral.log.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .padding(.top, 4)
                }
                
            } label: {
                HStack {
                    Text("Log")
                    Spacer()
                    if !peripheral.log.isEmpty {
                        Text("\(peripheral.log.count)")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
    
    /// Displays all messages received from the connected iOS central.
    /// If no messages have been received, a placeholder is shown.
    var receivedMessagesSection: some View {
        Section("Received messages") {
            if peripheral.receivedMessages.isEmpty {
                Text("No messages yet")
                    .foregroundColor(.secondary)
            } else {
                ForEach(peripheral.receivedMessages, id: \.self) { msg in
                    Text(msg)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    /// The input bar used to compose and send messages to subscribed centrals.
    /// The send button becomes disabled if Bluetooth is not advertising or
    /// if the message is empty.
    var inputBar: some View {
        HStack {
            TextField("Message to iOS…", text: $outgoingText)
            
            Button("Send") {
                let text = outgoingText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                peripheral.sendToCentrals(text)
                outgoingText = ""
            }
            .disabled(!peripheral.isAdvertising ||
                      outgoingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
}
