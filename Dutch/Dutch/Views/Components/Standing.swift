/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

/// Where somebody stands in a group: owing, owed, or even.
///
/// Three cases rather than a signed `Money` carried around with a sign test at
/// each call site, so that "even" is a state of its own. An earlier version
/// tinted by sign alone and rendered a zero balance green, which reads as being
/// owed money.
///
/// Shared between the group list and the detail screen because both answer the
/// same question — the list for the person holding the phone, the detail screen
/// for every member — and phrasing or colouring them differently would make the
/// same balance look like two different facts.
enum Standing: Equatable {
    case owes(Money)
    case isOwed(Money)
    case settled

    /// A net position as a standing. `nil` — a member the settlement has no
    /// balance for — is even, which is what a member with no expenses is.
    init(balance: Money?) {
        guard let balance, !balance.isZero else {
            self = .settled
            return
        }
        self = balance < .zero ? .owes(balance.magnitude) : .isOwed(balance)
    }

    var tint: Color {
        switch self {
        case .owes: .red
        case .isOwed: .green
        case .settled: .secondary
        }
    }

    /// Redundant to the colour on purpose. Colour alone can't carry the
    /// difference between owing and being owed: it fails for anyone with a
    /// red/green deficiency, and VoiceOver never sees it at all.
    func caption(isMe: Bool) -> String {
        switch self {
        case .owes: isMe ? String(localized: "you owe") : String(localized: "owes")
        case .isOwed: isMe ? String(localized: "you are owed") : String(localized: "is owed")
        case .settled: String(localized: "settled up")
        }
    }

    /// The whole standing as a sentence, for VoiceOver.
    func accessibleValue(isMe: Bool, currencyCode: String) -> String {
        switch self {
        case .owes(let amount):
            let money = amount.formatted(currencyCode: currencyCode)
            return isMe ? String(localized: "You owe \(money)") : String(localized: "Owes \(money)")
        case .isOwed(let amount):
            let money = amount.formatted(currencyCode: currencyCode)
            return isMe
                ? String(localized: "You are owed \(money)")
                : String(localized: "Is owed \(money)")
        case .settled:
            return String(localized: "Settled up")
        }
    }
}
