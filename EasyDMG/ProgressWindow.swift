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
        // Create a small floating window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "EasyDMG"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)

        // Set up the SwiftUI content view
        let contentView = InstallProgressView()
        window.contentView = NSHostingView(rootView: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(message: String) {
        print("🪟 ProgressWindow.show() called with message: '\(message)'")
        guard let window = window else {
            print("❌ Window is nil!")
            return
        }

        // Update the message
        if let hostingView = window.contentView as? NSHostingView<InstallProgressView> {
            hostingView.rootView = InstallProgressView(message: message)
            print("🪟 Updated hosting view with message")
        }

        // Show the window
        print("🪟 Centering and showing window...")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("🪟 Window should now be visible!")
    }

    func update(message: String) {
        print("🪟 ProgressWindow.update() called with message: '\(message)'")
        guard let window = window else {
            print("❌ Window is nil!")
            return
        }

        // Update the message
        if let hostingView = window.contentView as? NSHostingView<InstallProgressView> {
            hostingView.rootView = InstallProgressView(message: message)
            print("🪟 Updated message")
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

    var body: some View {
        VStack(spacing: 16) {
            // Animated icon
            Image(systemName: "gear.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            SwiftUI.ProgressView()
                .scaleEffect(0.8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
