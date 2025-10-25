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
    @StateObject private var dmgProcessor = DMGProcessor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dmgProcessor)
                .onOpenURL { url in
                    // Handle DMG files opened via double-click or drag-drop
                    handleOpenedFile(url)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open DMG...") {
                    selectDMGFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private func handleOpenedFile(_ url: URL) {
        // Verify it's a DMG file
        guard url.pathExtension.lowercased() == "dmg" else {
            print("Ignoring non-DMG file: \(url.path)")
            return
        }

        print("Opening DMG file: \(url.path)")

        // Process the DMG file
        Task {
            await dmgProcessor.processDMG(at: url)
        }
    }

    private func selectDMGFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "dmg")!]
        panel.message = "Select a DMG file to install"

        if panel.runModal() == .OK, let url = panel.url {
            handleOpenedFile(url)
        }
    }
}

// AppDelegate to handle file opening events
class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        print("AppDelegate received files: \(urls)")
        for url in urls {
            if url.pathExtension.lowercased() == "dmg" {
                NotificationCenter.default.post(name: .openDMGFile, object: url)
            }
        }
    }
}

extension Notification.Name {
    static let openDMGFile = Notification.Name("openDMGFile")
}
