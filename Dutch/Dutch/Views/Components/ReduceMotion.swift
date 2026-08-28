/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// A `contentTransition` that becomes a plain swap when Reduce Motion is on.
///
/// The app's motion is concentrated in content transitions, and both kinds it
/// uses are what the setting exists to turn off:
///
/// - `.numericText()` rolls every digit of a balance whenever the figure
///   changes — including changes the user did not initiate, arriving from a
///   CloudKit import while they are reading the screen. It is also why an App
///   Store screenshot taken seconds after launch caught ghost numerals, which
///   is the same effect seen by someone who did not want it.
/// - `.symbolEffect(.replace)` swaps a glyph by scaling one out and the next in.
///
/// Deliberately **not** applied to the `.snappy` value animations elsewhere in
/// the app. Those animate colour and layout — a balance turning from red to
/// green, a picker's selection moving — and Reduce Motion targets motion, not
/// change. Apple's own guidance is to replace motion with a cross-fade rather
/// than to freeze the interface, so a colour that eases is left easing.
///
/// Read from the environment rather than `UIAccessibility.isReduceMotionEnabled`
/// so the view redraws when the setting is changed mid-session; the static
/// property answers correctly but nothing observes it.
private struct MotionContentTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let transition: ContentTransition

    func body(content: Content) -> some View {
        // `.identity` rather than `.opacity`: a cross-faded digit is still a
        // digit drawing attention to itself, and the value here is a number
        // somebody is trying to read, not an event they need to notice.
        content.contentTransition(reduceMotion ? .identity : transition)
    }
}

extension View {
    /// `contentTransition(_:)`, honouring Reduce Motion.
    ///
    /// Every animated content transition in the app goes through this. A bare
    /// `.contentTransition` is not wrong so much as unaudited against the
    /// setting — if a new one is added, route it through here.
    func motionContentTransition(_ transition: ContentTransition) -> some View {
        modifier(MotionContentTransition(transition: transition))
    }
}
