import XCTest

/// End-to-end checks in the running app (XCUITest drives real taps and drags).
@MainActor
final class SolitaireUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Launches the app with a Debug scenario or seed, passed in the environment (see UITestScenario).
    private func launch(scenario: String? = nil, seed: UInt64? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        // Ignore saved window state, as Xcode does for the unit-test host. A run that quit with no
        // window open saves "no windows", and XCUITest's launch (unlike Finder or the Dock) does not
        // send the "open application" event that would open one anyway — the app came up windowless.
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        if let scenario { app.launchEnvironment["SOLITAIRE_SCENARIO"] = scenario }
        if let seed { app.launchEnvironment["SOLITAIRE_SEED"] = String(seed) }
        app.launch()
        return app
    }

    /// Acceptance 5: a game played to a win shows the win sheet with the move count and time.
    func testAutoFinishWinsAndShowsTheWinSheet() {
        let app = launch(scenario: "almostWon")
        let autoFinish = app.buttons["Auto-finish"]
        XCTAssertTrue(autoFinish.waitForExistence(timeout: 5), "Auto-finish should be offered")
        autoFinish.press()
        XCTAssertTrue(app.staticTexts["You won!"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["12 moves"].exists, "twelve auto-finish moves")
        XCTAssertTrue(app.buttons["New Game"].exists)
    }

    /// Acceptance 6: a king alone at the bottom of a column reaches an empty column by drag, but a
    /// tap offers nothing (it would only shuffle columns).
    func testKingToAnEmptyColumnByDragNotByTap() {
        let app = launch(scenario: "kingAlone")
        let king = app.buttons["King of Hearts, column 1"].exists
            ? app.buttons["King of Hearts, column 1"] : app.staticTexts["King of Hearts, column 1"]
        XCTAssertTrue(king.waitForExistence(timeout: 5))
        let emptyColumn = app.descendants(matching: .any)["Column 2, empty"]
        XCTAssertTrue(emptyColumn.exists)

        king.press()
        // Give a (wrong) move time to happen before asserting that none did.
        XCTAssertFalse(app.descendants(matching: .any)["King of Hearts, column 2"].waitForExistence(timeout: 1),
                       "a tap must not move it")
        XCTAssertTrue(app.descendants(matching: .any)["King of Hearts, column 1"].exists)
        XCTAssertTrue(emptyColumn.exists, "column 2 is still empty")

        king.drag(to: emptyColumn)
        XCTAssertTrue(app.descendants(matching: .any)["King of Hearts, column 2"].waitForExistence(timeout: 5),
                      "the drag should have moved it")
    }

    /// Repeated clicks on the stock each draw in the running app. (XCUITest spaces clicks ~0.55 s
    /// apart — just over the macOS double-click interval — so the "however fast" half of the rule
    /// is covered by the `Routing` unit tests, not here.)
    func testFastClicksOnTheStockEachDraw() {
        let app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        app.descendants(matching: .any)["Stock, 23 cards"].press()
        app.descendants(matching: .any)["Stock, 22 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 21 cards"].waitForExistence(timeout: 5))
    }

    #if os(macOS)
    /// The Game and Edit menus follow the game: Undo enables after a move, Auto-finish only when it
    /// is available.
    func testMenuItemsFollowTheGame() {
        let app = launch(scenario: "almostWon")
        XCTAssertTrue(app.buttons["Auto-finish"].waitForExistence(timeout: 5))
        func menuItem(_ menu: String, _ item: String) -> XCUIElement {
            app.menuBars.menuBarItems[menu].click()
            return app.menuBars.menuItems[item]
        }
        XCTAssertTrue(menuItem("Game", "Auto-finish").isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(menuItem("Edit", "Undo").isEnabled, "nothing to undo yet")
        app.typeKey(.escape, modifierFlags: [])
        app.descendants(matching: .any)["Jack of Spades, column 1"].press()   // one move to a foundation
        XCTAssertTrue(menuItem("Edit", "Undo").isEnabled, "a move can be undone")
        app.typeKey(.escape, modifierFlags: [])
    }
    #endif

    /// A tap on the stock draws; undo puts it back.
    func testDrawAndUndo() {
        let app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        app.buttons["Undo"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
    }
}

/// On macOS 27, XCUITest's `tap()` no longer reaches AppKit/SwiftUI controls: "Synthesize event"
/// takes seconds and the control never acts. `click()` still works but exists only on macOS, so
/// these pick the right gesture per platform.
extension XCUIElement {
    func press() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }

    func drag(to target: XCUIElement) {
        #if os(macOS)
        click(forDuration: 0.2, thenDragTo: target)
        #else
        press(forDuration: 0.2, thenDragTo: target)
        #endif
    }
}
