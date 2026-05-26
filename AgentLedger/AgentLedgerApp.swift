import SwiftUI
import Amplify
import AWSCognitoAuthPlugin
import AWSAPIPlugin
import AWSS3StoragePlugin

class AppDelegate: NSObject, UIApplicationDelegate {
    let pushManager = PushNotificationManager.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Suppress noisy system network logs (tcp_input, nw_*, etc.)
        setenv("OS_ACTIVITY_MODE", "default", 1)
        setenv("CFNETWORK_DIAGNOSTICS", "0", 1)

        UNUserNotificationCenter.current().delegate = pushManager
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        pushManager.didRegisterForRemoteNotifications(with: deviceToken)
        print("[PUSH] APNs token received in AppDelegate")
        // Token save is handled by RootView.requestPushPermissions to avoid duplicates
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        pushManager.didFailToRegisterForRemoteNotifications(with: error)
    }
}

@main
struct AgentLedgerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var amplifyService = AmplifyService.shared

    init() {
        configureAmplify()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(amplifyService)
        }
    }

    private func configureAmplify() {
        // Check if amplify_outputs.json exists in bundle
        if let path = Bundle.main.path(forResource: "amplify_outputs", ofType: "json") {
            print("Found amplify_outputs.json at: \(path)")
        } else {
            print("ERROR: amplify_outputs.json NOT FOUND in app bundle!")
            print("Make sure the file is added to the Xcode project and included in the app target.")
            return
        }

        do {
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.add(plugin: AWSAPIPlugin())
            try Amplify.add(plugin: AWSS3StoragePlugin())
            try Amplify.configure(with: .amplifyOutputs)
            AmplifyService.shared.isConfigured = true
            print("Amplify configured successfully")
        } catch {
            AmplifyService.shared.isConfigured = false
            print("ERROR configuring Amplify: \(error)")
            print("App will run in offline mode with sample data.")
        }
    }
}

struct RootView: View {
    @EnvironmentObject var amplifyService: AmplifyService
    @StateObject private var viewModel = AppViewModel()
    @State private var isCheckingAuth = true
    @State private var didSetupPush = false
    @State private var didInitialSync = false

    var body: some View {
        Group {
            if isCheckingAuth {
                ProgressView("Loading...")
            } else if amplifyService.isSignedIn {
                ContentView()
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            } else {
                AuthView()
                    .environmentObject(amplifyService)
            }
        }
        .task {
            await amplifyService.checkAuthStatus()
            isCheckingAuth = false

            if amplifyService.isSignedIn {
                didInitialSync = true
                viewModel.syncWithAmplify(amplifyService)
                viewModel.startMessageSubscription(amplifyService)
                await setupPushOnce()
            }
        }
        .onChange(of: amplifyService.isSignedIn) { _, newValue in
            if newValue && !didInitialSync {
                Task {
                    viewModel.syncWithAmplify(amplifyService)
                    viewModel.startMessageSubscription(amplifyService)
                    await setupPushOnce()
                }
            }
            didInitialSync = false
        }
    }

    private func setupPushOnce() async {
        guard !didSetupPush else { return }
        didSetupPush = true

        let pushManager = PushNotificationManager.shared
        let granted = await pushManager.requestAuthorization()
        if granted {
            // Wait for APNs device token to arrive (up to 5 seconds)
            for _ in 0..<10 {
                if pushManager.deviceToken != nil { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if pushManager.deviceToken != nil {
                print("[PUSH] RootView: saving device token to backend...")
                await pushManager.saveTokenToBackend(amplifyService)
            } else {
                print("[PUSH] RootView: device token not available after 5s")
            }
        }
    }
}
