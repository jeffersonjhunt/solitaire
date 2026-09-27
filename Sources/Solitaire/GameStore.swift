import Foundation
import Observation
import SolitaireEngine

/// The only object that changes game state. Views call its intents and never mutate state
/// themselves; every change pushes an undo snapshot first.
@Observable @MainActor
final class GameStore {
    static let undoLimit = 300
    static let autoFinishStep: Duration = .milliseconds(90)

    private(set) var state: GameState
    private(set) var undoStack: [GameState] = []
    /// True while the app is in the foreground; the clock only runs then.
    var isActive = true {
        didSet { updateClock() }
    }

    @ObservationIgnored private let makeSeed: () -> UInt64
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var finishing: Task<Void, Never>?

    /// - Parameter makeSeed: where deal seeds come from; tests inject a fixed sequence.
    init(drawCount: Int = 1, makeSeed: @escaping () -> UInt64 = { UInt64.random(in: .min ... .max) }) {
        self.makeSeed = makeSeed
        state = SolitaireEngine.newGame(drawCount: Self.validDrawCount(drawCount), seed: makeSeed())
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canAutoFinish: Bool { SolitaireEngine.canAutoFinish(state) }

    // MARK: Intents

    /// Deals a new game. An out-of-range draw count (e.g. a corrupted setting) becomes 1.
    func newGame(drawCount: Int) {
        stopAutoFinish()
        state = SolitaireEngine.newGame(drawCount: Self.validDrawCount(drawCount), seed: makeSeed())
        undoStack.removeAll()
        updateClock()
    }

    /// Continues a game from a given state (a saved game, or a test position). Undo starts empty.
    func resume(from saved: GameState) {
        stopAutoFinish()
        state = saved
        undoStack.removeAll()
        updateClock()
    }

    /// Tap or click on a card: sends it (with its run) to the best legal destination.
    /// Returns false when nothing can move, so the view can wiggle instead.
    @discardableResult
    func tap(pile: PileID, index: Int) -> Bool {
        guard let destination = SolitaireEngine.autoDestination(for: pile, index: index, in: state) else {
            return false
        }
        perform(Move(source: pile, index: index, destination: destination))
        return true
    }

    /// A drag released over `destination`. Returns false for an illegal drop (the card springs back).
    @discardableResult
    func drop(source: PileID, index: Int, on destination: PileID) -> Bool {
        let move = Move(source: source, index: index, destination: destination)
        guard SolitaireEngine.canMove(move, in: state) else { return false }
        perform(move)
        return true
    }

    /// Tap on the stock: draw, or redeal when the stock is empty.
    func tapStock() {
        guard !state.isWon, !(state.stock.isEmpty && state.waste.isEmpty) else { return }
        record()
        SolitaireEngine.drawFromStock(&state)
        updateClock()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        stopAutoFinish()
        state = previous
        updateClock()
    }

    /// Plays the rest of the game to the foundations, one normal (undoable) move every 90 ms.
    func autoFinish() {
        guard canAutoFinish, finishing == nil else { return }
        finishing = Task { [weak self] in
            while let self, !Task.isCancelled, let move = SolitaireEngine.nextAutoFinishMove(in: self.state) {
                self.perform(move)
                try? await Task.sleep(for: Self.autoFinishStep)
            }
            // A cancelled run must not clear the handle of a run started after it.
            if !Task.isCancelled { self?.finishing = nil }
        }
    }

    // MARK: Clock

    /// The game has started once the player has done something.
    var isRunning: Bool { isActive && !state.isWon && state.moveCount > 0 }

    /// One second of play. Called by the clock; tests call it directly.
    func tick() {
        guard isRunning else { return }
        state.elapsed += 1
    }

    private func updateClock() {
        if isRunning, clock == nil {
            clock = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        } else if !isRunning {
            clock?.cancel()
            clock = nil
        }
    }

    // MARK: Helpers

    private func perform(_ move: Move) {
        record()
        SolitaireEngine.apply(move, to: &state)
        updateClock()
    }

    /// Snapshot the state before a change; the oldest snapshot falls off past the limit.
    private func record() {
        undoStack.append(state)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst(undoStack.count - Self.undoLimit)
        }
    }

    private func stopAutoFinish() {
        finishing?.cancel()
        finishing = nil
    }

    static func validDrawCount(_ drawCount: Int) -> Int {
        drawCount == 3 ? 3 : 1
    }
}
