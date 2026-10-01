import SwiftUI
import SolitaireEngine

/// The whole window: the green table, the board, the toolbar (bottom on iPhone, top elsewhere),
/// and on a win the cascade plus the win sheet with the move count and time.
struct ContentView: View {
    let store: GameStore
    let ui: AppUI
    @State private var dismissedWinSeed: UInt64?
    /// The win whose cascade has finished; the win sheet waits for it, so the cascade plays uncovered.
    @State private var cascadeFinishedSeed: UInt64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !Self.barAtBottom { GameBar(store: store, ui: ui) }
            BoardView(store: store) { cascadeFinishedSeed = store.state.seed }   // draws the win cascade itself
                .padding(.horizontal, 4)
            if Self.barAtBottom { GameBar(store: store, ui: ui) }
        }
        .background(TableBackground().ignoresSafeArea())
        #if os(iOS)
        // Haptics, iOS and iPadOS only: light on a move, soft on a draw, success on a win.
        .sensoryFeedback(trigger: store.feedback) { _, event in
            switch event?.kind {
            case .move: .impact(weight: .light)
            case .draw: .impact(flexibility: .soft)
            case .win: .success
            case nil: nil
            }
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: Binding(get: { ui.showingHelp }, set: { ui.showingHelp = $0 })) {
            NavigationStack {
                HowToPlayView { ui.showingHelp = false }
            }
        }
        #endif
        .sheet(isPresented: winSheetShown) {
            WinSheet(moves: store.state.moveCount, elapsed: store.state.elapsed,
                     preferredDrawCount: store.preferredDrawCount) { count in
                store.newGame(drawCount: count)
            }
        }
    }

    /// Shown once per won game, after its cascade (at once under Reduce Motion, which has none);
    /// closing it leaves the finished board and the cascade's trail (New Game is in the toolbar).
    private var winSheetShown: Binding<Bool> {
        Binding(
            get: {
                store.state.isWon && dismissedWinSeed != store.state.seed
                    && (reduceMotion || cascadeFinishedSeed == store.state.seed)
            },
            set: { shown in if !shown { dismissedWinSeed = store.state.seed } }
        )
    }

    static var barAtBottom: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}

/// A dark green gradient; card faces stay readable on it in light and dark mode.
struct TableBackground: View {
    var body: some View {
        LinearGradient(colors: [Color("TableTop"), Color("TableBottom")], startPoint: .top, endPoint: .bottom)
    }
}

/// The win sheet: move count and time, and a new game — asking for the draw count like every other
/// way of starting one (the remembered mode is the default button).
struct WinSheet: View {
    let moves: Int
    let elapsed: TimeInterval
    let preferredDrawCount: Int
    let newGame: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("You won!").font(.largeTitle.bold())
            HStack(spacing: 24) {
                Label("\(moves) moves", systemImage: "arrow.left.arrow.right")
                Label(GameBar.clock(elapsed), systemImage: "clock")
                    .accessibilityLabel("Time \(GameBar.spokenClock(elapsed))")
            }
            .font(.title3.monospacedDigit())
            HStack {
                Button("Close") { dismiss() }
                ForEach([1, 3], id: \.self) { count in
                    let button = Button("New Game: Draw \(count)") { newGame(count) }
                    if count == preferredDrawCount {
                        button.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    } else {
                        button.buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView(store: GameStore(), ui: AppUI())
}
