import XCTest

/// End-to-end checks in the running app (XCUITest drives real taps and drags).
@MainActor
final class SolitaireUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The UI tests' own save file and settings suite: no UI test reads or overwrites the player's
    /// real game or preferences (on the Mac they share the real app's container). One fixed name,
    /// reset at the start of each test, so runs never leave files piling up.
    private let isolation = "uitest"

    /// Launches the app with a Debug scenario or seed, passed in the environment (see
    /// UITestScenario). `reset: false` keeps the previous launch's save — for relaunch tests.
    private func launch(scenario: String? = nil, seed: UInt64? = nil, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SOLITAIRE_SAVE_FILE"] = isolation
        app.launchEnvironment["SOLITAIRE_DEFAULTS_SUITE"] = isolation
        if reset { app.launchEnvironment["SOLITAIRE_RESET"] = "1" }
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
        // A new game from the win sheet asks for the draw count, like every other way to start one.
        XCTAssertTrue(app.buttons["New Game: Draw 1"].exists && app.buttons["New Game: Draw 3"].exists)
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

    /// The profiling position works in the app: the whole King→Ace run drags to the empty column.
    func testKingToAceRunDragsWhole() {
        let app = launch(scenario: "kingToAce")
        let king = app.descendants(matching: .any)["King of Spades, column 1"]
        XCTAssertTrue(king.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Ace of Spades, column 1"].exists)
        king.drag(to: app.descendants(matching: .any)["Column 2, empty"], grabAt: 0.08)   // its visible strip
        XCTAssertTrue(app.descendants(matching: .any)["King of Spades, column 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["Ace of Spades, column 2"].exists, "the run moved whole")
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

    /// Acceptance 7: force-quitting mid-game and relaunching restores the same board, move count and
    /// elapsed time.
    func testForceQuitAndRelaunchRestoresTheGame() throws {
        var app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        app.descendants(matching: .any)["Stock, 23 cards"].press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 22 cards"].waitForExistence(timeout: 5))
        let waste = wasteTop(app)
        sleep(6)                                          // the clock passes a five-second save
        let before = try seconds(app)
        XCTAssertGreaterThanOrEqual(before, 5)

        app.terminate()                                   // force quit: no chance to save
        app = launch(reset: false)                        // same save file, no seed: resume
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 22 cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(app, equalTo: "2 moves").exists, "move count restored")
        XCTAssertEqual(wasteTop(app), waste, "same board")
        // Restored to the last save — at most five seconds back (decision). The clock runs again
        // once relaunched, so allow for the relaunch itself (slower on iOS) above.
        let after = try seconds(app)
        XCTAssertTrue((before - 5)...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
        XCTAssertFalse(app.buttons["Undo"].isEnabled, "a resumed game starts with undo empty")
    }

    /// Quitting normally (⌘Q on the Mac; iOS sending the app to the background) saves on the spot,
    /// so the elapsed time comes back exactly — not rounded down to the last five-second save.
    func testQuittingNormallyKeepsTheExactTime() throws {
        var app = launch(seed: 4)
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        sleep(8)                                          // between five-second saves (7-8 s)
        let before = try seconds(app)
        XCTAssertTrue(before % 5 != 0, "not on a save boundary (\(before) s), or the test proves nothing")
        #if os(macOS)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        #else
        XCUIDevice.shared.press(.home)                    // background: the app saves on the spot
        sleep(2)
        app.terminate()
        #endif
        app = launch(reset: false)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 23 cards"].waitForExistence(timeout: 5))
        // Never less than when it quit (a rounded-down five-second save would be), plus the
        // seconds the clock runs until the quit and again after the relaunch.
        let after = try seconds(app)
        XCTAssertTrue(before...(before + Self.relaunchSlack) ~= after,
                      "elapsed \(after) s after quitting at \(before) s")
    }

    /// Seconds the clock keeps running around a quit and relaunch (quit ~1 s, iOS relaunch ~3 s).
    private static let relaunchSlack = 6

    /// Starting a new game asks for the draw count — a sheet on iPhone, the File menu pair on the
    /// Mac — and deals in that mode.
    func testNewGameAsksForTheDrawCount() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        #if os(macOS)
        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["New Game: Draw 3"].click()
        #else
        app.buttons["New Game"].press()
        XCTAssertTrue(app.buttons["Draw 3"].waitForExistence(timeout: 5), "the draw-count choice is offered")
        app.buttons["Draw 3"].press()
        #endif
        let stock = app.descendants(matching: .any)["Stock, 24 cards"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        stock.press()
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 21 cards"].waitForExistence(timeout: 5),
                      "a draw-3 deal turns three cards")
    }

    /// The waste top's label ("7 of Clubs, waste"), to compare boards across a relaunch.
    private func wasteTop(_ app: XCUIApplication) -> String? {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH ', waste'"))
            .allElementsBoundByIndex.last?.label
    }

    /// An element whose text is `string`. The toolbar's counters are StaticTexts whose text iOS
    /// exposes as the accessibility label and macOS as the value, so match either.
    private func text(_ app: XCUIApplication, equalTo string: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR value == %@", string, string)).firstMatch
    }

    /// Elapsed seconds from the clock's spoken text ("Time 0 minutes 7 seconds").
    private func seconds(_ app: XCUIApplication) throws -> Int {
        let clock = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Time ' OR value BEGINSWITH 'Time '")).firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "the clock")
        let spoken = clock.label.hasPrefix("Time ") ? clock.label : (clock.value as? String ?? "")
        let words = spoken.split(separator: " ")
        guard words.count >= 4, let minutes = Int(words[1]), let secs = Int(words[3]) else {
            XCTFail("unexpected clock text: \(spoken)")         // fail, never skip: a skip would hide it
            return -1
        }
        return minutes * 60 + secs
    }

    /// How to Play opens from where the spec's help lives on each platform: Help ▸ Solitaire Help
    /// on the Mac (a window), the new-game chooser on iPhone (a sheet, closed with Done).
    func testHowToPlayOpens() {
        let app = launch(seed: 4)
        XCTAssertTrue(app.descendants(matching: .any)["Stock, 24 cards"].waitForExistence(timeout: 5))
        #if os(macOS)
        app.menuBars.menuBarItems["Help"].click()
        app.menuBars.menuItems["Solitaire Help"].click()
        XCTAssertTrue(app.windows["How to Play"].waitForExistence(timeout: 5), "the help window")
        XCTAssertTrue(text(app, equalTo: "Goal").exists)
        #else
        app.buttons["New Game"].press()
        XCTAssertTrue(app.buttons["How to Play"].waitForExistence(timeout: 5))
        app.buttons["How to Play"].press()
        XCTAssertTrue(text(app, equalTo: "Goal").waitForExistence(timeout: 5), "the help sheet")
        app.buttons["Done"].press()
        XCTAssertTrue(text(app, equalTo: "Goal").waitForNonExistence(timeout: 5), "Done closes it")
        #endif
    }

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

    /// Drags from `grabAt` (a fraction of the height from the top) to the target's centre. A card
    /// under others in a fan shows only its top strip; grabbing its centre picks up a card below.
    func drag(to target: XCUIElement, grabAt y: CGFloat = 0.5) {
        let from = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
        let to = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        #if os(macOS)
        from.click(forDuration: 0.2, thenDragTo: to)
        #else
        from.press(forDuration: 0.2, thenDragTo: to)
        #endif
    }
}
