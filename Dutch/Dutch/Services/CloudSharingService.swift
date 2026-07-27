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

        var errorDescription: String? {
            switch self {
            case .noShareAvailable:
                "This group could not be prepared for sharing. Check that you're signed in to iCloud."
            case .sharedStoreUnavailable:
                "Shared groups can't be stored right now. Check that you're signed in to iCloud."
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
        if let existing = try? existingShare(for: group) {
            return (existing, CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier))
        }

        let (_, share, ckContainer) = try await container.share([group], to: nil)
        share[CKShare.SystemFieldKey.title] = group.name ?? "Expense Group"
        return (share, ckContainer)
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
