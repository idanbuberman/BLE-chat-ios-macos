# BLE-chat-ios-macos – iOS Central & macOS Peripheral

This repository contains a complete two-app Bluetooth Low Energy communication system:

1. **iOS App – “BTFinder”**  
   Acts as a BLE Central. Scans for devices, connects to one at a time, and provides a real-time text chat interface.

2. **macOS App – “BTMessager”**  
   Acts as a BLE Peripheral. Advertises a custom BLE chat service and exchanges UTF-8 messages with the iOS app.

The system demonstrates how to implement a cross-platform BLE chat using CoreBluetooth and SwiftUI.

---

## Project Structure
ble-chat/
├─ ios/ → BTFinder (iOS BLE Central)
├─ macos/ → BTMessager (macOS BLE Peripheral)
└─ README.md → System-level documentation (this file)

Each app has its own README for platform-specific details.

---

## Technologies Used

- SwiftUI  
- CoreBluetooth  
- MVVM + Service Layer  
- BLE Notify + Write  
- iOS 16+, macOS 13+  

---

## High-Level System Overview

Both apps communicate using a custom BLE “Chat Service”.

**Shared UUIDs:**

- Service UUID  
  `7E57C000-2C8F-4F3C-9F91-8577E1891234`

- TX Characteristic (Mac → iOS, notify)  
  `7E57C001-2C8F-4F3C-9F91-8577E1891234`

- RX Characteristic (iOS → Mac, write)  
  `7E57C002-2C8F-4F3C-9F91-8577E1891234`

This creates a simple bidirectional BLE chat protocol.

---

# iOS App (“BTFinder”) – BLE Central

The iOS app performs:

### 1. Periodic BLE scanning
- Scans once every X seconds
- Uses a “scan window” to avoid UI flicker
- Prunes old devices between windows

### 2. Single active connection
- Connects only to one device at a time
- Disconnects previous automatically
- UI shows the connected device

### 3. Chat UI
- Full message history
- Live incoming messages
- “Me:” prefix for outgoing messages

### 4. Unread message badge
- Shown on “Open chat”
- Increments only when chat is not open
- Supports “...” for 100+ messages

Uses:
- `BluetoothScanViewModel`
- `DeviceDetailViewModel`
- `BluetoothService`

---

# macOS App (“BTMessager”) – BLE Peripheral

The macOS app:

- Acts as a BLE Peripheral
- Advertises the chat service
- Exposes TX (notify) and RX (write) characteristics
- Shows BLE power state + advertising status
- Allows sending messages to iOS
- Displays all incoming messages
- Simulates a hardware BLE device

---

# End-To-End BLE Flow

1. macOS starts advertising  
2. iOS scans and discovers it  
3. User selects device → iOS connects  
4. iOS discovers service + characteristics  
5. Messaging flows:
   - iOS → Mac (write)
   - Mac → iOS (notify)
6. iOS stores messages per device
7. When macOS closes, iOS detects disconnect

---

# Running the System

### macOS
1. Run BTMessager
2. Wait for Bluetooth to show “poweredOn”
3. Advertising starts automatically

### iOS
1. Run BTFinder on a physical device
2. Tap “Start scanning”
3. Select your Mac when it appears
4. Tap “Open chat”
5. Exchange messages

---

# Future Improvements

- Background BLE mode  
- Better chat formatting  
- Persist history to disk  
- Reliable write queue  
- Auto-reconnect  
- Multi-device support  

---

# Author

Created by **Idan Buberman**, 2025  
Swift • CoreBluetooth • iOS • macOS

