import SwiftUI

/// The in-app help: the rules of Klondike and this platform's controls. On the Mac it is the
/// Help ▸ Solitaire Help window (⌘?); on iPhone and iPad a sheet opened from the new-game chooser
/// or, with a keyboard, the Help menu. The same content as the README's "How to play".
struct HowToPlayView: View {
    var done: (() -> Void)?

    var body: some View {
        ScrollView {
            HowToPlayContent()
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle("How to Play")
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
    }
}

/// The sections themselves, without the scroll view (so they can also be rendered to an image).
struct HowToPlayContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(HowToPlay.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.lines, id: \.self) { line in
                        Text(.init(line))                          // Markdown: **bold** keys
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The help text, kept as data so a test can check it covers the rules and this platform's
/// controls.
enum HowToPlay {
    struct Section: Identifiable {
        let title: String
        let lines: [String]
        var id: String { title }
    }

    static var sections: [Section] {
        [
            Section(title: "Goal", lines: [
                "Move all 52 cards onto the four foundations (marked **A**, top right) — one pile per suit, from ace up to king.",
            ]),
            Section(title: "The deal", lines: [
                "Seven columns: the first has one card, the seventh has seven. Only the last card of each column is face up.",
                "The other 24 cards are the **stock** (top left). Cards you draw go face up on the **waste** beside it.",
            ]),
            Section(title: "Moves", lines: [
                "**To a foundation:** an ace onto an empty foundation, then the same suit one rank higher. Cards go up from the waste or the bottom of a column.",
                "**Between columns:** onto a card one rank higher of the opposite colour — a red 7 onto a black 8. A face-up run moves together.",
                "**Empty column:** only a king, with any run on it.",
                "**Back from a foundation:** drag its top card onto a column, under the same colour and rank rule.",
                "A face-down card uncovered at the bottom of a column turns over by itself.",
            ]),
            Section(title: "The stock", lines: [
                "Draw one card, or three in **Draw 3** mode — then only the top card of the waste can be played.",
                "When the stock is empty, draw again to turn the waste back over. There is no limit.",
            ]),
            Section(title: "Controls", lines: controls),
            Section(title: "Winning", lines: [
                "When the stock and waste are empty and every card is face up, **Auto-finish** appears and plays the rest.",
                "There is no score and no losing: if you are stuck, undo or deal again. Once you win, the game is locked.",
            ]),
            Section(title: "Saving", lines: [
                "Your game is saved as you play and resumes at the next launch (undo starts fresh). \(resumeSetting)",
            ]),
        ]
    }

    /// Where the resume-at-launch switch lives on this platform.
    private static var resumeSetting: String {
        #if os(macOS)
        "You can turn resuming off in **Settings (⌘,)**."
        #else
        "You can turn resuming off in **More** or the **New Game** options."
        #endif
    }

    private static var controls: [String] {
        #if os(macOS)
        [
            "**Click** a card to send it to its best spot (double-click works too); **drag** to place it exactly.",
            "**Click the stock** or press **Space** to draw.",
            "The bar along the bottom: **Undo**, **Finish** (auto-finish, once every card can go home), **New Game** and **More** (How to Play, the draw mode, Settings).",
            "**⌘Z** undo · **⌘N** new game · **⌘↩\u{FE0E}** auto-finish · **File ▸ New Game: Draw 1 / Draw 3** · **Game ▸ Draw Three** · **Settings (⌘,)**.",
            "A card with nowhere to go wiggles. Clicking a card on a foundation does nothing — drag it if you mean to.",
        ]
        #else
        [
            "**Tap** a card to send it to its best spot; **drag** to place it exactly.",
            "**Tap the stock** to draw.",
            "The bar along the bottom: **Undo**, **Finish** (auto-finish, once every card can go home), **New Game** — which asks for Draw 1 or Draw 3 — and **More** (How to Play, the draw mode, resuming at launch).",
            "With a keyboard: **⌘Z** undo · **⌘N** new game · **Space** draw · **⌘↩\u{FE0E}** auto-finish.",
            "A card with nowhere to go wiggles. Tapping a card on a foundation does nothing — drag it if you mean to.",
        ]
        #endif
    }
}

#Preview {
    NavigationStack { HowToPlayView() }
}
