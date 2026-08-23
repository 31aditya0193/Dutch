//
//  LocalizableTests.swift
//  DutchTests
//
//  Created by Aditya Mishra on 23/08/26.
//

@testable import Dutch
import Foundation
import Testing

struct LocalizableTests {
    @Test("Test all english translations")
    func testEnglishTranslations() {
        let bundle = Bundle.main
        let keys = [
            "about",
            "addMembersFirst",
            "addMembersToSplitExpense",
            "amount",
            "newAdditionInstructions",
            "checkMatchOnOtherDevice",
            "createOrJoinAGroup",
            "dutchPrivacyDisclosure",
            "pullToRefresh",
            "totalSpent",
            "youTheUser"
        ]

        let expectedTranslations = [
            "About",
            "Add members first.",
            "Add members to start splitting expenses.",
            "Amount",
            "Anyone who scans this code can join the group. Use Invite People instead to choose people yourself.",
            "Check this matches on the other device.",
            "Create a group to start splitting expenses, or join one with a QR code.",
            "Dutch keeps your groups in your own iCloud account. Nothing is stored on any server of ours, because there isn't one.",
            "Pull the list down to check iCloud.",
            "Total spent",
            "You"
        ]

        for idx in keys.indices {
            let key = keys[idx]
            let localizedString = bundle.localizedString(
                forKey: key,
                value: nil,
                table: "Localizable"
            )
            
            #expect(localizedString == expectedTranslations[idx])
            #expect(localizedString != key)
        }
    }

}
