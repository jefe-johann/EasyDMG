//
//  NotificationManager.swift
//  EasyDMG
//
//  Handles user notifications using UserNotifications framework
//

import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    override private init() {
        super.init()
        setupNotifications()
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Request notification permissions
        requestPermission()
    }

    func requestPermission() {
        let center = UNUserNotificationCenter.current()

        // First check current authorization status
        center.getNotificationSettings { settings in
            print("📱 Current notification authorization status: \(settings.authorizationStatus.rawValue)")
            print("📱 Alert setting: \(settings.alertSetting.rawValue)")
            print("📱 Sound setting: \(settings.soundSetting.rawValue)")

            switch settings.authorizationStatus {
            case .notDetermined:
                print("📱 Requesting notification permission...")
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if granted {
                        print("✅ Notification permission granted")
                    } else {
                        print("❌ Notification permission denied")
                    }
                    if let error = error {
                        print("❌ Notification permission error: \(error)")
                    }
                }
            case .denied:
                print("⚠️ Notifications are denied - user needs to enable in System Settings")
            case .authorized:
                print("✅ Notifications already authorized")
            case .provisional:
                print("📱 Notifications provisionally authorized")
            case .ephemeral:
                print("📱 Notifications ephemeral")
            @unknown default:
                print("⚠️ Unknown notification authorization status")
            }
        }
    }

    func showNotification(title: String, message: String) {
        print("📬 Attempting to show notification: '\(title)' - '\(message)'")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        // Add subtitle for better visibility
        content.subtitle = ""

        // Create request with unique identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // nil trigger means show immediately
        )

        // Add notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error showing notification: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
            } else {
                print("✅ Notification added successfully")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // This allows notifications to show even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("📬 Will present notification: \(notification.request.content.title)")
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse,
                              withCompletionHandler completionHandler: @escaping () -> Void) {
        print("📬 User interacted with notification: \(response.notification.request.content.title)")
        completionHandler()
    }
}
