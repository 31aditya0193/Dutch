import CloudKit
import CoreData
import UIKit

/// Creates and accepts CloudKit shares for `ExpenseGroup` records.
///
/// Sharing goes through `NSPersistentCloudKitContainer` rather than raw
/// `CKShare` calls. That matters: the container owns the record zones, so a
/// hand-built `CKShare` would point at a zone Core Data knows nothing about and
/// the shared objects would never sync.
@MainActor
enum CloudSharingService {

    enum SharingError: LocalizedError {
        case noShareAvailable
        case sharedStoreUnavailable
        case privateStoreUnavailable

        var errorDescription: String? {
            switch self {
            case .noShareAvailable:
                "This group could not be prepared for sharing. Check that you're signed in to iCloud."
            case .sharedStoreUnavailable:
                "Shared groups can't be stored right now. Check that you're signed in to iCloud."
            case .privateStoreUnavailable:
                "This group can't be prepared for sharing right now. Check that you're signed in to iCloud."
            }
        }
    }

    private static var container: NSPersistentCloudKitContainer {
        PersistenceController.shared.container
    }

    // MARK: - Creating a share

    /// Returns the existing share for a group, or creates one.
    ///
    /// Re-sharing an already-shared group must reuse its `CKShare`; creating a
    /// second one would strand the members who accepted the first.
    static func share(for group: ExpenseGroup) async throws -> (CKShare, CKContainer) {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)

        // An existing share is returned exactly as it stands. Re-opening it
        // here would look like a helpful upgrade for groups made by an older
        // build, but it would also silently undo an owner who deliberately
        // switched their group back to invitation-only — and it would do it
        // just by their visiting the share screen. Owner intent wins; the
        // share screen offers the switch instead.
        if let existing = try? existingShare(for: group) {
            return (existing, ckContainer)
        }

        let (_, share, sharedContainer) = try await container.share([group], to: nil)
        share[CKShare.SystemFieldKey.title] = group.name ?? "Expense Group"
        return (try await makeScannable(share), sharedContainer)
    }

    /// Opens a share to anyone holding its URL, and saves that back to CloudKit.
    ///
    /// A `CKShare` defaults to `publicPermission == .none`, which means the URL
    /// authorises nobody: only Apple IDs the owner added as participants can
    /// accept, and everyone else sees "Item Unavailable". That default is fine
    /// for an invitation sent through Messages — the system sheet adds the
    /// recipient as it sends — but it is fatal for a QR code, which has no
    /// step that could add anyone. Left at `.none`, scanning the code can only
    /// ever work for someone who was *already* invited, which makes the code a
    /// redundant second channel rather than a way in.
    ///
    /// So a newly created share is opened up, and the URL becomes the
    /// credential. It is an Apple-generated random token, not something
    /// guessable, but it is a bearer token: whoever holds it is in.
    /// `ShareGroupView` says so plainly, and the owner can still switch a group
    /// back to invitation-only from the system sharing sheet.
    ///
    /// Only ever called for shares this method just created — see the note in
    /// `share(for:)` about not overriding an owner's later choice.
    @discardableResult
    private static func makeScannable(_ share: CKShare) async throws -> CKShare {
        guard share.publicPermission == .none else { return share }
        guard let privateStore = PersistenceController.shared.privateStore else {
            throw SharingError.privateStoreUnavailable
        }

        share.publicPermission = .readWrite
        // Core Data does not notice changes made to a `CKShare` behind its
        // back; without this the new permission never reaches the server and
        // the local cache goes stale.
        return try await container.persistUpdatedShare(share, in: privateStore)
    }

    /// The share already attached to this group, if it has one.
    static func existingShare(for group: ExpenseGroup) throws -> CKShare? {
        try container.fetchShares(matching: [group.objectID])[group.objectID]
    }

    /// Whether the group is shared with anyone.
    static func isShared(_ group: ExpenseGroup) -> Bool {
        (try? existingShare(for: group)) .flatMap { $0 } != nil
    }

    // MARK: - Accepting a share

    /// Accepts an invitation opened from a link or QR code, routing the data
    /// into the shared store.
    static func acceptShare(_ metadata: CKShare.Metadata) async throws {
        guard let sharedStore = PersistenceController.shared.sharedStore else {
            throw SharingError.sharedStoreUnavailable
        }
        try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
    }

    /// Fetches the metadata for a share URL, then accepts it.
    ///
    /// Used when a share arrives as a scanned QR code rather than through the
    /// system's own invitation handling.
    static func acceptShare(at url: URL) async throws {
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)
        let metadata = try await ckContainer.shareMetadata(for: url)
        try await acceptShare(metadata)
    }
}

// MARK: - Share URL fetching

private extension CKContainer {
    /// `CKFetchShareMetadataOperation` wrapped for async/await.
    func shareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [url])
            operation.shouldFetchRootRecord = true

            var resumed = false
            operation.perShareMetadataResultBlock = { _, result in
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }
            operation.fetchShareMetadataResultBlock = { result in
                // Only fires as a failure path if no per-share result arrived.
                guard !resumed else { return }
                resumed = true
                switch result {
                case .success:
                    continuation.resume(throwing: CloudSharingService.SharingError.noShareAvailable)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            add(operation)
        }
    }
}
