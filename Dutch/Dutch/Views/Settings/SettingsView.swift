/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import UIKit
import UserNotifications

/// The app's one settings screen: what it may interrupt you for, and what it
/// is.
///
/// There is deliberately very little here, and no per-group anything. Almost
/// every choice this app offers belongs to the group and syncs with it — the
/// name, the icon, the currency, who is who — so it is edited where the group
/// is, not in a list of preferences one screen removed from the thing it
/// changes. What is left is the two things that genuinely have nowhere else to
/// live: a device-wide notification switch, and the legal and provenance links
/// that App Review, the App Store listing, and an MPL-licensed source tree all
/// expect to be reachable from inside the app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var notifier = ExpenseNotifier.shared
    @ObservedObject private var purchases = PurchaseStore.shared

    /// Mirrors the notifier rather than binding straight to it: turning this on
    /// is an `await` that can come back refused, and a `Toggle` bound to the
    /// real answer would flick on and then visibly back off. This one is the
    /// switch's own position, reconciled once the system has answered.
    @State private var wantsNotifications = false

    @State private var isRequesting = false
    @State private var restoreMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if notifier.isAvailable {
                    notifications
                }
                unlimited
                about
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await notifier.refreshAuthorization()
                wantsNotifications = notifier.isEnabled
            }
            .onChange(of: notifier.isEnabled) { _, enabled in
                wantsNotifications = enabled
            }
            .alert(
                "Restore Purchases",
                isPresented: .init(
                    get: { restoreMessage != nil },
                    set: { if !$0 { restoreMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notifications: some View {
        Section {
            Toggle("New Expenses", isOn: $wantsNotifications)
                .disabled(isRequesting || notifier.authorization == .denied)
                .onChange(of: wantsNotifications) { _, wanted in
                    Task { await apply(wanted) }
                }

            if notifier.authorization == .denied {
                // The only route back. iOS asks once and never again, so an app
                // that just showed a dead switch here would be telling somebody
                // their phone was broken.
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Label("Open Notification Settings", systemImage: "arrow.up.forward.app")
                }
            }
        } header: {
            Text(.notifications)
        } footer: {
            Text(footer)
        }
    }

    /// Says what the feature actually does, including the part that is
    /// unflattering.
    ///
    /// Dutch has no server. A notification is posted by this phone once iCloud
    /// has handed it the expense, and iOS decides when that happens — so
    /// "instantly" is not a promise the app is in a position to make, and one
    /// late banner would turn a working feature into a bug report. See
    /// `ExpenseNotifier`.
    private var footer: String {
        switch notifier.authorization {
        case .denied:
            return "Notifications are turned off for Dutch in Settings."
        default:
            return """
                Get a notification when someone else adds an expense to one of \
                your groups. Dutch has no server of its own, so these arrive \
                when iCloud delivers the change — usually within a minute, and \
                not at all while the app is force-quit.
                """
        }
    }

    private func apply(_ wanted: Bool) async {
        guard wanted != notifier.isEnabled else { return }

        if wanted {
            isRequesting = true
            let granted = await notifier.enable()
            isRequesting = false
            // Put the switch back if the system said no, rather than leaving it
            // on above a feature that cannot fire.
            wantsNotifications = granted
        } else {
            notifier.disable()
        }
    }

    // MARK: - Purchase

    @ViewBuilder
    private var unlimited: some View {
        Section {
            if purchases.hasUnlimitedGroups {
                LabeledContent("Dutch Unlimited", value: "Purchased")
            } else {
                // Restore lives here as well as on the group list. The list's
                // version disappears the moment the purchase lands, which is
                // correct there and leaves somebody whose purchase simply
                // hasn't synced yet with nowhere obvious to look — and Settings
                // is where everybody looks first.
                Button("Restore Purchases") {
                    Task { await restore() }
                }
                .disabled(purchases.isWorking)
            }
        }
    }

    private func restore() async {
        let restored = await purchases.restore()
        restoreMessage = restored
            ? "Your purchase has been restored."
            : "No previous purchase was found for this Apple Account."
    }

    // MARK: - About

    private var about: some View {
        Section {
            LabeledContent("Version", value: Self.version)

            Link(destination: URL(string: "https://dutch.smigi.net")!) {
                Label("Website", systemImage: "safari")
            }
            Link(destination: URL(string: "https://dutch.smigi.net/privacy/")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: URL(string: "https://github.com/lakafior/Dutch")!) {
                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Link(
                destination: URL(
                    string: "https://github.com/lakafior/Dutch/blob/main/LICENSE"
                )!
            ) {
                Label("Licence — MPL 2.0", systemImage: "doc.text")
            }
            Link(destination: URL(string: "mailto:dutch@smigi.net")!) {
                Label(.contactLink, systemImage: "envelope")
            }
        } header: {
            Text(.about)
        } footer: {
            Text(.dutchPrivacyDisclosure)
        }
    }

    /// Read from the bundle rather than written here, for the same reason the
    /// price is never written in Swift: there would then be two versions to
    /// keep in agreement, and the one on screen would be the stale one.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

#Preview {
    SettingsView()
}
