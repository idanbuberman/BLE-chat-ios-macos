
# BTFinder – iOS App

BTFinder is an iOS BLE Central app built in SwiftUI.  
It discovers nearby BLE devices, connects to one device at a time, and enables a live **text-chat** over Bluetooth with a macOS app acting as a BLE Peripheral.

This project demonstrates:

- Clean CoreBluetooth architecture. Singleton, but in real world would have probably use DI in order to mock at UT.
- Efficient periodic scanning (non-spammy list updates).
- Stable connection management.
- Per-device chat history.
- Unread messages badge on the main screen.
- Navigation using SwiftUI’s modern `NavigationStack`.

---

## Features

### 🔍 **1. BLE Device Scanning**
- User can enable “Auto Scan” mode.
- Scans are executed **once every X seconds** (interval configurable by the user).
- Between scan windows the device list stays stable.
- Old devices are pruned using a “left outer join” approach.

### 🔗 **2. Single Active Connection**
The app always maintains **one** connected BLE device:

- Selecting a device:
  - Disconnects any previously connected device.
  - Connects to the new one.
- The currently connected device name appears at the top (“Connected device: XYZ”).
- A manual “Disconnect” (X icon) is also available.

### 💬 **3. BLE Chat (Notify + Write)**
The app supports text chat with a peripheral device (the macOS sample):

- Uses a custom BLE “Chat” Service with matching UUIDs.
- RX characteristic (write) is used to send data iOS → Mac.
- TX characteristic (notify) is used to receive data Mac → iOS.
- Messages are persisted per device.

SwiftUI chat screen includes:
- Full message history.
- “Connected” status indicator.
- Text input & send button.
  
### 🔔 **4. Unread Messages Badge**
While on the device list screen:
- New messages (Mac → iOS) increment an unread counter.
- A floating red circle badge appears on the **Open chat** button.
- Opening the chat resets unread count.

Badge behavior:
- 1-99 → show number
- 100+ → show `"..."`

### 🧭 **5. SwiftUI Navigation**
- Uses **NavigationStack** + `.navigationDestination`.
- Clean state-driven presentation (`isChatActive`).
- Automatically restores unread handling when navigating back.

---

## Architecture Overview

### 📁 File Structure

BTFinder/
│
├── BTListView.swift <-- Main device list screen
├── BTListViewModel.swift <-- Scanning, connection mgmt, unread badge
│
├── DeviceDetailView.swift <-- Chat UI
├── DeviceDetailViewModel.swift <-- Chat logic + message history
│
├── BluetootheService.swift <-- BLE model + BluetoothService implementation
│
└── BTFinderApp.swift <-- App entry point (SwiftUI)

---

## Component Responsibilities

### 🧠 **BTListViewModel**
Handles:

- Periodic scanning  
- Timer management  
- Filtering + pruning devices  
- Connecting / disconnecting  
- Holding `connectedDevice`  
- Counting unread messages  
- Routing to the chat screen  

### 📡 **BluetoothService**
A singleton CoreBluetooth wrapper implementing `BluetoothServiceProtocol`.

It handles:

- CBCentralManager setup  
- Scanning  
- `didDiscover` → updates device list  
- Connecting & disconnecting peripherals  
- Discovering chat service & characteristics  
- Sending + receiving BLE messages  
- Persisting message history  
- Exposing callbacks:
  - `onDevicesUpdated`
  - `onMessageReceived`
  - `onDeviceDisconnected`

### 💬 **DeviceDetailViewModel**
Responsible for:

- Loading stored message history  
- Listening for new messages for *that specific device*  
- Sending outgoing messages  
- Updating the chat UI  

### 🎨 **UI (SwiftUI)**

- **BTListView**
  - Shows device list & scan controls  
  - Shows connected device  
  - Badge for unread messages  
  - Navigation to chat  

- **DeviceDetailView**
  - Displays message log  
  - Text field to send messages  
  - Simple connection indicator  

---

## BLE Service Definitions

The iOS app expects the macOS app to advertise:

| Purpose | UUID |
|---------|------|
| **Chat Service** | `7E57C000-2C8F-4F3C-9F91-8577E1891234` |
| **TX Characteristic (notify → iOS)** | `7E57C001-2C8F-4F3C-9F91-8577E1891234` |
| **RX Characteristic (write → Mac)** | `7E57C002-2C8F-4F3C-9F91-8577E1891234` |

The macOS app must use the same values.

---

## Running the App

### 1. Build & Run (iOS)
- Must run on a **real device** (BLE unavailable on iOS simulator).
- Bluetooth must be enabled.

### 2. Pair With macOS App (Optional)
- Open the macOS chat peripheral app (not included here).
- It should begin advertising.
- On iOS:
  - Tap **Start scanning**
  - Wait for your Mac to appear
  - Tap a device → it becomes **Connected**
  - Tap **Open chat**
  - Type messages both ways

### 3. Disconnect Behavior
If the macOS app closes:
- CoreBluetooth triggers `didDisconnectPeripheral`.
- `BluetoothScanViewModel` clears:
  - `connectedDevice`
  - `unreadMessagesCount`
- UI refreshes automatically.

---

## Possible Improvements

- Add error banners or toast messages
- Background BLE mode with state restoration
- Multiple concurrent connections
- Reliable write queue + backpressure handling
- Message timestamps
- Better chat formatting (bubbles, alignment)
- Persisting history to disk
