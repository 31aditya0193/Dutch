/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import SwiftUI
import UIKit

// MARK: - SwiftUI presentation

/// Presents the system sharing UI for a group.
///
/// `UICloudSharingController` has no SwiftUI equivalent, so it is bridged here.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        // `.allowPublic` has to be here or the sheet won't show "Anyone with
        // the link" — and without that setting the group's QR code admits
        // nobody. `.allowPrivate` stays available so an owner who wants a
        // closed group can still switch back to invitation-only.
        controller.availablePermissions = [.allowReadWrite, .allowPublic, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            // Surfaced through the system UI; logged for diagnosis.
            print("[Dutch] Failed to save share: \(error.localizedDescription)")
        }

        /// Writes the sheet's edits back into the Core Data store.
        ///
        /// Now that the sheet can change *who can access* — the owner may
        /// switch a group back to invitation-only — this is no longer a no-op.
        /// `NSPersistentCloudKitContainer` doesn't observe changes made to a
        /// `CKShare` by CloudKit APIs, so without this the local cache keeps
        /// reporting the old permission and `makeScannable` would reopen a
        /// group the owner just closed.
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            Task { @MainActor in
                guard let store = PersistenceController.shared.privateStore else { return }
                do {
                    try await PersistenceController.shared.container
                        .persistUpdatedShare(share, in: store)
                } catch {
                    print("[Dutch] Failed to persist updated share: \(error.localizedDescription)")
                }
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
