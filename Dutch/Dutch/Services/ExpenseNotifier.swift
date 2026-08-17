/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit
import UIKit
import UserNotifications

/// Tells the person holding this phone that somebody else added an expense.
///
/// There is no server here to send a push, and there never will be — so this is
/// not a push notification in the usual sense. It is a **local** notification,
/// posted by this device about something it has already downloaded. The chain
/// is:
///
/// 1. CloudKit sends `NSPersistentCloudKitContainer` a silent push;
/// 2. the container imports, which posts `NSPersistentStoreRemoteChange`;
/// 3. this reads Core Data's persistent history to find out *what* arrived, and
///    posts a `UNNotificationRequest` for the expenses that are new.
///
/// **This is best-effort by construction, and the settings copy says so.** Step
/// 1 is a silent push, which iOS throttles at its own discretion, delivers not
/// at all to an app the user force-quit, and delays on a device in Low Power
/// Mode. Nothing in the OS offers a stronger guarantee to an app without a
/// backend, and promising "instantly" in the UI would be a lie the app cannot
/// keep. Opening the app always shows the truth.
///
/// Persistent history rather than diffing fetch results, because history is the
/// only record of *what changed* that survives the app not being running. It is
/// also how the mirroring import and this device's own typing are told apart:
/// every local write goes through `GroupStore` on the view context, which sets
/// `transactionAuthor`, and `arrivals(since:container:localAuthor:me:)` skips
/// transactions carrying it. A future write on a context that forgot to set an
/// author would notify the user about their own typing.
@MainActor
final class ExpenseNotifier: NSObject, ObservableObject {
    static let shared = ExpenseNotifier(controller: .shared)

    /// Whether the user has asked for these at all. Persisted, and never the
    /// same question as `authorization`: iOS can revoke permission in Settings
    /// without the app's preference changing, and the settings screen has to be
    /// able to say which of the two is off.
    @Published private(set) var isEnabled: Bool

    /// What iOS currently thinks, refreshed whenever the settings screen
    /// appears — permission can be withdrawn in Settings.app while the app is
    /// backgrounded, and nothing tells the app when it was.
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Whether notifications can be offered at all.
    ///
    /// False for the in-memory stack, for the same reason `CloudSyncMonitor`
    /// switches itself off there: no mirroring event will ever arrive, so the
    /// toggle would be an authorization prompt in front of a feature that
    /// cannot fire. UI tests in particular must never see a system alert.
    let isAvailable: Bool

    /// How long a burst of changes is given to settle, for the same reason
    /// `SpotlightIndexer` coalesces: one CloudKit pull arrives as a run of
    /// remote-change notifications, and scanning on each would read the same
    /// history a dozen times over.
    private static let coalescingDelay = Duration.milliseconds(600)

    /// How long the background push handler will hold the process open waiting
    /// for the import it was woken for. Beyond this iOS is about to suspend the
    /// app anyway, and a scan that hasn't found anything by now will find it on
    /// the next launch instead.
    private static let pushWindow = Duration.seconds(20)

    /// How often the push handler re-reads history while it waits. Polled
    /// rather than awaiting the remote-change notification, for the reason
    /// `CloudSyncMonitor.settle` polls: this wait has to be abandonable on a
    /// timeout, and a continuation that both the timeout and a late
    /// notification can resume is a crash rather than a bug you can see.
    private static let pollInterval = Duration.seconds(2)

    /// At most this many individual notifications per group per scan. Beyond
    /// it, one summary — a phone that has been off all afternoon should show
    /// "8 new expenses", not eight banners to swipe away one at a time.
    private nonisolated static let detailLimit = 2

    private static let enabledKey = "notifications.newExpenses"
    private static let tokenKey = "notifications.historyToken"

    /// Carries the group to open when a notification is tapped.
    private nonisolated static let groupIDKey = "groupID"

    private let controller: PersistenceController
    private let defaults: UserDefaults

    private var observer: (any NSObjectProtocol)?
    private var pending: Task<Void, Never>?

    /// Whether a scan is already reading history.
    ///
    /// Two things scan: the remote-change observer and the background push
    /// handler's poll, and during a background wake-up *both* are running. They
    /// would otherwise fetch from the same stored token concurrently, each find
    /// the same transactions, and post every arrival twice. Set before the
    /// first `await` and cleared after the last, so there is no window for a
    /// second caller to slip through.
    private var isScanning = false

    init(
        controller: PersistenceController,
        defaults: UserDefaults = PersistenceController.appGroupDefaults
    ) {
        self.controller = controller
        self.defaults = defaults
        self.isAvailable = controller.isCloudSyncEnabled
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        super.init()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Lifecycle

    /// Starts watching for imported changes, and claims the notification
    /// delegate.
    ///
    /// Called from `didFinishLaunchingWithOptions` and nowhere else, because
    /// the delegate has to be set before launch finishes: a notification tapped
    /// while the app was not running is delivered as part of launch, and a
    /// delegate assigned any later never hears about it.
    func start() {
        guard isAvailable, observer == nil else { return }

        UNUserNotificationCenter.current().delegate = self

        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            Task { @MainActor in ExpenseNotifier.shared.remoteChangeArrived() }
        }

        Task { await refreshAuthorization() }
    }

    /// Holds the process awake while the import a silent push triggered runs,
    /// then scans what it brought down.
    ///
    /// Without this the app is woken, the container starts importing, and iOS
    /// suspends the process before `NSPersistentStoreRemoteChange` is ever
    /// posted — so the notification would only appear the next time somebody
    /// opened the app, which is the one moment it is worthless.
    ///
    /// Returns whether anything arrived, which is what the system uses to
    /// decide how generous to be with the next wake-up.
    func handleRemotePush() async -> UIBackgroundFetchResult {
        // Nothing to hold the process open *for* when the user hasn't asked for
        // notifications. The import then finishes whenever the container next
        // gets a chance, which is exactly what happened before this existed.
        guard isAvailable, isEnabled, authorization == .authorized else { return .noData }

        let deadline = ContinuousClock.now + Self.pushWindow

        // The container is already importing by the time this is called, and
        // there is no event that means "your zone has finished" — a push can
        // also be for an export, or for a zone this device already has. So this
        // re-reads history until something turns up or the window closes, which
        // returns immediately on a quick import and still catches a slow one.
        repeat {
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { break }
            if await scan() { return .newData }
        } while ContinuousClock.now < deadline

        return .noData
    }

    private func remoteChangeArrived() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled else { return }
            _ = await self?.scan()
        }
    }

    // MARK: - Preference

    /// Turns notifications on, asking iOS for permission the first time.
    ///
    /// The prompt is here rather than at launch on purpose. Asked cold, it
    /// arrives before the person has any idea what the app would notify them
    /// about, and a denial is close to permanent — iOS never asks twice, and
    /// the only way back is a trip to Settings. Asked at the moment somebody
    /// reaches for the toggle, the question already has an answer attached.
    ///
    /// Returns whether the toggle should end up on, so a denial doesn't leave a
    /// switch claiming a feature that cannot fire.
    @discardableResult
    func enable() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound]))
            ?? false

        await refreshAuthorization()

        guard granted else {
            setEnabled(false)
            return false
        }

        // Start from now, not from whatever the store last saw. Otherwise
        // enabling this on a phone that has been syncing for a month replays a
        // month of expenses as banners — every one of them already on screen in
        // the app behind the switch.
        rememberToken(currentToken())
        setEnabled(true)
        return true
    }

    func disable() {
        setEnabled(false)
        pending?.cancel()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Re-reads what iOS thinks, since permission can be withdrawn in
    /// Settings.app without the app running.
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = settings.authorizationStatus

        // A revoked permission turns the app's own preference off too, so the
        // settings screen shows one consistent answer rather than an "on"
        // switch above a row explaining that notifications are blocked.
        if isEnabled, settings.authorizationStatus == .denied {
            setEnabled(false)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    // MARK: - Scanning

    /// Reads what has arrived since the last scan and posts for it.
    ///
    /// Returns whether anything was posted.
    @discardableResult
    private func scan() async -> Bool {
        guard isAvailable, isEnabled, authorization == .authorized else { return false }
        guard !isScanning else { return false }
        isScanning = true
        defer { isScanning = false }

        guard let since = storedToken() else {
            // No baseline — this is the first scan after enabling, or the token
            // was dropped. Take today's position and notify about nothing:
            // history that predates the user asking for notifications is not
            // news to them.
            rememberToken(currentToken())
            return false
        }

        let found = await Self.arrivals(
            since: since,
            container: controller.container,
            localAuthor: controller.viewContext.transactionAuthor,
            me: CloudIdentity.current
        )

        if let token = found.token {
            rememberToken(token)
        }

        // The token still advanced above. Somebody watching the list while a
        // sync lands has already seen the expense appear, and a banner over the
        // row it just added is noise — but it is *seen* noise, so it must not
        // be replayed the next time the app is backgrounded.
        guard UIApplication.shared.applicationState != .active else { return false }
        guard !found.arrivals.isEmpty else { return false }

        post(found.arrivals)
        return true
    }

    // MARK: - Posting

    private func post(_ arrivals: [Arrival]) {
        let centre = UNUserNotificationCenter.current()

        for (groupID, group) in Dictionary(grouping: arrivals, by: \.groupID) {
            for content in Self.contents(for: group, groupID: groupID) {
                centre.add(
                    UNNotificationRequest(
                        identifier: UUID().uuidString,
                        content: content,
                        // No trigger: the event already happened, and the
                        // device is holding the data. Delivered immediately.
                        trigger: nil
                    )
                )
            }
        }
    }

    /// One notification per arrival up to `detailLimit`, and a single summary
    /// past it.
    ///
    /// `nonisolated` and taking only values, so the wording can be tested
    /// without a store, a stack, or a notification centre.
    nonisolated static func contents(
        for arrivals: [Arrival],
        groupID: UUID
    ) -> [UNMutableNotificationContent] {
        let bodies: [String]
        if arrivals.count > detailLimit {
            bodies = ["\(arrivals.count) new expenses"]
        } else {
            bodies = arrivals.map(\.body)
        }

        return bodies.map { body in
            let content = UNMutableNotificationContent()
            content.title = arrivals.first?.groupName ?? "Dutch"
            content.body = body
            content.sound = .default
            // Groups a trip's notifications together in Notification Centre,
            // so three arrivals from one dinner don't read as three unrelated
            // events from three apps.
            content.threadIdentifier = groupID.uuidString
            content.userInfo = [groupIDKey: groupID.uuidString]
            return content
        }
    }

    // MARK: - History

    /// One expense that arrived from somebody else's device, reduced to strings
    /// before it leaves the context that fetched it.
    ///
    /// No managed objects cross out of here, for the same reason `GroupSummary`
    /// holds none: the notification is built and delivered long after the
    /// background context that read it has gone.
    struct Arrival: Sendable, Equatable {
        let groupID: UUID
        let groupName: String
        let payer: String
        let title: String
        let amount: String
        let isReimbursement: Bool

        var body: String {
            isReimbursement
                ? "\(payer) settled up · \(amount)"
                : "\(payer) added \(title) · \(amount)"
        }
    }

    /// Walks persistent history for expenses inserted by anything other than
    /// this device.
    ///
    /// `nonisolated` and given everything it needs, so the whole read happens
    /// on a background context and nothing here touches the view context — this
    /// runs during a background wake-up, where blocking the main queue is a
    /// termination rather than a stutter.
    nonisolated static func arrivals(
        since token: NSPersistentHistoryToken,
        container: NSPersistentContainer,
        localAuthor: String?,
        me: String?
    ) async -> (arrivals: [Arrival], token: NSPersistentHistoryToken?) {
        let context = container.newBackgroundContext()

        return await context.perform {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)

            guard
                let result = try? context.execute(request) as? NSPersistentHistoryResult,
                let transactions = result.result as? [NSPersistentHistoryTransaction]
            else {
                // The token is one the store no longer recognises. Core Data
                // purges history behind CloudKit mirroring after about a week,
                // so this is what a phone that spent a fortnight in a drawer
                // comes back to — and it throws rather than returning nothing.
                //
                // Recovered by handing back *today's* position, which the
                // caller stores. Leaving the stale token in place instead is
                // the tempting, wrong answer: every later scan would fail on
                // the same expired token, and notifications would be silently
                // dead forever with nothing on screen to say so. Resetting
                // costs at most a backlog nobody was going to read as banners.
                return ([], container.persistentStoreCoordinator
                    .currentPersistentHistoryToken(fromStores: nil))
            }

            var arrivals: [Arrival] = []

            for transaction in transactions where transaction.author != localAuthor {
                for change in transaction.changes ?? []
                where change.changeType == .insert
                    && change.changedObjectID.entity.name == "Expense" {
                    guard
                        let expense = try? context.existingObject(
                            with: change.changedObjectID
                        ) as? Expense,
                        let arrival = Self.arrival(for: expense, me: me)
                    else { continue }
                    arrivals.append(arrival)
                }
            }

            return (arrivals, transactions.last?.token)
        }
    }

    /// `nil` for an expense there is nothing worth saying about.
    ///
    /// Incomplete records are dropped the way `SettlementBridge` drops them —
    /// every attribute is optional for CloudKit's sake, so a half-synced expense
    /// is representable and would otherwise notify as "added · " with blanks
    /// where the facts go.
    ///
    /// Expenses the reader paid for are dropped too. The assumption is the one
    /// `ExpenseDefaults` already rests on — each person enters their own
    /// spending on their own phone — so an expense arriving over CloudKit with
    /// this Apple Account as its payer is overwhelmingly this same person's
    /// other device, and notifying them about their own typing is the fastest
    /// way to get the whole feature switched off.
    private nonisolated static func arrival(for expense: Expense, me: String?) -> Arrival? {
        guard
            let group = expense.group,
            let groupID = group.id,
            let name = group.name,
            let payer = expense.paidBy,
            let payerName = payer.name
        else { return nil }

        if let me, payer.cloudUserRecordName == me { return nil }

        return Arrival(
            groupID: groupID,
            groupName: name,
            payer: payerName,
            title: expense.title ?? "an expense",
            amount: Money(amount: expense.amount).formatted(in: group),
            isReimbursement: expense.isReimbursement
        )
    }

    // MARK: - Token

    /// Where the last scan got to.
    ///
    /// Archived into the app group suite rather than held in memory, because
    /// the whole point is to survive the app not running — an in-memory token
    /// would make every cold launch either replay everything or skip it.
    private func storedToken() -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: Self.tokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSPersistentHistoryToken.self,
            from: data
        )
    }

    private func rememberToken(_ token: NSPersistentHistoryToken?) {
        guard let token else { return }

        do {
            let data = try NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            )
            defaults.set(data, forKey: Self.tokenKey)
        } catch {
            // Swallowed silently this would be the worst kind of bug here: no
            // stored token means every scan takes the "no baseline" path, finds
            // nothing, and fails to store one — so notifications would simply
            // never arrive, with a switch on screen saying they would. Logged
            // like `SpotlightIndexer`'s failures, for the same reason: there is
            // nothing the person holding the phone can do, but there needs to
            // be something to find.
            print("[Dutch] Could not persist the notification history token: \(error)")
        }
    }

    private func currentToken() -> NSPersistentHistoryToken? {
        controller.container.persistentStoreCoordinator
            .currentPersistentHistoryToken(fromStores: nil)
    }
}

// MARK: - Tapping

extension ExpenseNotifier: UNUserNotificationCenterDelegate {
    /// Opens the group the notification was about.
    ///
    /// Through `AppRouter` like every other way in from outside the view tree —
    /// the quick action, Spotlight, and the intents all land here, and a second
    /// mechanism for the same push would be a second thing to keep in agreement
    /// with the navigation path.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard
            let raw = response.notification.request.content
                .userInfo[Self.groupIDKey] as? String,
            let id = UUID(uuidString: raw)
        else { return }

        await MainActor.run { AppRouter.shared.open(.group(id)) }
    }
}
