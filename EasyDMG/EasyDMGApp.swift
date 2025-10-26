//
//  EasyDMGApp.swift
//  EasyDMG
//
//  Created by Jeff Schumann on 10/24/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct EasyDMGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window - shown when launched directly
        WindowGroup("EasyDMG") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .commands {
            // Remove file menu commands
            CommandGroup(replacing: .newItem) { }
        }
    }
}

// AppDelegate to handle file opening events
class AppDelegate: NSObject, NSApplicationDelegate {
    private let dmgProcessor = DMGProcessor()
    private var launchedWithFiles = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // This is called before application(_:open:)
        // We use it to detect if files will be opened
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if launched with files by seeing if application(_:open:) was called
        // We'll set launchedWithFiles in that method

        // Small delay to let file opening happen first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !self.launchedWithFiles {
                // Launched directly - show settings window with dock icon
                print("✅ Launched directly - showing settings window")
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                // Launched with DMG - stay in background
                print("✅ Launched with DMG - staying in background")
                NSApp.setActivationPolicy(.accessory)
                self.hideSettingsWindow()
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
        // Prevent quit only while actively processing
        if dmgProcessor.isProcessing {
            print("⚠️ Still processing, preventing quit")
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
}
