
# BTMessager (macOS App)

BTMessager is a macOS Bluetooth Low Energy (BLE) **peripheral** designed to communicate with the iOS app "BTFinder".  
It exposes a small BLE chat protocol over a custom BLE service and allows sending and receiving text messages to/from an iOS central.

This project is part of a two-app exercise:
- BTFinder (iOS) → acts as a BLE **central**
- BTMessager (macOS) → acts as a BLE **peripheral**

The macOS app broadcasts a BLE service, waits for the iOS device to connect, receives writes, and sends notifications back.

---

## Features

- Runs a fully functional BLE peripheral using CoreBluetooth
- Advertises a custom service and two characteristics:
  - TX characteristic (notify) → Messages **from macOS to iOS**
  - RX characteristic (write) → Messages **from iOS to macOS**
- Shows Bluetooth state and advertising status
- Displays received messages in realtime
- Collapsible debug log panel (connect/disconnect, state changes, errors)
- Ability to manually send text messages to connected iOS centrals
- Safe UUID synchronization with the iOS app (same service + characteristics)
- Clean SwiftUI UI with reactive updates

---

## Technical Architecture

### BLE Service Layout

Service UUID:
- 7E57C000-2C8F-4F3C-9F91-8577E1891234

Characteristics:
- TX (Notify)
  - UUID: 7E57C001-2C8F-4F3C-9F91-8577E1891234
  - macOS → iOS notifications
- RX (Write / WriteWithoutResponse)
  - UUID: 7E57C002-2C8F-4F3C-9F91-8577E1891234
  - iOS → macOS messages

The iOS and macOS apps must use matching UUIDs to communicate.

---

## Files Overview

### MacChatPeripheral.swift
Implements the BLE logic:
- Starts/stops advertising
- Creates service/characteristics
- Handles subscriptions
- Handles incoming writes
- Sends messages
- Maintains internal logs
- Publishes connection and advertising state

### MacChatView.swift
Implements the UI:
- Status indicators (BT power, advertising)
- List of received messages
- Collapsible log section
- Text field for sending messages

---

## Running the App

1. Open the project in Xcode.
2. Ensure macOS Bluetooth is enabled.
3. Run the app.
4. The app will automatically:
   - Turn into a BLE peripheral
   - Advertise the “MacChat” device name
   - Wait for iOS to connect and subscribe

5. Open the iOS app `BTFinder` and connect from there.

You will see:
- Subscription events in the log
- Incoming messages in "Received messages"
- You can respond via the bottom text field

---

## Permissions

macOS requires Bluetooth capability in `Info.plist`:
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app communicates with an iOS device over Bluetooth LE</string>

In addition, the app must be able to access Bluetooth hardware in sandboxed environments (App Sandbox → Hardware → Bluetooth).

---

## Known Limitations

- Peripheral can only handle a single connected central at a time.
- No automatic reconnection or session persistence.
- No background mode (macOS apps normally do not need this).
- Not suitable for large or binary data payloads (only UTF-8 strings).

---
