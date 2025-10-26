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
        // Hidden window group for background-only app
        // This allows file associations to work properly
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .commands {
            // Remove all menu commands for cleaner background operation
            CommandGroup(replacing: .newItem) { }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 0, height: 0)
    }
}

// AppDelegate to handle file opening events
class AppDelegate: NSObject, NSApplicationDelegate {
    private let dmgProcessor = DMGProcessor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("✅ EasyDMG launched in background mode")

        // Hide the empty window immediately
        NSApp.windows.first?.orderOut(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        print("✅ application(_:open:) called with \(urls.count) file(s): \(urls)")

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Prevent quit only while actively processing
        if dmgProcessor.isProcessing {
            print("⚠️ Still processing, preventing quit")
            return .terminateCancel
        }
        print("✅ Processing complete, allowing termination")
        return .terminateNow
    }
}
