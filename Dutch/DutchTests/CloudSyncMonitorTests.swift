/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import Testing
@testable import Dutch

/// Tests for the one part of sync status that is pure logic.
///
/// The monitor's bookkeeping needs a live mirroring container to exercise and
/// is left to the app; the error wording is what a user actually reads, and it
/// is the part that would silently rot back into `localizedDescription`.
@Suite("CloudSyncMonitor")
struct CloudSyncMonitorTests {

    private func error(_ code: CKError.Code) -> CKError {
        CKError(code)
    }

    @Test("A signed-out account is reported as something to fix")
    func notAuthenticated() {
        let message = CloudSyncMonitor.describe(error(.notAuthenticated))
        #expect(message.contains("Sign in to iCloud"))
    }

    @Test("A full account says storage, not sync")
    func quotaExceeded() {
        let message = CloudSyncMonitor.describe(error(.quotaExceeded))
        #expect(message.contains("storage is full"))
    }

    @Test("Being offline is described as temporary")
    func offline() {
        for code in [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable] {
            let message = CloudSyncMonitor.describe(error(code))
            #expect(message.contains("when the connection is back"))
        }
    }

    /// The umbrella `partialFailure` describes nothing useful, so the reason
    /// has to come from the item underneath it.
    @Test("A partial failure reports the underlying reason")
    func partialFailure() {
        let underlying = CKError(.quotaExceeded)
        let partial = CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: ["zone": underlying]]
        )

        #expect(CloudSyncMonitor.describe(partial).contains("storage is full"))
    }

    /// A partial failure carrying nothing still has to say something.
    @Test("An empty partial failure falls back to a plain sentence")
    func emptyPartialFailure() {
        let message = CloudSyncMonitor.describe(CKError(.partialFailure))
        #expect(message == "Some changes couldn't be synced with iCloud.")
    }

    @Test("A non-CloudKit error is passed through")
    func otherError() {
        struct Failure: LocalizedError {
            var errorDescription: String? { "Something else went wrong." }
        }
        #expect(CloudSyncMonitor.describe(Failure()) == "Something else went wrong.")
    }
}
