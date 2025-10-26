//
//  SettingsWindow.swift
//  EasyDMG
//
//  Settings window with Setup, About, and Settings tabs
//

import SwiftUI
import AppKit
import Combine

struct SettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with app icon and title (always visible)
            HStack(spacing: 12) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("EasyDMG")
                        .font(.system(size: 24, weight: .bold))
                    Text("Version \(Bundle.main.appVersion)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Tabbed content
            TabView(selection: $selectedTab) {
                SetupTabView()
                    .tabItem {
                        Label("Setup", systemImage: "gearshape.2")
                    }
                    .tag(0)

                AboutTabView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(1)

                SettingsTabView(preferences: preferences)
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                    .tag(2)
            }
            .padding(20)
        }
        .frame(width: 550, height: 450)
    }
}

// MARK: - Setup Tab

struct SetupTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Quick usage intro
                Text("You can use 'Open With' on any DMG file to have EasyDMG seamlessly handle app installations and cleanup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                Divider()

                Text("Set as Default for DMG Files")
                    .font(.headline)

                Text("To make EasyDMG your default app for installing DMG files:")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    StepView(number: 1, text: "Right-click any .dmg file")
                    StepView(number: 2, text: "Select \"Get Info\"")
                    StepView(number: 3, text: "Under \"Open with:\", choose EasyDMG")
                    StepView(number: 4, text: "Click \"Change All...\"")
                }
                .padding(.leading, 8)

                // Screenshot
                Image("easydmg-select")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(8)
                    .shadow(radius: 2)
                    .padding(.top, 8)

                Text("Once set, double-clicking any DMG file will be handled by EasyDMG!")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

struct StepView: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(text)
        }
    }
}

// MARK: - About Tab

struct AboutTabView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Top spacing
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)

                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                }

                Text("EasyDMG")
                    .font(.system(size: 28, weight: .bold))

                Text("Version \(Bundle.main.appVersion)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                Text("Makes installing Mac apps effortless")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                HStack(spacing: 16) {
                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/yourusername/easydmg")!)
                    }) {
                        Label("GitHub", systemImage: "link")
                    }

                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://github.com/yourusername/easydmg/issues")!)
                    }) {
                        Label("Report Issue", systemImage: "exclamationmark.bubble")
                    }
                }
                .padding(.top, 8)

                // Bottom spacing
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 30)

                Text("Created with care for the Mac community")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        }
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Installation Preferences")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Automatically move DMG to trash after installation", isOn: $preferences.autoTrashDMG)
                        .toggleStyle(.checkbox)

                    Toggle("Reveal app in Finder after installation", isOn: $preferences.revealInFinder)
                        .toggleStyle(.checkbox)
                }
                .padding(.leading, 8)

                Divider()
                    .padding(.vertical, 8)

                Text("These settings only apply to automatic installations. Manual installations will always open the mounted volume.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - User Preferences

class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    @Published var autoTrashDMG: Bool {
        didSet {
            UserDefaults.standard.set(autoTrashDMG, forKey: "autoTrashDMG")
        }
    }

    @Published var revealInFinder: Bool {
        didSet {
            UserDefaults.standard.set(revealInFinder, forKey: "revealInFinder")
        }
    }

    private init() {
        self.autoTrashDMG = UserDefaults.standard.object(forKey: "autoTrashDMG") as? Bool ?? true
        self.revealInFinder = UserDefaults.standard.object(forKey: "revealInFinder") as? Bool ?? true
    }
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
