import SwiftUI

/// A transient, non-blocking error message pinned to the bottom of a screen.
///
/// This replaces the modal alerts the app used to raise for save failures. An
/// alert stops everything to say something the user can only acknowledge, and
/// on the expense form it does it while they are mid-entry. A banner reports
/// the same thing without taking the screen — which matters most exactly where
/// the user has unsaved input worth protecting.
private struct ErrorBannerModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // The animation is scoped to this stack rather than to
                // `content`, so it drives the banner in and out without also
                // animating unrelated changes in the screen behind it.
                ZStack {
                    if let message {
                        banner(message)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
            }
            .task(id: message) {
                guard message != nil else { return }
                // Long enough to read a sentence, short enough that a stale
                // failure isn't still on screen two actions later.
                try? await Task.sleep(for: .seconds(6))
                message = nil
            }
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .font(.title3)

            Text(text)
                .font(.subheadline)
                // Never truncate an error. At large type sizes the one useful
                // sentence is the first thing a line limit would cut.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                message = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
            // Cancels out the frame's padding so the glyph still sits on the
            // same optical line as the text, while keeping the 44pt target.
            .padding(-12)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

extension View {
    /// Presents `message` as a dismissible banner over the bottom of this view.
    func errorBanner(_ message: Binding<String?>) -> some View {
        modifier(ErrorBannerModifier(message: message))
    }
}

#Preview {
    // A wrapper rather than `@Previewable`, which needs a newer deployment
    // target than this app builds against.
    struct Harness: View {
        @State private var message: String? =
            "The group couldn't be saved because iCloud is unavailable."

        var body: some View {
            NavigationStack {
                List {
                    Button("Show error") {
                        message = "The group couldn't be saved because iCloud is unavailable."
                    }
                }
                .navigationTitle("Preview")
                .errorBanner($message)
            }
        }
    }

    return Harness()
}
