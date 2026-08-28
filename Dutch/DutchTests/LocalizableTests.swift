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
            "amount",
            "newAdditionInstructions",
            "checkMatchOnOtherDevice",
            "createOrJoinAGroup",
            "dutchPrivacyDisclosure",
            "pullToRefresh",
            "totalSpent",
            "youTheUser",
            "members",
            "splitAmong",
            "expenseDetails",
            "settled",
            "settledUp",
            "settlementExplanation",
            "partialPercentageExplanation",
            "excludePayerSplitExplanation",
            "percentageSplitExplanation",
            "pricingDescription",
            "appStoreUnreachable",
            "oneTimePurchase",
            "nothingSpentYet"
        ]

        let expectedTranslations = [
            "About",
            "Add members first.",
            "Amount",
            "Anyone who scans this code can join the group. Use Invite People instead to choose people yourself.",
            "Check this matches on the other device.",
            "Create a group to start splitting expenses, or join one with a QR code.",
            "Dutch keeps your groups in your own iCloud account. Nothing is stored on any server of ours, because there isn't one.",
            "Pull the list down to check iCloud.",
            "Total spent",
            "You",
            "Members",
            "Split Among",
            "Expense Details",
            "Settled",
            "Settled up",
            "Make these payments and everyone is even. Mark one paid and it is logged below.",
            "Percent of a full share, 1 to 200. A fare with 51% off is 49.",
            "Include whoever shares the cost. Leave the payer out if they were covering it for others.",
            "100% is a full share — a 51% off fare is 49%, and two people sharing one hotel room are 50% each. The amounts beside each name always add up to the total.",
            "One group is free. Unlock unlimited groups with a one-time purchase — joining other people's groups is always free.",
            "The App Store couldn't be reached.",
            "One-time purchase.",
            "Nothing spent yet"
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
