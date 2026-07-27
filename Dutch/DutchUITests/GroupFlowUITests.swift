import XCTest

/// Drives the app the way a person would: create a group, add two members,
/// record an expense, and check the settle-up line.
///
/// Each run starts from a clean store via the `-uitesting-reset` launch
/// argument, so the tests don't depend on what a previous run left behind.
final class GroupFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitesting-reset"]
        app.launch()
    }

    func testEmptyStateIsShownOnFirstLaunch() {
        XCTAssertTrue(
            app.staticTexts["No Groups"].waitForExistence(timeout: 5),
            "A fresh install should show the empty state."
        )
    }

    func testCreateGroupAddMembersAndSplitAnExpense() throws {
        // ── Create the group ────────────────────────────────────
        app.buttons["New Group"].tap()

        let nameField = app.textFields["Group Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Berlin Trip")
        app.buttons["Create"].tap()

        // Creating pushes straight into the new group — it is empty and
        // useless until it has members, so there is nothing to go back to.
        XCTAssertTrue(
            app.navigationBars["Berlin Trip"].waitForExistence(timeout: 5),
            "Creating a group should open it."
        )

        // ── Add two members ─────────────────────────────────────
        try addMember(named: "Alice")
        try addMember(named: "Bob")

        XCTAssertTrue(app.staticTexts["Alice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bob"].exists)

        // ── Record an expense split between them ────────────────
        app.buttons["Add Expense"].tap()

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Dinner")

        let amountField = app.textFields["Amount"]
        amountField.tap()
        amountField.typeText("30")

        app.buttons["Who paid?"].tap()
        app.buttons["Alice"].tap()

        // Alice is preselected as a sharer; add Bob. The split rows are
        // buttons now, not tap gestures on text.
        app.buttons["Bob"].firstMatch.tap()

        app.buttons["Save"].tap()

        // ── The settle-up line should say Bob pays Alice ────────
        XCTAssertTrue(
            app.staticTexts["Settle Up"].waitForExistence(timeout: 5),
            "A split expense should produce a settle-up section."
        )

        // The row shows an arrow rather than the word, so assert on the
        // accessibility label the row combines for VoiceOver.
        let settlement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "pays"))
            .firstMatch
        XCTAssertTrue(
            settlement.waitForExistence(timeout: 5),
            "The settle-up row should read as one payment to VoiceOver."
        )
    }

    func testExpensesCanBeDeleted() throws {
        app.buttons["New Group"].tap()

        let nameField = app.textFields["Group Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Lunch Club")
        app.buttons["Create"].tap()

        try addMember(named: "Alice")

        app.buttons["Add Expense"].tap()
        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Coffee")
        app.textFields["Amount"].tap()
        app.textFields["Amount"].typeText("5")
        app.buttons["Who paid?"].tap()
        app.buttons["Alice"].tap()
        app.buttons["Save"].tap()

        let expense = app.staticTexts["Coffee"]
        XCTAssertTrue(expense.waitForExistence(timeout: 5))

        // A mistyped expense used to be permanent, which quietly poisoned
        // every balance in the group.
        expense.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()

        XCTAssertFalse(
            expense.waitForExistence(timeout: 2),
            "A swiped-away expense should be gone."
        )
    }

    private func addMember(named name: String) throws {
        app.buttons["Add Member"].firstMatch.tap()

        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Add"].tap()
    }
}
