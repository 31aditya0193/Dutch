import SwiftUI
import CloudKit

@main
struct DutchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit delivers sync notifications silently; without registering,
        // the app only picks up remote changes on the next launch.
        application.registerForRemoteNotifications()
        return true
    }

    /// Routes scene creation through `SceneDelegate` so share invitations can
    /// be handled — see the note there.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// MARK: - Scene Delegate

/// Handles accepted CloudKit share invitations.
///
/// This has to live on the *scene* delegate. The `UIApplicationDelegate`
/// equivalent is never called in a scene-based app, which is a quiet way to end
/// up with invitations that appear to do nothing when tapped.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            do {
                try await CloudSharingService.acceptShare(cloudKitShareMetadata)
            } catch {
                print("[Dutch] Failed to accept share: \(error.localizedDescription)")
            }
        }
    }
}
