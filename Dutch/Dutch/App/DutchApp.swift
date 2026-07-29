import AppIntents
import CloudKit
import SwiftUI
import UIKit

@main
struct DutchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    private let persistenceController = PersistenceController.shared

    init() {
        // Tells the system what this app's shortcuts take as parameters, so
        // the group picker in Shortcuts and Siri is populated rather than
        // empty. Cheap, and it has to happen before anything can run one.
        DutchShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
        // On the way to the background, not on the way in: the group the user
        // was last in is only settled once they stop looking at it, and
        // rewriting the quick action mid-session would change the Home Screen
        // under a menu somebody might have open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { refreshQuickActions() }
        }
    }

    /// Names the Home Screen quick action after the group it will open.
    ///
    /// "New Expense · Berlin Trip" says what the long-press will actually do,
    /// which matters because it does something different depending on where the
    /// user was last.
    ///
    /// This is the *only* place the quick action is defined. There is no static
    /// twin in `Dutch-Info.plist`, because the system shows the static list and
    /// the dynamic one together — `shortcutItems` is the dynamic list alone and
    /// never replaces the plist. Defining both put two identical "New Expense"
    /// rows in the menu.
    ///
    /// Written unconditionally, including with no group: a deleted group would
    /// otherwise keep its name on the Home Screen, pointing at nothing.
    @MainActor
    private func refreshQuickActions() {
        let name = GroupLookup
            .lastOpened(in: persistenceController.viewContext)?
            .name

        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.newExpense,
                localizedTitle: "New Expense",
                localizedSubtitle: name,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
                userInfo: nil
            )
        ]
    }
}

// MARK: - Quick Actions

/// The Home Screen quick action types, shared between the plist and the code
/// that handles them.
///
/// A mistyped identifier here is a long-press that does nothing at all, with no
/// error anywhere — so the string exists once.
enum QuickAction {
    /// Must match `UIApplicationShortcutItemType` in `Dutch-Info.plist`.
    static let newExpense = "net.smigi.Dutch.newExpense"

    /// Routes an activated quick action, if it is one this app knows.
    ///
    /// Falls through to the last opened group, exactly as `NewExpenseIntent`
    /// does — the two are the same action reached two ways, and they must not
    /// disagree about which group that means.
    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) {
        guard item.type == newExpense else { return }
        AppRouter.shared.open(ExpenseDefaults.lastOpenedGroupID.map { .newExpense(in: $0) })
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

        // Starts publishing the groups to Spotlight and watching for changes.
        // Here rather than in `DutchApp.init` because it needs a loaded store,
        // and because this is already where launch-time registration lives.
        MainActor.assumeIsolated {
            SpotlightIndexer.shared.start(reading: PersistenceController.shared.viewContext)
        }

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

/// Handles accepted CloudKit share invitations, Home Screen quick actions and
/// tapped Spotlight results.
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

    /// A quick action tapped while the app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated { QuickAction.handle(shortcutItem) }
        completionHandler(true)
    }

    /// A Spotlight result tapped while the app was already running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        MainActor.assumeIsolated { SpotlightIndexer.handle(userActivity) }
    }

    /// A quick action or Spotlight result that launched the app.
    ///
    /// Both paths are needed, for each of them. The system delivers a
    /// cold-launch action here and never calls the matching method above for
    /// it, so handling only those gives a quick action — or a search result —
    /// that works until you actually quit the app.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        MainActor.assumeIsolated {
            if let item = connectionOptions.shortcutItem {
                QuickAction.handle(item)
            }
            for activity in connectionOptions.userActivities {
                SpotlightIndexer.handle(activity)
            }
        }
    }
}
