/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// Picks a group's symbol and colour. Renders as rows, so it goes inside a
/// `Section` in whatever `Form` is presenting it.
///
/// There is no separate preview tile: the grid shows every symbol in the colour
/// currently chosen, so picking a colour re-tints the thing being chosen and the
/// selection *is* the preview. A swatch plus a grid plus a large sample of the
/// two combined is three ways of saying the same thing in one sheet.
struct AppearancePicker: View {
    @Binding var appearance: GroupAppearance

    /// A tap target of 44 with a smaller mark inside it, rather than a 30pt
    /// button that happens to be easy to miss.
    private let target: CGFloat = 44

    var body: some View {
        Group {
            colors
            symbols
        }
        .sensoryFeedback(.selection, trigger: appearance)
    }

    // MARK: - Colours

    private var colors: some View {
        // Wrapping rather than a horizontal scroll: eight swatches fit across
        // every phone at ordinary type sizes, and a row that scrolls hides
        // choices behind a gesture nobody knows is there.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: target), spacing: 4)], spacing: 4) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    appearance.color = color
                } label: {
                    Circle()
                        .fill(color.tint.gradient)
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay {
                            Circle()
                                .strokeBorder(color.tint, lineWidth: 2)
                                .opacity(appearance.color == color ? 1 : 0)
                        }
                        .frame(width: target, height: target)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
                .accessibilityAddTraits(appearance.color == color ? [.isSelected] : [])
            }
        }
        .animation(.snappy, value: appearance.color)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }

    // MARK: - Symbols

    private var symbols: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: target), spacing: 4)], spacing: 4) {
            ForEach(GroupSymbol.allCases) { symbol in
                Button {
                    appearance.symbol = symbol
                } label: {
                    symbolMark(symbol)
                        .frame(width: target, height: target)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol.label)
                .accessibilityAddTraits(appearance.symbol == symbol ? [.isSelected] : [])
            }
        }
        .animation(.snappy, value: appearance)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Symbol")
    }

    @ViewBuilder
    private func symbolMark(_ symbol: GroupSymbol) -> some View {
        let isSelected = appearance.symbol == symbol

        Image(systemName: symbol.systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 36, height: 36)
            // Two layers rather than one fill chosen by a ternary, so the
            // colour crossfades in on selection instead of the shape style
            // being swapped out from under the animation.
            .background {
                Circle().fill(.fill.quaternary)
            }
            .background {
                Circle()
                    .fill(appearance.color.tint.gradient)
                    .opacity(isSelected ? 1 : 0)
            }
    }
}

#Preview {
    @Previewable @State var appearance = GroupAppearance(symbol: .airplane, color: .indigo)

    Form {
        Section("Appearance") {
            AppearancePicker(appearance: $appearance)
        }
    }
}
