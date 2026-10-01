import SwiftUI
import SolitaireEngine

/// The whole window, the same on every platform (direction A): the green table, the header with
/// moves and time, the board, the four-button bar along the bottom, and on a win the cascade
/// plus the win sheet with the move count and time.
struct ContentView: View {
    let store: GameStore
    let ui: AppUI
    @State private var dismissedWinSeed: UInt64?
    /// The win whose cascade has finished; the win sheet waits for it, so the cascade plays uncovered.
    @State private var cascadeFinishedSeed: UInt64?
    /// The width the seven columns actually use, so the header lines up with the cards.
    @State private var boardWidth: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage(AppSettings.cardFaceKey, store: AppSettings.defaults) private var cardFace = CardFaceStyle.classic
    @AppStorage(AppSettings.cardBackKey, store: AppSettings.defaults) private var cardBack = CardBackStyle.classicBlue
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// A phone held sideways: the header folds into the bar, so the cards keep its height.
    private var shortScreen: Bool { verticalSizeClass == .compact }
    #else
    private let shortScreen = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !shortScreen { GameHeader(store: store, ui: ui, width: boardWidth) }
            BoardView(store: store) { cascadeFinishedSeed = store.state.seed }   // draws the win cascade itself
                .onGeometryChange(for: CGFloat.self) { [isTouch = BoardView.isTouch] proxy in
                    BoardMetrics(size: proxy.size, isTouch: isTouch).usedWidth
                } action: { boardWidth = $0 }
            ActionBar(store: store, ui: ui, withStats: shortScreen)
        }
        .background(TableBackground().ignoresSafeArea())
        .environment(\.cardStyle, CardStyle(face: cardFace, back: cardBack))
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
        .sheet(isPresented: Binding(get: { ui.showingSettings }, set: { ui.showingSettings = $0 })) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.showingSettings = false } }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { ui.showingAbout }, set: { ui.showingAbout = $0 })) {
            NavigationStack {
                AboutView()
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { ui.showingAbout = false } }
                    }
            }
        }
        #endif
        // New Game, the draw chip and the menus ask here before losing a game in progress.
        .alert(ui.pendingNewGame?.title ?? "",
               isPresented: Binding(get: { ui.pendingNewGame != nil }, set: { if !$0 { ui.pendingNewGame = nil } }),
               presenting: ui.pendingNewGame) { request in
            Button(request.confirm, role: .destructive) {
                ui.pendingNewGame = nil
                store.newGame(drawCount: request.drawCount)
            }
            Button("Cancel", role: .cancel) { ui.pendingNewGame = nil }
        } message: { request in
            Text(request.message)
        }
        .sheet(isPresented: winSheetShown) {
            WinSheet(moves: store.state.moveCount, elapsed: store.state.elapsed,
                     preferredDrawCount: store.preferredDrawCount) { count in
                store.newGame(drawCount: count)
            }
        }
    }

    private var winSheetShown: Binding<Bool> {
        Binding(
            get: {
                Self.showsWinSheet(isWon: store.state.isWon, dismissed: dismissedWinSeed == store.state.seed,
                                   cascadeFinished: cascadeFinishedSeed == store.state.seed,
                                   reduceMotion: reduceMotion, voiceOver: voiceOver)
            },
            set: { shown in if !shown { dismissedWinSeed = store.state.seed } }
        )
    }

    /// The win sheet: once per won game, after its cascade so the cascade plays uncovered — but at
    /// once under Reduce Motion (there is no cascade) or VoiceOver (the cascade is silent and can't
    /// be skipped by touch; the sheet is what VoiceOver reads). Closing it leaves the finished board
    /// and the trail (New Game is in the bar along the bottom).
    nonisolated static func showsWinSheet(isWon: Bool, dismissed: Bool, cascadeFinished: Bool,
                                          reduceMotion: Bool, voiceOver: Bool) -> Bool {
        isWon && !dismissed && (cascadeFinished || reduceMotion || voiceOver)
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
                Label(GameHeader.clock(elapsed), systemImage: "clock")
                    .accessibilityLabel("Time \(GameHeader.spokenClock(elapsed))")
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
