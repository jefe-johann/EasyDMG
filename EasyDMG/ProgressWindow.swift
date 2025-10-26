//
//  ProgressWindow.swift
//  EasyDMG
//
//  Floating progress window for background processing
//

import SwiftUI
import AppKit

@MainActor
class ProgressWindowController: NSWindowController {
    static let shared = ProgressWindowController()

    private init() {
        // Create a compact notification-style window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 75),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "EasyDMG"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false

        super.init(window: window)

        // Set up the SwiftUI content view
        let contentView = InstallProgressView()
        window.contentView = NSHostingView(rootView: contentView)

        // Position in top-right corner (notification area)
        positionInTopRight()
    }

    private func positionInTopRight() {
        guard let window = window, let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height

        // Position 20px from right, 50px from top
        let x = screenFrame.maxX - windowWidth - 20
        let y = screenFrame.maxY - windowHeight - 50

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(message: String, progress: Double = 0.0) {
        print("🪟 ProgressWindow.show() called with message: '\(message)', progress: \(progress)")
        guard let window = window else {
            print("❌ Window is nil!")
            return
        }

        // Update the message and progress
        if let hostingView = window.contentView as? NSHostingView<InstallProgressView> {
            hostingView.rootView = InstallProgressView(message: message, progress: progress)
            print("🪟 Updated hosting view with message and progress")
        }

        // Position in top-right corner and show the window
        print("🪟 Positioning and showing window...")
        positionInTopRight()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("🪟 Window should now be visible!")
    }

    func update(message: String, progress: Double) {
        print("🪟 ProgressWindow.update() called with message: '\(message)', progress: \(progress)")
        guard let window = window else {
            print("❌ Window is nil!")
            return
        }

        // Update the message and progress
        if let hostingView = window.contentView as? NSHostingView<InstallProgressView> {
            hostingView.rootView = InstallProgressView(message: message, progress: progress)
            print("🪟 Updated message and progress")
        }
    }

    func hide() {
        print("🪟 ProgressWindow.hide() called")
        window?.orderOut(nil)
        print("🪟 Window hidden")
    }
}

// SwiftUI view for the progress window
struct InstallProgressView: View {
    var message: String = "Processing..."
    var progress: Double = 0.0

    var body: some View {
        HStack(spacing: 12) {
            // EasyDMG wizard hamster icon
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 48, height: 48)
            } else {
                // Fallback if app icon not found
                Image(systemName: "opticaldiscdrive.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }

            // Text and progress bar
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                SwiftUI.ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 112/255, green: 113/255, blue: 112/255))
            }
        }
        .tint(Color(red: 112/255, green: 113/255, blue: 112/255))
        .environment(\.controlActiveState, .key)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(VisualEffectView())
    }
}

// Native blur effect
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
