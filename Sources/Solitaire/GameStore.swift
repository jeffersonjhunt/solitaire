import Foundation
import Observation
import SolitaireEngine

/// The only object that changes game state. Views call its intents and never mutate state
/// themselves; every change pushes an undo snapshot first.
@Observable @MainActor
final class GameStore {
    static let undoLimit = 300
    static let autoFinishStep: Duration = .milliseconds(90)

    private(set) var state: GameState {
        didSet {
            let moved = Self.movedCards(from: oldValue, to: state)
            if !moved.isEmpty {
                movedCardIDs = moved
                // Any change that moves cards (undo, a draw, an auto-finish step, a resume) ends a
                // drag in progress — the card it held may not be where it was. The clock's tick
                // moves nothing and leaves the drag alone.
                pendingDrag = nil
            }
        }
    }
    /// The cards the latest change moved between piles (a move, draw, redeal, undo or deal). The
    /// board raises them above everything while they animate, so they never slide under a deeper
    /// column; the clock ticking does not reset it.
    private(set) var movedCardIDs: Set<Int> = []
    /// The draw mode the next deal uses (toggled from the Game menu; persisted in U5).
    var preferredDrawCount: Int
    /// The card being dragged (with its run), from `beginDrag` until `drop` or `cancelDrag`.
    private(set) var pendingDrag: PendingDrag?
    /// The latest thing worth a haptic (iOS): a move, a draw, a win. Nothing on failure.
    private(set) var feedback: FeedbackEvent?

    struct PendingDrag: Equatable {
        let source: PileID
        let index: Int
    }

    struct FeedbackEvent: Equatable {
        enum Kind: Equatable { case move, draw, win }
        let kind: Kind
        let sequence: Int                 // distinguishes two identical events in a row
    }
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
        preferredDrawCount = Self.validDrawCount(drawCount)
        state = SolitaireEngine.newGame(drawCount: Self.validDrawCount(drawCount), seed: makeSeed())
    }

    /// Nothing undoes a win: a won game cannot be un-won (spec decision).
    var canUndo: Bool { !undoStack.isEmpty && !state.isWon }
    var canAutoFinish: Bool { SolitaireEngine.canAutoFinish(state) }

    // MARK: Intents

    /// Deals a new game in the preferred draw mode.
    func newGame() {
        newGame(drawCount: preferredDrawCount)
    }

    /// Deals a new game. An out-of-range draw count (e.g. a corrupted setting) becomes 1; the
    /// choice is remembered for the next deal.
    func newGame(drawCount: Int) {
        stopAutoFinish()
        pendingDrag = nil
        preferredDrawCount = Self.validDrawCount(drawCount)
        state = SolitaireEngine.newGame(drawCount: preferredDrawCount, seed: makeSeed())
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

    /// Game menu: switch the draw mode for the next deal (the game in progress is unchanged).
    func toggleDrawMode() {
        preferredDrawCount = preferredDrawCount == 1 ? 3 : 1
    }

    /// A drag has passed its threshold on this card. Returns false (and holds nothing) for a card
    /// that cannot be picked up: face down, buried in the waste or a foundation, or the stock.
    @discardableResult
    func beginDrag(pile: PileID, index: Int) -> Bool {
        guard SolitaireEngine.canPickUp(from: pile, index: index, in: state) else { return false }
        pendingDrag = PendingDrag(source: pile, index: index)
        return true
    }

    func cancelDrag() {
        pendingDrag = nil
    }

    /// A drag released over `destination`. Returns false for an illegal drop (the card springs back).
    @discardableResult
    func drop(source: PileID, index: Int, on destination: PileID) -> Bool {
        pendingDrag = nil
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
        announce(.draw)
        updateClock()
    }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
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
        announce(state.isWon ? .win : .move)
        updateClock()
    }

    private func announce(_ kind: FeedbackEvent.Kind) {
        feedback = FeedbackEvent(kind: kind, sequence: (feedback?.sequence ?? 0) + 1)
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

    static func movedCards(from old: GameState, to new: GameState) -> Set<Int> {
        func piles(_ s: GameState) -> [Int: PileID] {
            var out: [Int: PileID] = [:]
            for c in s.stock { out[c.id] = .stock }
            for c in s.waste { out[c.id] = .waste }
            for (f, pile) in s.foundations.enumerated() { for c in pile { out[c.id] = .foundation(f) } }
            for (t, pile) in s.tableau.enumerated() { for c in pile { out[c.id] = .tableau(t) } }
            return out
        }
        let before = piles(old)
        return Set(piles(new).compactMap { id, pile in before[id] == pile ? nil : id })
    }

    static func validDrawCount(_ drawCount: Int) -> Int {
        drawCount == 3 ? 3 : 1
    }
}
