//
//  DMGProcessor.swift
//  EasyDMG
//
//  Main class for processing DMG files
//  Replicates the logic from easyDMG.sh v1.03
//

import Foundation
import AppKit
import Combine

@MainActor
class DMGProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var statusMessage = ""

    // Process a DMG file (main entry point)
    func processDMG(at url: URL) async {
        guard !isProcessing else {
            print("Already processing a DMG file")
            return
        }

        isProcessing = true
        statusMessage = "Processing DMG files..."

        // Show startup notification
        NotificationManager.shared.showNotification(
            title: "EasyDMG",
            message: "Processing DMG files..."
        )

        // Validate the DMG file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            await handleError("File not found: \(url.lastPathComponent)")
            return
        }

        // Check for license agreement in DMG
        // TODO: Fix license detection - currently giving false positives without sandbox
        // if await hasLicenseAgreement(dmgPath: url.path) {
        //     print("DMG has license agreement - opening for manual installation")
        //     await openForManualInstallation(dmgPath: url.path, reason: "DMG requires manual installation")
        //     return
        // }

        // Mount the DMG
        guard let mountPoint = await mountDMG(at: url.path) else {
            await openForManualInstallation(dmgPath: url.path, reason: "DMG requires manual installation")
            return
        }

        // Find .app files in the mounted DMG
        let appFiles = findAppFiles(in: mountPoint)

        // Handle different scenarios
        switch appFiles.count {
        case 0:
            print("No .app found in DMG - opening for manual handling")
            await openForManualInstallation(mountPoint: mountPoint)
            return

        case 1:
            // Single app found - proceed with installation
            let appPath = appFiles[0]
            await installApp(from: appPath, mountPoint: mountPoint, dmgPath: url.path)

        default:
            // Multiple apps found - manual handling
            print("Multiple .app files found - opening for manual handling")
            await openForManualInstallation(mountPoint: mountPoint)
            return
        }

        isProcessing = false
    }

    // Check if DMG has a license agreement
    private func hasLicenseAgreement(dmgPath: String) async -> Bool {
        // Use hdiutil imageinfo to check for license
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["imageinfo", dmgPath]

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check for license agreement in output
            return output.contains("Software License Agreement") && output.contains("true")
        } catch {
            print("Error checking for license: \(error)")
            return false
        }
    }

    // Mount a DMG file and return the mount point
    private func mountDMG(at path: String) async -> String? {
        print("Mounting \(path)...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", path, "-nobrowse"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                print("Mount failed with status \(task.terminationStatus)")
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Check for error/warning keywords
            if output.lowercased().contains("error") ||
               output.lowercased().contains("failed") ||
               output.lowercased().contains("invalid") {
                print("Unexpected mount output detected")
                return nil
            }

            // Extract mount point from output (look for /Volumes/...)
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if let range = line.range(of: "/Volumes/") {
                    let mountPoint = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    // Clean up mount point (remove any trailing content after the path)
                    if let endIndex = mountPoint.firstIndex(where: { $0.isNewline || $0 == "\t" }) {
                        return String(mountPoint[..<endIndex])
                    }
                    return mountPoint
                }
            }

            print("Failed to determine mount point from output")
            return nil

        } catch {
            print("Error mounting DMG: \(error)")
            return nil
        }
    }

    // Find .app files in a directory (root level only)
    private func findAppFiles(in mountPoint: String) -> [String] {
        let fileManager = FileManager.default
        var appFiles: [String] = []

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: mountPoint)
            for item in contents {
                if item.hasSuffix(".app") {
                    let fullPath = (mountPoint as NSString).appendingPathComponent(item)
                    appFiles.append(fullPath)
                }
            }
        } catch {
            print("Error scanning mount point: \(error)")
        }

        print("Found \(appFiles.count) .app file(s)")
        return appFiles
    }

    // Install an app to /Applications
    private func installApp(from appPath: String, mountPoint: String, dmgPath: String) async {
        let appName = (appPath as NSString).lastPathComponent
        let destinationPath = "/Applications/\(appName)"

        // Check if app already exists
        if FileManager.default.fileExists(atPath: destinationPath) {
            print("App '\(appName)' already exists in Applications")

            // Show Skip/Replace dialog
            let shouldReplace = await showSkipReplaceDialog(appName: appName)

            if !shouldReplace {
                // User chose to skip
                NotificationManager.shared.showNotification(
                    title: "EasyDMG",
                    message: "Skipped installing \(appName)"
                )
                await unmountAndCleanup(mountPoint: mountPoint, dmgPath: dmgPath)
                isProcessing = false
                return
            }

            // User chose to replace - remove existing app
            do {
                try FileManager.default.removeItem(atPath: destinationPath)
            } catch {
                print("Error removing existing app: \(error)")
                await handleError("Failed to remove existing app")
                await unmountDMG(at: mountPoint)
                isProcessing = false
                return
            }
        }

        // Brief pause for UX pacing
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Copy app to /Applications
        print("Installing \(appName) to Applications folder...")
        do {
            try FileManager.default.copyItem(atPath: appPath, toPath: destinationPath)
        } catch {
            print("Error copying app: \(error)")
            await handleError("Failed to install app: \(error.localizedDescription)")
            await unmountDMG(at: mountPoint)
            isProcessing = false
            return
        }

        // Brief pause before cleanup
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Success!
        await unmountAndCleanup(mountPoint: mountPoint, dmgPath: dmgPath)

        // Show success notification
        let message = FileManager.default.fileExists(atPath: destinationPath) ? "Replaced \(appName)" : "Installed \(appName)"
        NotificationManager.shared.showNotification(
            title: "EasyDMG",
            message: message
        )

        // Reveal in Finder
        revealInFinder(path: destinationPath)

        isProcessing = false
    }

    // Show Skip/Replace dialog
    private func showSkipReplaceDialog(appName: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "EasyDMG"
                alert.informativeText = "\(appName) already exists in Applications.\n\nWhat would you like to do?"

                // Try to use EasyDMG icon
                if let iconPath = Bundle.main.path(forResource: "wizardhamster", ofType: "icns"),
                   let icon = NSImage(contentsOfFile: iconPath) {
                    alert.icon = icon
                }

                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Skip")

                let response = alert.runModal()
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

    // Unmount DMG
    private func unmountDMG(at mountPoint: String) async {
        print("Unmounting \(mountPoint)...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", mountPoint]

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus != 0 {
                print("Warning: Failed to detach DMG, trying force detach...")
                // Try force detach
                let forceTask = Process()
                forceTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                forceTask.arguments = ["detach", mountPoint, "-force"]
                try? forceTask.run()
                forceTask.waitUntilExit()
            }
        } catch {
            print("Error unmounting DMG: \(error)")
        }
    }

    // Unmount and cleanup (move DMG to trash)
    private func unmountAndCleanup(mountPoint: String, dmgPath: String) async {
        await unmountDMG(at: mountPoint)

        // Move DMG to trash
        let dmgURL = URL(fileURLWithPath: dmgPath)
        do {
            try FileManager.default.trashItem(at: dmgURL, resultingItemURL: nil)
        } catch {
            print("Warning: Failed to move DMG to trash: \(error)")
        }
    }

    // Open for manual installation (mount point)
    private func openForManualInstallation(mountPoint: String) async {
        NotificationManager.shared.showNotification(
            title: "EasyDMG",
            message: "DMG requires manual installation"
        )
        NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint))
    }

    // Open for manual installation (DMG path)
    private func openForManualInstallation(dmgPath: String, reason: String) async {
        NotificationManager.shared.showNotification(
            title: "EasyDMG",
            message: reason
        )
        NSWorkspace.shared.open(URL(fileURLWithPath: dmgPath))
    }

    // Reveal app in Finder
    private func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "/Applications")
    }

    // Handle errors
    private func handleError(_ message: String) async {
        print("Error: \(message)")
        NotificationManager.shared.showNotification(
            title: "EasyDMG Error",
            message: message
        )
        isProcessing = false
    }
}
