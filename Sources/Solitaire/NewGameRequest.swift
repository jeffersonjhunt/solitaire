import Foundation

/// A new deal the player asked for (spec "New games and the draw mode"): New Game keeps the
/// current game's mode; the draw chip and the Mac's draw items name one. A game in progress is
/// asked about first — the alert in ContentView — and anything else is replaced at once.
struct NewGameRequest: Equatable {
    let drawCount: Int
    /// A different mode from the game it would replace.
    let switching: Bool

    var title: String { switching ? "Switch to Draw \(drawCount)?" : "Start a new game?" }
    var message: String {
        switching ? "This starts a new game, and the current one will be lost." : "This one will be lost."
    }
    var confirm: String { switching ? "Start New Game" : "New Game" }
}

extension AppUI {
    /// Deals a new game — in `drawCount`, or the current game's mode — at once, unless that would
    /// lose a game in progress; then it only asks (`pendingNewGame`), and the alert deals or not.
    /// Asking stops auto-finish, so the game cannot be won behind the question.
    func requestNewGame(drawCount: Int? = nil, store: GameStore) {
        let count = GameStore.validDrawCount(drawCount ?? store.state.drawCount)
        guard store.isInProgress else {
            pendingNewGame = nil
            store.newGame(drawCount: count)
            return
        }
        store.stopAutoFinish()
        pendingNewGame = NewGameRequest(drawCount: count, switching: count != store.state.drawCount)
    }
}
