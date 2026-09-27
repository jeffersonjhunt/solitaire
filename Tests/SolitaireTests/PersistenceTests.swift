import Foundation
import Testing
import SolitaireEngine
@testable import Solitaire

private func tempSaveURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("solitaire-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("game.json")
}

@Suite struct Resumability {
    let game = SolitaireEngine.newGame(drawCount: 1, seed: 4)

    @Test func aRealGameIsResumable() {
        #expect(SaveValidation.isResumable(game))
    }

    /// Anything invalid is discarded (spec: 52 distinct cards, not already won; decision F6: 4
    /// foundations and 7 columns) — plus a valid draw mode and sane counters.
    @Test(arguments: [
        "won", "3 foundations", "8 columns", "51 cards", "duplicate card", "rank 14", "draw 2",
        "negative moves", "negative time",
    ])
    func invalidSavesAreRejected(_ defect: String) {
        var s = game
        switch defect {
        case "won": s.isWon = true
        case "3 foundations": s.foundations.removeLast()
        case "8 columns": s.tableau.append([])
        case "51 cards": s.stock.removeLast()
        case "duplicate card": s.stock[0] = s.stock[1]
        case "rank 14": s.stock[0] = Card(suit: .clubs, rank: 14)
        case "draw 2": s.drawCount = 2
        case "negative moves": s.moveCount = -1
        case "negative time": s.elapsed = -1
        default: Issue.record("unknown defect")
        }
        #expect(!SaveValidation.isResumable(s), "\(defect)")
    }
}

@Suite struct Saving {
    let game = SolitaireEngine.newGame(drawCount: 3, seed: 9)

    @Test func aSaveRoundTrips() async throws {
        let url = tempSaveURL()
        let saver = GameSaver(url: url)
        var s = game
        SolitaireEngine.drawFromStock(&s)
        s.elapsed = 42
        try await saver.save(s, sequence: 1)
        #expect(GameSaver.load(from: url) == s)
    }

    /// Saves may land out of order; a late, older one must not overwrite a newer one.
    @Test func anOlderSaveNeverOverwritesANewerOne() async throws {
        let url = tempSaveURL()
        let saver = GameSaver(url: url)
        var newer = game
        newer.moveCount = 5
        try await saver.save(newer, sequence: 2)
        try await saver.save(game, sequence: 1)
        #expect(GameSaver.load(from: url)?.moveCount == 5)
    }

    @Test func missingCorruptOrWonSavesLoadAsNothing() async throws {
        let url = tempSaveURL()
        #expect(GameSaver.load(from: url) == nil, "missing")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        #expect(GameSaver.load(from: url) == nil, "corrupt")
        var won = game
        won.isWon = true
        try await GameSaver(url: url).save(won, sequence: 1)
        #expect(GameSaver.load(from: url) == nil, "already won")
    }
}

@Suite struct Launching {
    let saved = SolitaireEngine.newGame(drawCount: 3, seed: 9)

    @Test func resumeWhenWantedAndPresent() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: true, drawCount: 1) == .resume(saved))
    }

    @Test func dealFreshOtherwiseInTheRememberedMode() {
        #expect(LaunchPlan.decide(saved: saved, resumePreferred: false, drawCount: 3) == .deal(drawCount: 3))
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, drawCount: 3) == .deal(drawCount: 3))
        #expect(LaunchPlan.decide(saved: nil, resumePreferred: true, drawCount: 7) == .deal(drawCount: 1),
                "a corrupt setting is clamped")
    }

    /// The unit-test host shares the real Mac app's container: it must never read or write the
    /// player's save. UI tests name their own file.
    @Test func testsNeverTouchTheRealSave() {
        #expect(SaveLocation.url(environment: ["XCTestConfigurationFilePath": "/x"]) == nil)
        #expect(SaveLocation.url(environment: [:])?.lastPathComponent == "game.json")
        #expect(SaveLocation.url(environment: ["SOLITAIRE_SAVE_FILE": "uitest-1"])?.lastPathComponent == "uitest-1.json")
        #expect(SaveLocation.url(environment: [:])?.deletingLastPathComponent().lastPathComponent == "Solitaire")
    }
}

@MainActor @Suite struct SaveTriggers {
    @Test func everyChangeSavesButTheClockOnlyEveryFiveSeconds() {
        let a = SolitaireEngine.newGame(drawCount: 1, seed: 4)
        var drawn = a
        SolitaireEngine.drawFromStock(&drawn)
        #expect(GameStore.shouldSave(from: a, to: drawn), "a draw")
        var t = a
        for second in 1...10 {
            let before = t
            t.elapsed = Double(second)
            #expect(GameStore.shouldSave(from: before, to: t) == (second % 5 == 0), "tick \(second)")
        }
    }

    /// The store saves after a move and after undo — what a force-quit relaunch would find.
    @Test func theStoreSavesWhatItShows() async throws {
        let url = tempSaveURL()
        let store = makeStore()
        store.saver = GameSaver(url: url)
        store.tapStock()
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state)
        store.tapStock()
        store.undo()
        await store.lastSave?.value
        #expect(GameSaver.load(from: url) == store.state, "after undo")
        for _ in 0..<5 { store.tick() }
        await store.lastSave?.value
        #expect(GameSaver.load(from: url)?.elapsed == 5, "the fifth second is saved")
    }
}
