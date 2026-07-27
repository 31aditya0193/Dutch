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

    /// Shared by the aiming frame and by the scanner's `rectOfInterest`, so the
    /// square the user aims with is the square the decoder actually reads.
    private static let aimingSide: CGFloat = QRScannerView.defaultAimingSide

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
            // Replaces the raw `kSystemSoundID_Vibrate` the scanner used to
            // fire from its capture delegate.
            .sensoryFeedback(.success, trigger: phase == .joining)
        }
    }

    private var scanner: some View {
        // Camera and overlay share one stack and one set of ignored safe areas,
        // so the drawn frame and the scanner's region of interest are centred
        // on the same point.
        ZStack {
            // `id` forces a fresh scanner (and a fresh one-shot guard) when
            // retrying after a failure.
            QRScannerView(
                onScanned: { payload in handleScan(payload) },
                onError: { error in phase = .failed(error.localizedDescription) },
                aimingSide: Self.aimingSide
            )
            .id(phase == .scanning)

            aimingFrame

            VStack {
                Spacer()
                Text("Point the camera at the group's QR code.")
                    .font(.callout)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// A dimmed surround with the aiming square cut out of it.
    ///
    /// Every Apple scanner — Camera, Wallet, Watch pairing — bounds the region
    /// it reads. The dark surround does the aiming instruction that a caption
    /// can only describe, and it tells the truth: the scanner really is only
    /// decoding inside this square.
    private var aimingFrame: some View {
        Rectangle()
            .fill(.black.opacity(0.5))
            .reverseMask {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .frame(width: Self.aimingSide, height: Self.aimingSide)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: Self.aimingSide, height: Self.aimingSide)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

// MARK: - Reverse Mask

private extension View {
    /// Punches `mask` out of this view, rather than keeping only what it covers.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            Rectangle()
                .overlay {
                    mask()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

#Preview {
    JoinGroupView()
}
