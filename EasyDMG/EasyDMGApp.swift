//
//  EasyDMGApp.swift
//  EasyDMG
//
//  Created by Jeff Schumann on 10/24/25.
//

import SwiftUI

@main
struct EasyDMGApp: App {
    @StateObject private var dmgProcessor = DMGProcessor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dmgProcessor)
                .onOpenURL { url in
                    // Handle DMG files opened via double-click or drag-drop
                    handleOpenedFile(url)
                }
        }
        .handlesExternalEvents(matching: [])
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
}
