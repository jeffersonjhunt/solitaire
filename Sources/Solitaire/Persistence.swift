import Foundation
import SolitaireEngine

/// Writes the game in progress as JSON, atomically, off the main actor (spec: "Persistence and
/// settings"). Each save carries a sequence number, so a save that arrives late can never
/// overwrite a newer one. Nothing is written anywhere but this one local file.
actor GameSaver {
    let url: URL
    private var lastWritten = -1

    init(url: URL) {
        self.url = url
    }

    /// Saves `state` unless a newer save (higher `sequence`) has already been written.
    func save(_ state: GameState, sequence: Int) throws {
        guard sequence > lastWritten else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        lastWritten = sequence
    }

    /// The saved game, if there is one that decodes and passes `SaveValidation`; nil otherwise.
    nonisolated static func load(from url: URL) -> GameState? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(GameState.self, from: data),
              SaveValidation.isResumable(state) else { return nil }
        return state
    }
}

/// Whether a decoded save is a game we can resume: 52 distinct real cards in 4 foundations and 7
/// columns, a valid draw mode, sane counters, and not already won (spec + decision F6). Anything
/// else is discarded silently and a fresh game dealt.
enum SaveValidation {
    static func isResumable(_ s: GameState) -> Bool {
        guard s.foundations.count == 4, s.tableau.count == 7,
              s.drawCount == 1 || s.drawCount == 3,
              !s.isWon, !SolitaireEngine.isWon(s),
              s.moveCount >= 0, s.elapsed >= 0, s.elapsed.isFinite else { return false }
        let cards = s.stock + s.waste + s.foundations.flatMap { $0 } + s.tableau.flatMap { $0 }
        guard cards.count == 52, cards.allSatisfy({ (1...13).contains($0.rank) }) else { return false }
        return Set(cards.map(\.id)).count == 52
    }
}

/// What to do at launch: resume the saved game (when the player wants that and it is valid) or
/// deal a fresh one in the remembered draw mode.
enum LaunchPlan: Equatable {
    case resume(GameState)
    case deal(drawCount: Int)

    static func decide(saved: GameState?, resumePreferred: Bool, drawCount: Int) -> LaunchPlan {
        if resumePreferred, let saved { return .resume(saved) }
        return .deal(drawCount: GameStore.validDrawCount(drawCount))
    }
}

/// Where the game is saved: Application Support/Solitaire/game.json. Debug builds let tests use
/// their own file (SOLITAIRE_SAVE_FILE), and the unit-test host never persists: on the Mac it
/// shares the real app's sandbox container, so it would otherwise read and overwrite the player's
/// real game.
enum SaveLocation {
    static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil { return nil }        // unit-test host
        let name = environment["SOLITAIRE_SAVE_FILE"] ?? "game"
        #else
        let name = "game"
        #endif
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Solitaire", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }
}
