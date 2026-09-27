import SwiftUI
import SolitaireEngine

/// The whole window: the green table, the board, the toolbar (bottom on iPhone, top elsewhere),
/// and on a win the cascade plus the win sheet with the move count and time.
struct ContentView: View {
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissedWinSeed: UInt64?

    var body: some View {
        VStack(spacing: 0) {
            if !Self.barAtBottom { GameBar(store: store) }
            BoardView(store: store)
                .padding(.horizontal, 4)
                .overlay {
                    if store.state.isWon && !reduceMotion {
                        GeometryReader { geo in
                            WinCascade(foundations: store.state.foundations,
                                       layout: BoardLayout(state: store.state,
                                                           metrics: BoardMetrics(size: geo.size, isTouch: BoardView.isTouch)))
                        }
                        .id(store.state.seed)          // a fresh cascade for every win
                    }
                }
            if Self.barAtBottom { GameBar(store: store) }
        }
        .background(TableBackground().ignoresSafeArea())
        .sheet(isPresented: winSheetShown) {
            WinSheet(moves: store.state.moveCount, elapsed: store.state.elapsed) {
                store.newGame(drawCount: store.state.drawCount)
            }
        }
    }

    /// Shown once per won game; closing it leaves the finished board (New Game is in the toolbar).
    private var winSheetShown: Binding<Bool> {
        Binding(
            get: { store.state.isWon && dismissedWinSeed != store.state.seed },
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

struct WinSheet: View {
    let moves: Int
    let elapsed: TimeInterval
    let newGame: () -> Void
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
                Button("New Game") { newGame() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView(store: GameStore())
}
