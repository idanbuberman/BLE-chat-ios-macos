//
//  BTFinderApp.swift
//  BTFinder
//
//  Created by jenkins on 16/11/2025.
//

import SwiftUI
import UserNotifications

@main
struct BTFinderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.badge, .sound, .alert]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            BluetoothScanView()
                .environmentObject(AppLifecycle.shared)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                AppLifecycle.shared.isActive = true
                
                // Clear badge when app returns to foreground
                UNUserNotificationCenter.current().setBadgeCount(0)
            case .inactive, .background:
                AppLifecycle.shared.isActive = false
            @unknown default:
                break
            }
        }
    }
}

final class AppLifecycle: ObservableObject {
    static let shared = AppLifecycle()
    
    @Published var isActive: Bool = true
}
