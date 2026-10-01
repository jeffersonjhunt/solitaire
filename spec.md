# Solitaire for Apple platforms — build specification

Sep 27, 2026 · @Jefferson

A single SwiftUI Klondike solitaire app for macOS, iOS and iPadOS: one shared game engine, one adaptive board view, no network code, no ads, no in-app purchases, no accounts.

## Scope and platforms

One Xcode project, one multiplatform app target, one shared SwiftUI codebase. Platform differences live in a small number of `#if os(...)` branches, not in separate views.

| Item | Value |
| --- | --- |
| Targets | macOS, iOS, iPadOS (one app target, Mac as native AppKit-backed SwiftUI, not Catalyst) |
| Minimum OS | macOS 14, iOS 17, iPadOS 17 |
| Language | Swift 6, strict concurrency, SwiftUI app lifecycle |
| Dependencies | none — Foundation, SwiftUI, Observation, and SpriteKit only if a win animation is added |
| Orientations | iPhone portrait and landscape; iPad all four; Mac resizable window |
| Game | Klondike only |

Explicitly out of scope: ads, in-app purchases, accounts, sign-in, analytics, crash reporting, remote config, and any network request. The app ships with no `NSAppTransportSecurity` needs and no entitlements beyond sandbox defaults. iCloud sync is out of scope for v1 but the save format must not block it later.

The app must launch straight into a playable board with no splash screen, onboarding, or modal.

## Game rules

Standard Klondike with a 52-card deck, seven tableau columns, four foundations, one stock and one waste.

Deal: column *i* (0-based) receives *i*+1 cards; only its last card is face up. The remaining 24 cards form the stock, all face down.

Legal moves the engine must allow, and nothing else:

- Waste top card, or a tableau column's bottom-most face-up card, to a foundation: an ace onto an empty foundation, otherwise same suit and rank exactly one higher than the foundation's top card.
- A single card, or a run of face-up cards taken from any face-up position in a column, onto another column: the run's first card must be one rank lower than the destination's top card and of the opposite colour. Only a king (with the run below it) may move onto an empty column.
- Foundation top card back to a tableau column, under the same colour-and-rank rule.
- Turning a card face up: when a move leaves a column's last card face down, it flips face up automatically. This is part of the same move for undo purposes.

Draw modes: draw 1 or draw 3, chosen when a game is dealt. Draw 3 turns up to three cards to the waste and only the topmost is playable. Redeals are unlimited: with the stock empty, tapping it returns the waste to the stock in reverse order, face down, and counts as one move.

The game is won when all four foundations hold 13 cards. There is no scoring and no loss state — a stuck game is simply a game the player restarts or undoes out of.

## Architecture

&#91;embedded content: app architecture · 6 components\]

The engine is a value-type library with no SwiftUI import: every rule can be unit-tested without a view. The store is the only object that mutates state, and it saves after each applied move.

## Model types

All model types are `Sendable` value types in a `SolitaireEngine` folder or local Swift package. `GameState` is the whole game: rendering, saving and testing all read from it.

```swift
enum Suit: Int, Codable, CaseIterable, Sendable {
    case spades, hearts, diamonds, clubs
    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct Card: Identifiable, Hashable, Codable, Sendable {
    let suit: Suit
    let rank: Int          // 1...13, ace low
    var isFaceUp: Bool
    var id: Int { suit.rawValue * 13 + rank - 1 }   // stable 0...51
}

enum PileID: Hashable, Codable, Sendable {
    case stock, waste
    case foundation(Int)   // 0...3
    case tableau(Int)      // 0...6
}

struct Move: Hashable, Codable, Sendable {
    let source: PileID
    let index: Int         // first card moved, within the source pile
    let destination: PileID
}

struct GameState: Codable, Sendable {
    var stock: [Card]      // last element is the top, drawn first
    var waste: [Card]
    var foundations: [[Card]]  // always 4
    var tableau: [[Card]]      // always 7
    var drawCount: Int         // 1 or 3
    var moveCount: Int
    var elapsed: TimeInterval
    var isWon: Bool
    var seed: UInt64           // the shuffle seed, for replay and tests
}
```

Order convention: every pile is ordered bottom to top, so `last` is the visible or playable card, and a tableau run to move is `pile[index...]`. `id` is derived from suit and rank so SwiftUI `matchedGeometryEffect` and animations track the same card across piles.

Shuffling uses a seeded generator (`SplitMix64` or similar, roughly 20 lines) rather than `shuffled()`, so a failing game can be reproduced in a test from its seed alone.

## Engine and store API

The engine is a namespace of pure functions over `GameState`. No function may throw for a rejected move — it returns `nil` or `false` so the UI can simply not animate.

```swift
enum SolitaireEngine {
    static func newGame(drawCount: Int, seed: UInt64) -> GameState
    static func canMove(_ move: Move, in state: GameState) -> Bool
    static func apply(_ move: Move, to state: inout GameState)      // precondition: canMove
    static func drawFromStock(_ state: inout GameState)             // draws, or redeals when empty
    static func autoDestination(for source: PileID, index: Int,
                                in state: GameState) -> PileID?     // tap-to-move target
    static func canAutoFinish(_ state: GameState) -> Bool
    static func nextAutoFinishMove(in state: GameState) -> Move?
    static func isWon(_ state: GameState) -> Bool
}
```

Tap-to-move picks a destination in this order: the matching foundation if a single card can go there; then a non-empty tableau column that accepts the run, scanning left to right starting after the source column; then an empty column, unless the run already sits alone at the bottom of a column, which would be a no-op shuffle.

Auto-finish is offered when the stock and waste are empty and every tableau card is face up. It plays the lowest available rank to a foundation every 90 ms until no move remains, and each step is a normal move, so undo walks back through them.

Undo is a stack of `GameState` snapshots pushed before every state change, capped at 300 entries and cleared on a new deal. Draw, redeal, move and flip are all undoable; a flip is never undone separately from the move that caused it. Redo is not required.

`GameStore` is an `@Observable final class` on the main actor. It owns the current `GameState`, the undo stack, a one-second timer that ticks only while the game is started, unwon and the app is active, and the pending drag. Views call intents on it — `tap(pile:index:)`, `drop(source:index:on:)`, `tapStock()`, `undo()`, `newGame(drawCount:)`, `autoFinish()` — and never mutate state themselves.

## Interaction

Every platform supports both ways of moving a card: a single tap or click sends it to the best legal destination, and a drag places it exactly.

| Input | Behaviour |
| --- | --- |
| Tap or click a face-up card | Move it (with the run below it) to the auto destination; if none, a 0.25 s wiggle and no state change |
| Tap or click the stock | Draw; when the stock is empty and the waste is not, redeal |
| Drag | Lift the card and its run above the board, drop on the pile whose frame the dragged card's centre is nearest; an illegal drop springs back |
| Double-click (macOS) | Same as tap — send to foundation if possible |
| Hover (macOS, iPadOS pointer) | Highlight the card under the pointer at 1 px stroke; no other hover effect |

A drag begins after 8 points of movement so a slow tap is still a tap. The dragged run renders in an overlay above all piles with a slightly stronger shadow, tracks the finger or pointer one-to-one, and animates home in 0.2 s on an illegal drop. Only face-up cards are draggable, and only the top card of the waste or a foundation.

Keyboard and menus on macOS, through `CommandGroup`: New Game (⌘N), Undo (⌘Z), Draw (space), Auto-finish (⌘⏎), Toggle draw mode in a Game menu, and the standard window and help groups. On iPadOS the same shortcuts work from a hardware keyboard via `.keyboardShortcut`. VoiceOver labels every card as rank and suit, and every empty pile by name.

Haptics on iOS and iPadOS only: a light impact on a successful move, a soft impact on a stock draw, a success notification on a win. Nothing on failure beyond the wiggle. Sound is out of scope for v1.

## Layout and visuals

`BoardMetrics` is a struct built from the available size in a `GeometryReader`. Everything else reads from it, so there are no magic numbers in the views.

| Metric | Rule |
| --- | --- |
| Board width | Available width, capped at 900 pt and centred |
| Gap | 1.8% of board width, minimum 4 pt; boards narrower than 500 pt (phones in portrait): 3 pt |
| Side margin | Equal to the gap; 4 pt on boards narrower than 500 pt |
| Card width | (board width − 2 side margins − 6 gaps) / 7 |
| Row gap | Space between the top row and the columns: card width × 0.8, at most 16 pt on a touch board wider than it is tall |
| Card height | Card width × 1.4 |
| Corner radius | Card width × 0.09 |
| Top row | Stock at column 0, waste at column 1, foundations at columns 3 to 6 |
| Face-down fan | Card height × 0.12 |
| Face-up fan | Card height × 0.29, scaled down together with the face-down fan when a column would overflow the board |
| Minimum hit target | 44 pt on touch; cards below that width force a compressed layout |

The same seven-column board is used on every platform: on a Mac or iPad the cards simply get larger until the 900 pt cap, and the extra height goes to the tableau. The controls are the same everywhere too (decision 2026-10-01): a header over the board with moves, elapsed time and the draw mode in Space Mono, and a bar along the bottom with four labelled 60 pt buttons — Undo, Finish (auto-finish; burnt orange when available), New Game and More (How to Play, Settings… and About Solitaire). On a phone held sideways the header folds into the bar, whose buttons are then 52 pt.

Cards are drawn in SwiftUI, not images, in the face and back the player has chosen (see "Card styles"): a rounded rectangle with a hairline border and a 1 pt shadow, corner index top-left, a large suit below it.

The table is a dark green gradient that the card faces stay readable against in light and dark mode. Card faces do not invert in dark mode. Moves animate with a 0.2 s `.easeOut`; flips use a 0.25 s rotation on the Y axis. All motion is skipped when `accessibilityReduceMotion` is on.

## Card styles

The player chooses a card face and a card back, independently, in Settings (see "Settings, About and
the More menu"). Four of each ship; the defaults are the original look, so nothing changes for a
player who never opens Settings. Everything is drawn in SwiftUI from these rules — no image files —
and every place a card appears uses the chosen style: the board, a drag in progress, the win
cascade (its cached card images are keyed by style), and the Settings previews.

Faces (rank and suit sizes are fractions of the card width):

| Face | Look |
| --- | --- |
| **Classic** (default) | White face; rank in the rounded system font, semibold, × 0.36, small suit × 0.28, top-left; large suit × 0.62, bottom-right; red and black from the asset colours |
| **Big Index** | White face; a heavier, larger corner index — black weight, rank × 0.37, small suit × 0.30 — in pure black and a bright red (#D0021B); large suit × 0.66, centred |
| **Vintage** | Cream face (#FBF4E4) with a fine inner frame (5 % inset); rank in the system serif (New York), bold; ink #1F1F1F and deep red #9E1B32; large suit centred |
| **Night** | Dark face (#262626, border #3A3A3A) with light ink: #EDEAE4 for spades and clubs, #FF7A7A for hearts and diamonds; layout as Classic |

Backs (each a white or tinted card with a patterned panel inset by 7 % of the width):

| Back | Look |
| --- | --- |
| **Classic Blue** (default) | White card; blue panel (#1D4E9C) with a white diagonal lattice at 30 % |
| **Burnt Orange** | The same lattice on #CC5500 |
| **Racing Green** | Cream card (#F7F1E3); green panel (#1F5E3A) of small cream diamonds at 35 %, with a cream inner frame line |
| **Night Pinstripe** | Near-black card (#1E1E1E); panel #141414 with a fine #CC5500 pinstripe at 135° and an orange inner frame line |

Rules every style keeps:

- **Readable when fanned.** A face-up card under another shows only its top strip, which is never
  less than 0.2 × card height (decision D1). Each face's corner index — rank and small suit — fits
  inside that strip at every card size: the index is placed by its capitals, whose tops sit
  0.015 × card width below the card's edge (text's own space above the capitals would otherwise
  push it about 0.09 × width lower). A unit test checks, with the platform's real font metrics,
  that every face's index ends within the strip.
- **Red and black stay distinct** (Klondike alternates them): each face has exactly two ink colours,
  one for hearts and diamonds and one for spades and clubs, and they differ in lightness, not hue alone.
- **No inversion in dark mode:** faces and backs look the same in light and dark appearance; Night
  is a choice, not an automatic mode.
- **Live:** changing a face or back restyles every card at once, including the game in progress.

## Settings, About and the More menu

**More** (the fourth button of the bottom bar) offers three items on every platform: **How to Play**,
**Settings…** and **About Solitaire**. On iPhone it is a menu; on iPad and the Mac a popover. On
the Mac, ⌘, and Solitaire ▸ Settings… open Settings, Solitaire ▸ About Solitaire opens About, and
Game ▸ Draw Three stays in the menu bar.

**Settings** — a sheet on iPhone and iPad, the Settings window on the Mac:

- **Game:** draw mode for the next deal (one card or three; it does not change the game in
  progress) and resume the game in progress at launch.
- **Card face:** the four faces as tappable previews (an ace of hearts in each), the current one
  ringed in burnt orange (#CC5500).
- **Card back:** the four backs as tappable previews, ringed the same way.
- A live preview at the top: the chosen back beside two cards in the chosen face.

Changes apply immediately and are saved at once. The new-game chooser keeps only the choice it
exists for — Draw 1 or Draw 3 (and Cancel); resuming at launch and How to Play live in Settings and
More.

**About** — a sheet on iPhone and iPad, its own window on the Mac (replacing the standard About
panel):

- the app icon, **Solitaire**, and **Version 1.0 (build)** from the bundle;
- one line: Klondike, made by One Off Endeavors; no ads, no accounts, no tracking — nothing leaves
  your device;
- links: **One Off Endeavors** (https://oneoffendeavors.com), **Privacy policy**
  (https://oneoffendeavors.com/solitaire/privacy/), **Support and feedback**
  (https://oneoffendeavors.com/support/);
- **Acknowledgements:** Space Mono, © 2016 The Space Mono Project Authors, SIL Open Font License 1.1,
  with the licence's full text one tap away;
- **© 2026 One Off Endeavors**.

A link opens in the user's default browser. The app itself still makes no network connection of any
kind (on the Mac it remains sandboxed without a network permission).

## Persistence and settings

The game in progress is saved as JSON to `Application Support/Solitaire/game.json` through an actor that writes atomically. It saves after every applied move, on every timer tick divisible by five, and on scene phase leaving `.active`. Nothing is written to iCloud or the network.

On launch the app decodes that file, checks it holds 52 distinct cards and is not already won, and resumes it; anything invalid is discarded silently and a fresh game is dealt. The undo stack is not persisted — a resumed game starts with undo empty.

Settings live in `UserDefaults` via `@AppStorage`: draw count (default 1), a preference for whether to resume or always deal fresh (default resume), the card face (default Classic) and the card back (default Classic Blue). An unknown or invalid stored value falls back to the default. Starting a new game asks for the draw count in a small sheet on iPhone, a popover on iPad and the Mac, and the choice is remembered for the next deal.

On macOS, window size and position restore through the standard scene restoration; the game itself is not tied to a particular window size.

## Acceptance criteria and open decisions

Build the engine and its tests before any view. The app is done when all of these pass.

- [ ] A new deal always produces 52 distinct cards, 28 in the tableau with exactly 7 face up, and 24 in the stock.
- [ ] Every legal move listed in the rules succeeds and every illegal one is refused, covered by unit tests on `canMove`.
- [ ] Draw 3 leaves only the waste's top card playable; redeal restores the stock in reverse order.
- [ ] Undo from any point returns the exact previous state, including face-up flips and redeals, for 100 random moves from a fixed seed.
- [ ] A game played to a win from a known-solvable seed sets `isWon` and shows the win sheet with the move count and time.
- [ ] Tap-to-move never produces a no-op, and dragging a king onto an empty column from the bottom of another column is possible by drag but not offered by tap.
- [ ] Force-quitting mid-game and relaunching restores the same board, move count and elapsed time.
- [ ] The board lays out without clipping on iPhone SE portrait, iPhone Pro Max landscape, iPad split view at one third width, and a 600 pt wide Mac window.
- [ ] Instruments shows no dropped frames while dragging a 13-card run on the oldest supported device.
- [ ] The app builds with no third-party packages and makes no network calls (verify with a proxy or by removing network entitlement).

Open decisions for whoever builds it: whether to ship a win animation (a cascade of cards is the classic, and SpriteKit would be the only added framework), whether to add a hint button, and whether the Mac version gets a full-screen felt background or stays in a bordered window.

## Decisions

Recorded as they are made; each overrides anything above it conflicts with.

| Date | Decision |
| --- | --- |
| 2026-09-27 | Bundle identifier `com.oneoffendeavors.solitaire`. |
| 2026-09-27 | Open decisions: the win animation is a SwiftUI card cascade (no SpriteKit); no hint button in v1; the Mac version stays in a bordered window. |
| 2026-09-27 | Tapping or clicking a card on a foundation does nothing. Taps send cards toward the foundations; taking one back down is drag-only, so a missed tap never undoes progress. |
| 2026-09-27 | Once the game is won, no move or draw is allowed, so a won game cannot be un-won. |
| 2026-09-27 | An invalid stored draw count is clamped by the store before dealing; the engine's `newGame` keeps its 1-or-3 precondition. A resumed save must also have exactly 4 foundations and 7 columns. |
| 2026-09-27 (wording 2026-09-30) | Any build distributed outside this Mac (TestFlight, App Store, a shared `.app`) must not let a debugger attach: on the Mac the `com.apple.security.get-task-allow` entitlement is absent; on iOS/iPadOS `get-task-allow` is `false` (App Store signing always writes the key, set to false). Local development builds allow it, and that is fine for development. `tools/check-release.sh` enforces this before every upload. |
| 2026-09-27 | New games ask for the draw count everywhere (toolbar, win sheet) except ⌘N, which the spec lists as a direct shortcut: it deals at once in the remembered mode. |
| 2026-09-27 | "Same elapsed time" after a relaunch: quitting normally (⌘Q on the Mac, or iOS sending the app to the background) saves on the spot, so the time comes back exactly. A true force quit gives the app no chance to save, so the time comes back to the last save — at most five seconds earlier, the spec's own save cadence. |
| 2026-09-27 | Layout D1 — short, wide boards (phone landscape, short Mac windows): card width is the spec's width rule, capped by height so the top row plus a column of six face-down cards under a nine-card run (K→5) fits with its face-up fan no smaller than 0.2 × card height (readable). Longer runs squeeze further. Where height is plentiful the width rule is unchanged. |
| 2026-09-27 | Layout D2 — "compressed layout": on touch, when cards would be narrower than 44 pt, gaps drop to the 4 pt minimum and each card's tap area widens to its whole column slot. |
| 2026-10-01 | Direction A, chosen from mockups (design canvas "Solitaire layout mockups"): one layout for iPhone, iPad and Mac. Phone-width boards (under 500 pt) use 3 pt column gaps and 4 pt side margins, for cards about 9% larger. A row gap of 0.8 × card width separates the top row from the columns, capped at 16 pt on a touch board held sideways. Header (moves, time, draw mode; Space Mono, SIL OFL) over the board; a bottom bar with four labelled 60 pt buttons (Undo, Finish, New Game, More) on every platform, the Mac included; Finish is burnt orange (#CC5500) when auto-finish is available. On a phone held sideways the header folds into the bar (52 pt buttons), which keeps the cards about as large as before. |
| 2026-10-01 | Card styles, Settings and About (plan agreed from the "Cards" and "Settings and About" mockups): faces Classic, Big Index, Vintage and Night; backs Classic Blue, Burnt Orange, Racing Green and Night Pinstripe; chosen independently, Classic + Classic Blue by default, applied live. Four Colour was left out: blue diamonds and green clubs blur Klondike's red/black alternation. More offers How to Play, Settings… and About Solitaire; Draw Three and Resume move into Settings, and the new-game chooser keeps only Draw 1 / Draw 3. About links open in the browser; the app still has no network code. Copyright line: "© 2026 One Off Endeavors". |
