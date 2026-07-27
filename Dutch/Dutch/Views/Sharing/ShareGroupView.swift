import CloudKit
import CoreData
import SwiftUI

/// Shows a group's invitation: a QR code carrying the CloudKit share URL, the
/// word sequence for confirming it out loud, and the system invite sheet.
///
/// The QR encodes the **share URL**, not the word sequence. Without a server
/// there is nothing that could turn three words back into a group, so the words
/// are a label and the URL is the thing that actually grants access.
struct ShareGroupView: View {
    let group: ExpenseGroup

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .preparing
    @State private var showingInviteSheet = false

    private enum Phase {
        case preparing
        /// The QR code is carried here rather than generated in `body`.
        /// Encoding a share URL at correction level Q and rasterising it to a
        /// `CGImage` is milliseconds of work, and `body` re-ran it on every
        /// state change — including the one that presents the invite sheet, so
        /// it landed squarely in that transition.
        case ready(share: CKShare, container: CKContainer, qrCode: UIImage?)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .preparing:
                    ProgressView("Preparing invitation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let share, let container, let qrCode):
                    readyContent(share: share, container: container, qrCode: qrCode)

                case .failed(let message):
                    ContentUnavailableView(
                        "Can't Share This Group",
                        systemImage: "exclamationmark.icloud",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Share Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await prepareShare() }
    }

    // MARK: - Ready state

    @ViewBuilder
    private func readyContent(
        share: CKShare,
        container: CKContainer,
        qrCode: UIImage?
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                if let qrCode {
                    Image(uiImage: qrCode)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 250)
                        .padding(20)
                        // Deliberately white in both appearances, and not a
                        // semantic background: the generator emits black on
                        // white regardless of colour scheme, and a scanner
                        // needs that light quiet zone around the code. Swapping
                        // this for `systemBackground` would break scanning in
                        // dark mode while looking like a fix.
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .accessibilityLabel("QR code to join \(group.name ?? "this group")")
                } else {
                    ContentUnavailableView(
                        "Invitation Not Ready",
                        systemImage: "qrcode",
                        description: Text("iCloud hasn't finished creating the link yet.")
                    )
                }

                if let sequence = group.wordSequence {
                    VStack(spacing: 8) {
                        // This is the confirmation channel — the thing two
                        // people read to each other to be sure they joined the
                        // same group — so it gets the weight of a heading
                        // rather than sitting a step below the QR caption.
                        Text(sequence)
                            .font(.title.weight(.semibold))
                            .monospaced()
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())

                        Text("Check this matches on the other device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Button {
                    showingInviteSheet = true
                } label: {
                    Label("Invite People", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                Text("Scan the code, or send an invitation through Messages or Mail.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 24)
        }
        .sheet(isPresented: $showingInviteSheet) {
            CloudSharingSheet(
                share: share,
                container: container,
                groupName: group.name ?? "Expense Group"
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Preparing

    private func prepareShare() async {
        guard case .preparing = phase else { return }

        do {
            let (share, container) = try await CloudSharingService.share(for: group)

            // Cache the URL so the group list can show that it's shared
            // without re-hitting CloudKit.
            if let url = share.url, group.cloudKitShareURL != url {
                group.cloudKitShareURL = url
                try? context.save()
            }

            phase = .ready(
                share: share,
                container: container,
                qrCode: await QRCodeGenerator.image(for: share.url)
            )
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    ShareGroupView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
