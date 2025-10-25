//
//  ContentView.swift
//  EasyDMG
//
//  Created by Jeff Schumann on 10/24/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var dmgProcessor: DMGProcessor

    var body: some View {
        VStack(spacing: 20) {
            // App icon or placeholder
            Image(systemName: "opticaldiscdrive")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("EasyDMG")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Drop a DMG file onto the app icon or double-click a DMG to install")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Button("Select DMG File...") {
                selectDMGFile()
            }
            .buttonStyle(.borderedProminent)

            if dmgProcessor.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)

                Text(dmgProcessor.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }

    private func selectDMGFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "dmg")!]
        panel.message = "Select a DMG file to install"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await dmgProcessor.processDMG(at: url)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DMGProcessor())
}
