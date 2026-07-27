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
        nameField.typeText("Berlin Trip")
        app.buttons["Create"].tap()

        let groupCell = app.staticTexts["Berlin Trip"]
        XCTAssertTrue(groupCell.waitForExistence(timeout: 5), "The new group should appear in the list.")
        groupCell.tap()

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

        // Alice is preselected as a sharer; add Bob.
        app.staticTexts["Bob"].tap()

        app.buttons["Save"].tap()

        // ── The settle-up line should say Bob pays Alice ────────
        XCTAssertTrue(
            app.staticTexts["Settle Up"].waitForExistence(timeout: 5),
            "A split expense should produce a settle-up section."
        )
        XCTAssertTrue(app.staticTexts["pays"].exists)
    }

    private func addMember(named name: String) throws {
        app.buttons["Add Member"].firstMatch.tap()

        let field = app.textFields["Name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        app.buttons["Add"].tap()
    }
}
