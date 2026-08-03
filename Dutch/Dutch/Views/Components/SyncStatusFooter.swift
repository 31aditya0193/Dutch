/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// One quiet line saying where iCloud sync stands.
///
/// It exists mostly for its failure state. Everything about this app assumes
/// sync works, and when it doesn't — signed out, out of storage, on a plane —
/// the previous behaviour was for expenses to simply stop appearing on other
/// people's phones with nothing anywhere to explain it. Being told is the
/// difference between a bug report and a Settings trip.
///
/// It is also what makes pull-to-refresh honest: the gesture cannot make
/// CloudKit fetch (see `CloudSyncMonitor`), so what it can do is show that a
/// sync is running and when the last one landed.
struct SyncStatusFooter: View {
    @ObservedObject private var sync = CloudSyncMonitor.shared

    /// Cached, because this renders on every list redraw.
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        if sync.isEnabled {
            Label {
                Text(caption)
            } icon: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
            }
            .font(.footnote)
            // Semantic, so a real problem reads as one and the ordinary state
            // stays out of the way.
            .foregroundStyle(sync.problem == nil ? Color.secondary : Color.orange)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(caption)
            // The gesture that changes this line isn't discoverable on its own,
            // and a footer is the one place there is room to say so.
            .accessibilityHint("Pull the list down to check iCloud")
        }
    }

    private var symbol: String {
        if sync.isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if sync.problem != nil { return "exclamationmark.icloud" }
        return sync.lastSync == nil ? "icloud" : "checkmark.icloud"
    }

    private var caption: String {
        if sync.isSyncing { return "Syncing with iCloud…" }
        if let problem = sync.problem { return problem }

        guard let lastSync = sync.lastSync else {
            // Not an error: mirroring may simply not have run its first import
            // yet, which is the normal state for the first seconds of a launch.
            return "Waiting for iCloud"
        }

        // `RelativeDateTimeFormatter` renders the first minute as "in 0
        // seconds", which reads as a scheduled event rather than a finished
        // one — and the first minute is exactly when somebody who just pulled
        // the list is reading this.
        guard Date.now.timeIntervalSince(lastSync) >= 60 else {
            return "Synced just now"
        }
        return "Synced \(Self.relative.localizedString(for: lastSync, relativeTo: .now))"
    }
}
