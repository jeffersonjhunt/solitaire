import SwiftUI

/// Moves, elapsed time, New game, Undo, and Auto-finish when it is available. Placed at the
/// bottom within thumb reach on iPhone, at the top on iPad and Mac (see `ContentView`).
struct GameBar: View {
    let store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
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
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    if reduceMotion { store.undo() } else { withAnimation(BoardView.moveAnimation) { store.undo() } }
                }
                .disabled(!store.canUndo)
                Menu {
                    Button("Draw 1") { store.newGame(drawCount: 1) }
                    Button("Draw 3") { store.newGame(drawCount: 3) }
                } label: {
                    Label("New Game", systemImage: "plus.rectangle.on.rectangle")
                }
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
