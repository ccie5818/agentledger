import Foundation
import UserNotifications
import UIKit

/// Manages push notification registration and device token storage
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()

    @Published var deviceToken: String?
    @Published var isAuthorized = false
    @Published var pendingConversationID: String?
    private var isTokenSaved = false
    private var isSavingToken = false

    private override init() {
        super.init()
    }

    // MARK: - Request Permission

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isAuthorized = granted
            }
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("Push notification authorization error: \(error)")
            return false
        }
    }

    // MARK: - Handle Device Token

    func didRegisterForRemoteNotifications(with deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("APNs device token: \(token)")
        self.deviceToken = token
    }

    func didFailToRegisterForRemoteNotifications(with error: Error) {
        print("Failed to register for push notifications: \(error)")
    }

    // MARK: - Save Token to Backend

    func saveTokenToBackend(_ amplifyService: AmplifyService) async {
        // Prevent multiple simultaneous saves
        guard !isTokenSaved && !isSavingToken else {
            print("[PUSH] Token already saved or save in progress, skipping")
            return
        }
        guard let token = deviceToken else {
            print("[PUSH] No device token to save")
            return
        }
        guard amplifyService.isConfigured else { return }

        isSavingToken = true
        await amplifyService.updateDeviceToken(token, platform: "IOS")
        isTokenSaved = true
        isSavingToken = false
    }

    // MARK: - Handle Incoming Notification

    func handleNotification(userInfo: [AnyHashable: Any]) {
        if let conversationID = userInfo["conversationID"] as? String {
            print("[PUSH] Notification tapped for conversation: \(conversationID)")
            // Store for cold launch (ContentView might not exist yet)
            pendingConversationID = conversationID
            // Also post for warm launch (ContentView is already listening)
            NotificationCenter.default.post(
                name: .openConversation,
                object: nil,
                userInfo: ["conversationID": conversationID]
            )
        }
    }

    // MARK: - Clear Badge

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to clear badge: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    /// Called when notification arrives while app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    /// Called when user taps a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        handleNotification(userInfo: response.notification.request.content.userInfo)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openConversation = Notification.Name("openConversation")
}
