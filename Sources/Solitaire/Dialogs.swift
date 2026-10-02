import SwiftUI

/// The dark cards (spec "Colours and dialogs"): the win card and the "lose this game?" questions,
/// over the table dimmed by a black scrim. One look on every platform, replacing the system
/// sheet and alert, whose gold buttons were hard to read.
enum DialogColors {
    static let card = Color(hex: 0x141414)
    static let hairline = Color(hex: 0x2A2A2A)
    static let title = Color(hex: 0xF4F1EC)
    static let body = Color(hex: 0xC8C3BD)
    static let label = Color(hex: 0x9A9590)
    static let outline = Color(hex: 0x4A4642)
    /// Orange as text on the dark card (7.8:1); #CC5500 is for fills only.
    static let orangeText = Color(hex: 0xFF8A3D)
    static let scrim = Color.black.opacity(0.6)
}

/// A card's buttons: the main one orange with dark text (as Finish), the others outlined, and a
/// plain one for Close. Never keyboard-focused (like the bar): Return and Esc reach them.
struct DialogButtonStyle: ButtonStyle {
    enum Kind { case main, outlined, plain }
    var kind: Kind
    var height: CGFloat = 48
    /// Takes all the width it is offered; false: just its label's width (plus padding).
    var fills = true

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(.system(size: kind == .main ? 17 : 16, weight: kind == .plain ? .regular : (kind == .main ? .bold : .semibold)))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(kind == .main ? TableColors.onAccent : kind == .plain ? DialogColors.body : DialogColors.title)
            .padding(.horizontal, fills ? 8 : 16)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: height)
            .background {
                switch kind {
                case .main: shape.fill(TableColors.accent)
                case .outlined: shape.strokeBorder(DialogColors.outline, lineWidth: 1)
                case .plain: Color.clear
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// The dimmed table and a card on it. `bottom`: anchored to the bottom of the screen (the win
/// card on a phone held upright); otherwise centred, at most `maxWidth` wide. A tap on the dimmed
/// table calls `outside` (nil: the tap does nothing, but still never reaches the board).
struct DialogScrim<Card: View>: View {
    var bottom = false
    var maxWidth: CGFloat = 420
    var outside: (() -> Void)?
    @ViewBuilder let card: () -> Card

    var body: some View {
        ZStack(alignment: bottom ? .bottom : .center) {
            DialogColors.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { outside?() }
                .accessibilityHidden(true)
            card()
                .frame(maxWidth: bottom ? .infinity : maxWidth)
                .padding(bottom ? 12 : 24)
        }
    }
}

/// The card itself: #141414, hairline edge, large corners and a soft shadow. Modal for VoiceOver.
struct DialogCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(EdgeInsets(top: 24, leading: 20, bottom: 18, trailing: 20))
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(DialogColors.card))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(DialogColors.hairline))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier(identifier)
    }
}

/// The small Space Mono label over a card's title ("NEW GAME", "DRAW 1").
struct DialogKicker: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFont.mono(11, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(DialogColors.label)
    }
}

/// "Start a new game?" and the like: a label, the title, the message, then Cancel and the
/// confirming button (spec "Colours and dialogs").
struct QuestionCard: View {
    let request: NewGameRequest
    let cancel: () -> Void
    let confirm: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        DialogCard(identifier: "confirmation") {
            DialogKicker(text: request.kicker)
            Text(request.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DialogColors.title)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Text(request.message)
                .font(.system(size: 16))
                .foregroundStyle(DialogColors.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Cancel", action: cancel)
                    .buttonStyle(DialogButtonStyle(kind: .outlined))
                    .keyboardShortcut(.cancelAction)
                Button(request.confirm, action: confirm)
                    .buttonStyle(DialogButtonStyle(kind: .main))
                    .keyboardShortcut(.defaultAction)
            }
            .focusable(false)
            .padding(.top, 8)
        }
        .onAppear { titleFocused = true }
    }
}

/// The win card: the draw mode, "You won!", the figures in Space Mono, then a new game in the
/// same mode (orange), the other mode, and Close. `wide`: one row of buttons (iPad, the Mac, a
/// phone held sideways); otherwise stacked for a phone held upright.
struct WinCard: View {
    let drawCount: Int
    let moves: Int
    let elapsed: TimeInterval
    var wide = false
    let newGame: (Int) -> Void
    let close: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    private var other: Int { drawCount == 3 ? 1 : 3 }

    var body: some View {
        DialogCard(cornerRadius: wide ? 24 : 28, identifier: "winCard") {
            VStack(spacing: 6) {
                DialogKicker(text: "DRAW \(drawCount)")
                Text("You won!")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DialogColors.title)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                figure("MOVES", "\(moves)", spoken: "\(moves) moves")
                figure("TIME", GameHeader.clock(elapsed), spoken: "Time \(GameHeader.spokenClock(elapsed))")
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { DialogColors.hairline.frame(height: 1) }
            .overlay(alignment: .bottom) { DialogColors.hairline.frame(height: 1) }
            .padding(.vertical, 6)
            buttons
        }
        .onAppear { titleFocused = true }
    }

    private func figure(_ label: String, _ value: String, spoken: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(AppFont.mono(11, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(DialogColors.label)
            Text(value)
                .font(AppFont.mono(20, bold: true, relativeTo: .title3))
                .foregroundStyle(DialogColors.title)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var buttons: some View {
        let same = Button("New Game · Draw \(drawCount)") { newGame(drawCount) }
            .buttonStyle(DialogButtonStyle(kind: .main, height: wide ? 44 : 54))
            .keyboardShortcut(.defaultAction)
        // In one row the main button gets whatever its neighbours leave, so its label is never cut.
        let switchMode = Button("Draw \(other) instead") { newGame(other) }
            .buttonStyle(DialogButtonStyle(kind: .outlined, height: wide ? 44 : 48, fills: !wide))
        let closeButton = Button("Close", action: close)
            .buttonStyle(DialogButtonStyle(kind: wide ? .outlined : .plain, height: 44, fills: !wide))
            .keyboardShortcut(.cancelAction)
        Group {
            if wide {
                HStack(spacing: 8) { closeButton; switchMode; same }
            } else {
                VStack(spacing: 10) { same; switchMode; closeButton }
            }
        }
        .focusable(false)
    }
}
