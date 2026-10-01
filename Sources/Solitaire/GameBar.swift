import CoreText
import SwiftUI

/// Space Mono (SIL Open Font License; Resources/Fonts) for the header's figures — the One Off
/// Endeavors type. Registered at launch for this process only; should that ever fail,
/// `Font.custom` falls back to the system font.
enum AppFont {
    static let regular = "SpaceMono-Regular"
    static let bold = "SpaceMono-Bold"

    static func register() {
        for name in [regular, bold] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func mono(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle) -> Font {
        .custom(bold ? Self.bold : regular, size: size, relativeTo: style)
    }
}

/// Colours of the table's controls (direction A, from the One Off Endeavors palette).
enum TableColors {
    static let text = Color(red: 0.957, green: 0.945, blue: 0.925)          // #F4F1EC
    static let accent = Color(red: 0.8, green: 0.333, blue: 0)               // #CC5500, burnt orange
    static let onAccent = Color(red: 0.039, green: 0.039, blue: 0.039)       // #0A0A0A
}

/// Moves, time and this game's draw mode, over the board — the same on every platform, its edges
/// in line with the outer columns (`width`, the board's used width). `compact`: the smaller form
/// that sits inside the bar on a phone held sideways.
struct GameHeader: View {
    let store: GameStore
    var width: CGFloat?
    var compact = false

    var body: some View {
        if compact {
            stats.foregroundStyle(TableColors.text).fixedSize()
        } else {
            stats
                .foregroundStyle(TableColors.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .frame(maxWidth: width ?? BoardMetrics.maxBoardWidth)
                .frame(maxWidth: .infinity)
        }
    }

    private var stats: some View {
        HStack(alignment: .bottom, spacing: compact ? 14 : 22) {
            stat("MOVES", "\(store.state.moveCount)")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(store.state.moveCount) moves")
                .accessibilityAddTraits(.isStaticText)
            stat("TIME", Self.clock(store.state.elapsed))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Time \(Self.spokenClock(store.state.elapsed))")
                .accessibilityAddTraits(.isStaticText)
            if !compact { Spacer(minLength: 8) }
            let chip = Self.drawChip(current: store.state.drawCount, next: store.preferredDrawCount)
            Text(chip.text)
                .font(AppFont.mono(11, relativeTo: .caption2))
                .tracking(1.1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(TableColors.text.opacity(0.3)))
                .accessibilityLabel(chip.spoken)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.mono(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(TableColors.text.opacity(0.66))
            Text(value)
                .font(AppFont.mono(compact ? 17 : 20, bold: true, relativeTo: .title3))
        }
    }

    /// This game's draw mode — and the next deal's, when it has been changed (More, Game ▸ Draw
    /// Three), so the change shows at once instead of only after the next deal.
    nonisolated static func drawChip(current: Int, next: Int) -> (text: String, spoken: String) {
        let word = { $0 == 3 ? "three" : "one" }
        if current == next { return ("DRAW \(current)", "Draw \(word(current))") }
        return ("DRAW \(current) · NEXT \(next)", "Draw \(word(current)); next game draws \(word(next))")
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

/// The four controls along the bottom, the same on every platform: Undo, Finish (burnt orange
/// when auto-finish is available), New Game (asks for the draw count) and More. Each is a 60 pt
/// tall target; on iPad and the Mac the row is centred, at most 560 pt wide. `withStats`: a phone
/// held sideways, where height is short — the header folds in on the left and the buttons are
/// 52 pt tall, which gives the cards back the header's height.
struct ActionBar: View {
    let store: GameStore
    let ui: AppUI
    var withStats = false
    @State private var choosingNewGame = false
    #if os(iOS)
    @AppStorage(AppSettings.resumeKey, store: AppSettings.defaults) private var resumeOnLaunch = true
    #else
    @State private var showingMore = false
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        HStack(spacing: 16) {
            if withStats {
                GameHeader(store: store, compact: true)
                Spacer(minLength: 0)
            }
            buttons.frame(maxWidth: withStats ? 480 : 560)
        }
        .padding(8)
        .padding(.horizontal, withStats ? 8 : 0)
        .frame(maxWidth: .infinity)
        .environment(\.barButtonHeight, withStats ? 52 : 60)
        .background { Color.black.opacity(0.3).ignoresSafeArea(edges: [.bottom, .horizontal]) }
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var buttons: some View {
        HStack(spacing: 4) {
            Button { store.undo() } label: { BarLabel(title: "Undo", symbol: "arrow.uturn.backward") }
                .disabled(!store.canUndo)                       // also off once the game is won
            Button { store.autoFinish() } label: { BarLabel(title: "Finish", symbol: "forward") }
                .buttonStyle(BarButtonStyle(prominent: store.canAutoFinish))
                .disabled(!store.canAutoFinish)
                .accessibilityLabel("Auto-finish")
                .accessibilityInputLabels(["Finish", "Auto-finish"])   // Voice Control: the visible word works
            newGameControl
            moreControl
        }
        .buttonStyle(BarButtonStyle())
    }

    private var drawThree: Binding<Bool> {
        Binding(get: { store.preferredDrawCount == 3 }, set: { _ in store.toggleDrawMode() })
    }

    /// Starting a new game asks for the draw count (spec): a small sheet on iPhone, a popover on
    /// iPad and the Mac. The choice is remembered for the next deal.
    @ViewBuilder
    private var newGameControl: some View {
        let button = Button { choosingNewGame = true } label: {
            BarLabel(title: "New Game", symbol: "plus.rectangle.on.rectangle")
        }
        #if os(iOS)
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
        button.popover(isPresented: $choosingNewGame, arrowEdge: .top) {
            VStack(spacing: 12) {
                Text("New Game").font(.headline)
                HStack(spacing: 10) {
                    ForEach([1, 3], id: \.self) { count in
                        Button("Draw \(count)") {
                            choosingNewGame = false
                            store.newGame(drawCount: count)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(store.preferredDrawCount == count ? .accentColor : .gray)
                    }
                }
            }
            .padding(16)
        }
        #endif
    }

    /// How to Play, the draw mode for the next deal, and (iOS) resuming at launch or (Mac) Settings.
    @ViewBuilder
    private var moreControl: some View {
        #if os(iOS)
        Menu {
            Button("How to Play", systemImage: "questionmark.circle") { ui.showingHelp = true }
            Toggle("Draw Three", isOn: drawThree)
            Toggle("Resume at launch", isOn: $resumeOnLaunch)
        } label: {
            BarLabel(title: "More", symbol: "ellipsis.circle")
        }
        .menuStyle(.button)
        #else
        Button { showingMore = true } label: { BarLabel(title: "More", symbol: "ellipsis.circle") }
            .popover(isPresented: $showingMore, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("How to Play") {
                        showingMore = false
                        openWindow(id: HelpCommands.windowID)
                    }
                    Toggle("Draw Three", isOn: drawThree)
                    SettingsLink { Text("Settings…") }
                }
                .padding(16)
            }
        #endif
    }
}

extension EnvironmentValues {
    /// The bar buttons' height: 60 pt, or 52 pt in the shorter landscape bar (both ≥ 44 pt).
    @Entry var barButtonHeight: CGFloat = 60
}

/// An icon over a short label, filling its share of the bar.
struct BarLabel: View {
    let title: String
    let symbol: String
    @Environment(\.barButtonHeight) private var height

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(height: 26)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: height)
    }
}

/// The bar's buttons: plain on the felt, burnt orange when prominent, dimmed when disabled.
struct BarButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .foregroundStyle(prominent ? TableColors.onAccent : TableColors.text)
            .background(shape.fill(prominent ? TableColors.accent
                                   : configuration.isPressed ? Color.white.opacity(0.12) : .clear))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.38)
            .contentShape(shape)
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
