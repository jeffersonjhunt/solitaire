import SwiftUI

/// Moves, elapsed time, New game, Undo, and Auto-finish when it is available. Placed at the
/// bottom within thumb reach on iPhone, at the top on iPad and Mac (see `ContentView`).
struct GameBar: View {
    let store: GameStore
    let ui: AppUI
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    @State private var choosingNewGame = false
    #else
    private let isCompact = false
    #endif

    var body: some View {
        HStack(spacing: 16) {
            Label("\(store.state.moveCount)", systemImage: "arrow.left.arrow.right")
                .accessibilityLabel("\(store.state.moveCount) moves")
            Label(Self.clock(store.state.elapsed), systemImage: "clock")
                .accessibilityLabel("Time \(Self.spokenClock(store.state.elapsed))")
            Spacer(minLength: 8)
            Group {
                if store.canAutoFinish {
                    Button("Auto-finish", systemImage: "wand.and.stars") { store.autoFinish() }
                }
                Button("Undo", systemImage: "arrow.uturn.backward") { store.undo() }
                    .disabled(!store.canUndo)           // also off once the game is won
                newGameControl
            }
            // Icons only where width is tight (iPhone); the labels still name them for VoiceOver.
            .labelStyle(AdaptiveLabelStyle(iconOnly: isCompact))
        }
        .labelStyle(.titleAndIcon)
        .font(.callout.monospacedDigit())
        .foregroundStyle(.white)
        .tint(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.black.opacity(0.25))
    }

    /// Starting a new game asks for the draw count (spec): a small sheet on iPhone, a popover on
    /// iPad, a menu item pair on the Mac. The choice is remembered for the next deal.
    @ViewBuilder
    private var newGameControl: some View {
        #if os(iOS)
        let button = Button("New Game", systemImage: "plus.rectangle.on.rectangle") { choosingNewGame = true }
        Group {
            if UIDevice.current.userInterfaceIdiom == .phone {
                button.sheet(isPresented: $choosingNewGame) {
                    NewGameChooser(store: store, ui: ui) { choosingNewGame = false }
                        .presentationDetents([.height(340)])
                }
            } else {
                button.popover(isPresented: $choosingNewGame) {
                    NewGameChooser(store: store, ui: ui) { choosingNewGame = false }
                        .frame(width: 320)
                }
            }
        }
        .onChange(of: choosingNewGame) { _, open in
            if !open, ui.helpAfterChooser {                    // the chooser asked for help
                ui.helpAfterChooser = false
                ui.showingHelp = true
            }
        }
        #else
        Menu {
            Button("Draw 1") { store.newGame(drawCount: 1) }
            Button("Draw 3") { store.newGame(drawCount: 3) }
        } label: {
            Label("New Game", systemImage: "plus.rectangle.on.rectangle")
        }
        #endif
    }

    static func clock(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func spokenClock(_ elapsed: TimeInterval) -> String {
        let s = Int(elapsed)
        return "\(s / 60) minutes \(s % 60) seconds"
    }
}

private struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}

#if os(iOS)
/// The new-game choice on iPhone (sheet) and iPad (popover): the two draw modes, the current one
/// marked, plus the resume-at-launch setting.
struct NewGameChooser: View {
    let store: GameStore
    let ui: AppUI
    let done: () -> Void
    @AppStorage(AppSettings.resumeKey, store: AppSettings.defaults) private var resumeOnLaunch = true

    var body: some View {
        VStack(spacing: 16) {
            Text("New Game").font(.headline)
            HStack(spacing: 12) {
                choice("Draw 1", count: 1)
                choice("Draw 3", count: 3)
            }
            Toggle("Resume at launch", isOn: $resumeOnLaunch)
                .font(.subheadline)
            HStack {
                Button("How to Play", systemImage: "questionmark.circle") {
                    ui.helpAfterChooser = true
                    done()
                }
                Spacer()
                Button("Cancel", role: .cancel, action: done)
            }
        }
        .padding(24)
    }

    private func choice(_ title: String, count: Int) -> some View {
        Button {
            store.newGame(drawCount: count)
            done()
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.preferredDrawCount == count ? .accentColor : .gray)
        .accessibilityHint(store.preferredDrawCount == count ? "Current choice" : "")
    }
}
#endif
