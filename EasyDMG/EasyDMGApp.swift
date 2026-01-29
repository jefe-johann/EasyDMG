//
//  EasyDMGApp.swift
//  EasyDMG
//
//  Created by Jeff Schumann on 10/24/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications
import Sparkle

@main
struct EasyDMGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window - shown when launched directly
        WindowGroup("EasyDMG") {
            SettingsView()
                .environmentObject(appDelegate.updaterViewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            // Remove file menu commands
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// AppDelegate to handle file opening events
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let dmgProcessor = DMGProcessor()
    private var launchedWithFiles = false
    private let updaterController: SPUStandardUpdaterController
    private var isWaitingForUpdateCheck = false

    // Update check interval (24 hours)
    private let updateCheckInterval: TimeInterval = 24 * 60 * 60

    // View model for Sparkle updates UI
    let updaterViewModel: CheckForUpdatesViewModel

    override init() {
        // Initialize Sparkle updater (start it so canCheckForUpdates works)
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterViewModel = CheckForUpdatesViewModel(updater: updaterController.updater)
        super.init()
    }

    // Expose updater for settings UI
    var updater: SPUUpdater {
        updaterController.updater
    }

    // MARK: - Update Check Timing

    private var lastUpdateCheck: Date? {
        get {
            UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck")
        }
    }

    private func shouldCheckForUpdates() -> Bool {
        guard let lastCheck = lastUpdateCheck else {
            // Never checked before
            return true
        }

        let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
        return timeSinceLastCheck >= updateCheckInterval
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // This is called before application(_:open:)
        // We use it to detect if files will be opened
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set notification delegate to show notifications even when app is active
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("❌ Notification authorization error: \(error)")
            } else if granted {
                print("✅ Notification authorization granted")
            } else {
                print("⚠️ Notification authorization denied")
            }
        }

        // Check if launched with files by seeing if application(_:open:) was called
        // We'll set launchedWithFiles in that method

        // Small delay to let file opening happen first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.launchedWithFiles {
                // Launched directly - show settings window with dock icon
                print("✅ Launched directly - showing settings window")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                // Always check for updates when settings window is opened
                print("✅ Checking for updates (settings window)")
                self.updater.checkForUpdatesInBackground()
                self.lastUpdateCheck = Date()
            } else {
                // Launched with DMG - stay in background
                print("✅ Launched with DMG - staying in background")
                NSApp.setActivationPolicy(.accessory)
                self.hideSettingsWindow()

                // Only check for updates if 24+ hours have passed
                if self.shouldCheckForUpdates() {
                    print("✅ Checking for updates (24+ hours since last check)")
                    self.isWaitingForUpdateCheck = true
                    self.updater.checkForUpdatesInBackground()
                    self.lastUpdateCheck = Date()

                    // Give the update check time to complete before allowing quit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                        print("✅ Update check timeout reached, allowing quit")
                        self.isWaitingForUpdateCheck = false
                    }
                } else {
                    print("ℹ️ Skipping update check (checked recently)")
                }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        print("✅ application(_:open:) called with \(urls.count) file(s): \(urls)")
        launchedWithFiles = true

        // Hide settings window if it's visible (but not progress window)
        hideSettingsWindow()

        // Stay in background mode when processing DMG
        NSApp.setActivationPolicy(.accessory)

        for url in urls {
            print("✅ Checking file: \(url.path)")
            if url.pathExtension.lowercased() == "dmg" {
                print("✅ Processing DMG file: \(url.lastPathComponent)")
                Task { @MainActor in
                    await dmgProcessor.processDMG(at: url)
                }
            } else {
                print("⚠️ Not a DMG file, ignoring: \(url.path)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Quit when settings window is closed
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Prevent quit while actively processing
        if dmgProcessor.isProcessing {
            print("⚠️ Still processing, preventing quit")
            return .terminateCancel
        }

        // Prevent quit while waiting for update check to complete
        if isWaitingForUpdateCheck {
            print("⚠️ Waiting for update check, preventing quit")
            return .terminateCancel
        }

        print("✅ Allowing termination")
        return .terminateNow
    }

    private func hideSettingsWindow() {
        // Only hide settings windows, not the progress window
        for window in NSApp.windows {
            // Don't hide the progress window (it has .floating level)
            if window.level != .floating {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground/active
        completionHandler([.banner, .sound])
    }
}
