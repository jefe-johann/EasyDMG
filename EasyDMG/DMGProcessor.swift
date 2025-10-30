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
import UserNotifications

@MainActor
class DMGProcessor: ObservableObject {
    @Published var isProcessing = false
    private var currentFeedbackMode: FeedbackMode = .progressBar

    private func showProgress(_ message: String, progress: Double) {
        print("📝 \(message) (\(Int(progress * 100))%)")

        // Only show progress window if feedback mode is progress bar
        if currentFeedbackMode == .progressBar {
            ProgressWindowController.shared.update(message: message, progress: progress)
        }
    }

    private func sendNotification(title: String, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        // Use 1-second delay trigger to ensure notification delivers after app quits
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("❌ Notification error: \(error)")
        }
    }

    // Request notification permissions if needed
    private func requestNotificationPermissionsIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    // Get the effective feedback mode (fallback to progress bar if notifications denied)
    private func effectiveFeedbackMode() async -> FeedbackMode {
        let userMode = UserPreferences.shared.feedbackMode

        // If user wants notifications, check if permission is granted
        if userMode == .notification {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .denied {
                return .progressBar
            }
        }

        return userMode
    }

    // Process a DMG file (main entry point)
    func processDMG(at url: URL) async {
        guard !isProcessing else {
            return
        }

        isProcessing = true

        // Request notification permissions early (before checking effective mode)
        await requestNotificationPermissionsIfNeeded()

        // Determine effective feedback mode (with fallback for denied notifications)
        currentFeedbackMode = await effectiveFeedbackMode()

        // Show progress window only in progress bar mode
        if currentFeedbackMode == .progressBar {
            ProgressWindowController.shared.show(message: "Preparing...", progress: 0.0)
        }

        // Validate the DMG file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            await handleError("File not found: \(url.lastPathComponent)")
            return
        }

        // Check for license agreement in DMG
        // TODO: Fix license detection - currently giving false positives without sandbox
        // if await hasLicenseAgreement(dmgPath: url.path) {
        //     await openForManualInstallation(dmgPath: url.path, reason: "DMG requires manual installation")
        //     return
        // }

        // Mount the DMG (Step 1: 0% → 20%)
        showProgress("Mounting disk image...", progress: 0.0)
        guard let mountPoint = await mountDMG(at: url.path) else {
            await openForManualInstallation(dmgPath: url.path, reason: "DMG requires manual installation")
            return
        }

        // Find .app files in the mounted DMG (Step 2 starts: 20%)
        showProgress("Scanning for apps...", progress: 0.2)
        let appFiles = findAppFiles(in: mountPoint)

        // Handle different scenarios
        switch appFiles.count {
        case 0:
            print("No .app files found")
            await openForManualInstallation(mountPoint: mountPoint)
            return

        case 1:
            // Single app found - proceed with installation
            let appPath = appFiles[0]
            await installApp(from: appPath, mountPoint: mountPoint, dmgPath: url.path)

        default:
            print("Multiple .app files found (\(appFiles.count))")
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
        task.arguments = ["attach", path, "-nobrowse", "-readonly", "-noautoopen"]

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
            // Show Skip/Replace dialog
            let shouldReplace = await showSkipReplaceDialog(appName: appName)

            if !shouldReplace {
                // User chose to skip
                print("Installation cancelled by user")
                await unmountAndCleanup(mountPoint: mountPoint, dmgPath: dmgPath)
                ProgressWindowController.shared.hide()
                isProcessing = false

                // Quit after user skips
                print("✅ User skipped installation, quitting app")
                NSApp.terminate(nil)
                return
            }

            // User chose to replace - show progress if in progress bar mode
            if currentFeedbackMode == .progressBar {
                ProgressWindowController.shared.show(message: "Removing old version...", progress: 0.2)
            }
            do {
                try FileManager.default.removeItem(atPath: destinationPath)
            } catch {
                await handleError("Failed to remove old version")
                await unmountDMG(at: mountPoint)
                isProcessing = false
                return
            }
        }

        // Copy app to /Applications (Step 2: 20% → 40%)
        showProgress("Installing to Applications...", progress: 0.2)
        do {
            try FileManager.default.copyItem(atPath: appPath, toPath: destinationPath)

            // Remove quarantine attributes to prevent false "needs update" states
            // This replicates the behavior of manual Finder drag-and-drop installation
            await removeQuarantineAttributes(from: destinationPath)

            // Send notification if in notification mode
            if currentFeedbackMode == .notification {
                await sendNotification(title: "EasyDMG", message: "\(appName) installed successfully")
            }
        } catch {
            await handleError("Installation failed")
            await unmountDMG(at: mountPoint)
            isProcessing = false
            return
        }

        // Reveal in Finder (Step 3: 40% → 60%)
        if UserPreferences.shared.revealInFinder {
            showProgress("Opening in Finder...", progress: 0.4)
            revealInFinder(path: destinationPath)
        } else {
            showProgress("Finalizing installation...", progress: 0.4)
        }

        // Unmount DMG (Step 4: 60% → 80%)
        showProgress("Cleaning up...", progress: 0.6)
        await unmountDMG(at: mountPoint)

        // Move to Trash (Step 5: 80% → 100%)
        if UserPreferences.shared.autoTrashDMG {
            showProgress("Moving disk image to trash...", progress: 0.8)
            let dmgURL = URL(fileURLWithPath: dmgPath)
            do {
                try FileManager.default.trashItem(at: dmgURL, resultingItemURL: nil)
            } catch {
                print("Warning: Failed to move DMG to trash: \(error)")
            }
        } else {
            showProgress("Keeping disk image...", progress: 0.8)
        }

        // Handle completion based on feedback mode
        if currentFeedbackMode == .progressBar {
            // Show completion message briefly in progress bar mode
            showProgress("Installation complete!", progress: 1.0)
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        }

        // Hide the progress window (only visible in progress bar mode)
        ProgressWindowController.shared.hide()
        isProcessing = false

        // Quit the app after processing is complete
        // Note: Notifications use 1-second trigger, so they'll deliver after app quits
        print("✅ Processing complete, quitting app")
        NSApp.terminate(nil)
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

        let errorPipe = Pipe()
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("✓ Clean detach succeeded")
                return
            }

            // Read error output
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            print("Detach failed: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")

            // Check for "resource busy" and retry once
            if errorOutput.lowercased().contains("resource busy") {
                print("Resource busy, waiting 250ms and retrying...")
                try? await Task.sleep(nanoseconds: 250_000_000)

                let retryTask = Process()
                retryTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                retryTask.arguments = ["detach", mountPoint]
                try? retryTask.run()
                retryTask.waitUntilExit()

                if retryTask.terminationStatus == 0 {
                    print("✓ Retry detach succeeded")
                    return
                }
            }

            // Force detach as last resort
            print("Using force detach...")
            let forceTask = Process()
            forceTask.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            forceTask.arguments = ["detach", mountPoint, "-force"]
            try? forceTask.run()
            forceTask.waitUntilExit()
            print("✓ Force detach completed")
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

    // Remove quarantine attributes from installed app
    // This prevents apps with auto-update mechanisms from incorrectly detecting
    // "needs update" states that can cause unwanted behavior
    private func removeQuarantineAttributes(from path: String) async {
        print("Removing quarantine attributes from \(path)...")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        task.arguments = ["-dr", "com.apple.quarantine", path]

        let errorPipe = Pipe()
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                print("✓ Quarantine attributes removed")
            } else {
                // Read error but don't fail - this is non-critical
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                print("Note: Could not remove quarantine attributes: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        } catch {
            // Non-fatal error - log and continue
            print("Note: xattr command failed: \(error)")
        }
    }

    // Open for manual installation (mount point)
    private func openForManualInstallation(mountPoint: String) async {
        NSWorkspace.shared.open(URL(fileURLWithPath: mountPoint))
        ProgressWindowController.shared.hide()
        isProcessing = false

        // Quit after opening for manual install
        print("✅ Opened for manual installation, quitting app")
        NSApp.terminate(nil)
    }

    // Open for manual installation (DMG path)
    private func openForManualInstallation(dmgPath: String, reason: String) async {
        NSWorkspace.shared.open(URL(fileURLWithPath: dmgPath))
        ProgressWindowController.shared.hide()
        isProcessing = false

        // Quit after opening for manual install
        print("✅ Opened for manual installation, quitting app")
        NSApp.terminate(nil)
    }

    // Reveal app in Finder
    private func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "/Applications")
    }

    // Handle errors
    private func handleError(_ message: String) async {
        print("Error: \(message)")
        showProgress("Error: \(message)", progress: 0.0)

        // Keep error visible for 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        ProgressWindowController.shared.hide()
        isProcessing = false

        // Quit after error
        print("✅ Error handled, quitting app")
        NSApp.terminate(nil)
    }
}
