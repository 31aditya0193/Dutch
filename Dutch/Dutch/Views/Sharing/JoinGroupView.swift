import SwiftUI

/// Scans a group's QR code and accepts the CloudKit share it points at.
struct JoinGroupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .scanning

    private enum Phase: Equatable {
        case scanning
        case joining
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .scanning:
                    scanner

                case .joining:
                    ProgressView("Joining group…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't Join", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { phase = .scanning }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Join a Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var scanner: some View {
        ZStack {
            // `id` forces a fresh scanner (and a fresh one-shot guard) when
            // retrying after a failure.
            QRScannerView(
                onScanned: { payload in handleScan(payload) },
                onError: { error in phase = .failed(error.localizedDescription) }
            )
            .id(phase == .scanning)
            .ignoresSafeArea(edges: .bottom)

            VStack {
                Spacer()
                Text("Point the camera at the group's QR code.")
                    .font(.callout)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Handling a scan

    private func handleScan(_ payload: String) {
        guard let url = URL(string: payload), url.scheme?.hasPrefix("http") == true else {
            phase = .failed(
                "That doesn't look like a Dutch invitation. Scan the QR code from the group's Share screen."
            )
            return
        }

        phase = .joining

        Task {
            do {
                try await CloudSharingService.acceptShare(at: url)
                dismiss()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    JoinGroupView()
}
