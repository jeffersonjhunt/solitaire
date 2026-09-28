# Solitaire

Classic Klondike solitaire for **Mac, iPhone and iPad** — one SwiftUI app, one shared rules
engine, one adaptive board. No ads, no in-app purchases, no accounts and no network access: the
Mac app is sandboxed without a network permission, and nothing leaves the device.

- Draw one or draw three, unlimited redeals
- Tap or click to send a card to its best spot, or drag it exactly where you want it
- Undo (up to 300 steps), auto-finish, and a card cascade when you win
- Your game is saved as you play and picks up where you left off
- VoiceOver labels on every card and empty pile; Reduce Motion turns off all animation

## How to play

**Goal:** move all 52 cards onto the four foundations (the outlined spaces marked **A**, top
right), one pile per suit, from ace up to king.

**The deal:** seven columns; column 1 has one card, column 7 has seven. Only the last card of each
column is face up. The other 24 cards are the **stock** (top left); cards you draw go face up on
the **waste** next to it.

**Moves:**

- **To a foundation:** an ace onto an empty foundation, then the same suit one rank higher
  (A, 2, 3 … K). Cards go up from the waste or from the bottom of a column.
- **Between columns:** a card goes onto a card one rank higher of the opposite colour (a red 7
  onto a black 8). You can move a whole face-up run together, from any face-up card down.
- **Empty column:** only a king, with any run on it.
- **Back from a foundation:** you can drag a foundation's top card back onto a column, under the
  same colour and rank rule.
- When a move uncovers a face-down card at the bottom of a column, it turns over by itself.

**The stock:** tap it to draw — one card, or three in *Draw 3* mode, where only the top card of the
waste can be played. When the stock is empty, tap it again to turn the waste back over (no limit).

**Winning:** once the stock and waste are empty and every card is face up, **Auto-finish** appears
and plays the rest for you. There is no score and no losing — if you are stuck, undo or deal again.

### Controls

| | Mac | iPhone and iPad |
|---|---|---|
| Send a card to its best spot | click (double-click works too) | tap |
| Place a card exactly | drag | drag |
| Draw / turn the waste over | click the stock, or **Space** | tap the stock |
| Undo | **⌘Z** or the toolbar | the toolbar (⌘Z with a keyboard) |
| New game | **⌘N** (remembered draw mode), or **File ▸ New Game: Draw 1 / Draw 3** | the toolbar: choose Draw 1 or Draw 3 |
| Auto-finish | **⌘↩︎** or the toolbar, when offered | the toolbar, when offered |
| Draw mode for the next deal | **Game ▸ Draw Three**, or **Settings (⌘,)** | the new-game sheet (iPhone) or popover (iPad) |
| How to Play | **Help ▸ Solitaire Help** (⌘?) | **How to Play** in the new-game sheet or popover |

A card with nowhere to go gives a little wiggle. Tapping a card on a foundation does nothing, so a
missed tap never pulls a card back down; drag it if you mean to. Once you win, the game is locked:
nothing moves and undo is off.

### Saving and settings

The game in progress is saved after every move and every few seconds, and when you quit or switch
away; it resumes at the next launch (undo history starts fresh). Quitting normally keeps the time
exactly; a force quit returns to the last save, at most five seconds earlier.

Settings: the draw mode for the next deal (default: one card) and whether to resume the game in
progress at launch (default: yes).

Where things live — inside the app's sandbox:

- the game: `Library/Application Support/Solitaire/game.json` (a small versioned JSON file)
- the settings: the app's standard UserDefaults

## Requirements

- macOS 14 or later, iOS / iPadOS 17 or later
- To build: Xcode 16 or later (developed with Xcode 27 on macOS 27), Swift 6

## Building and running

The Xcode project is **generated** from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and is not committed. Change project settings in `project.yml`, never in Xcode's project editor —
the next generation would overwrite them.

**With Xcode:** generate the project, open it and run:

```bash
xcodegen generate            # XcodeGen 2.45.4, the version in .xcodegen-version
open Solitaire.xcodeproj     # choose "My Mac", an iPhone or an iPad simulator, then ⌘R
```

**From a Linux container** (how this app was built), with the `apple-xcodebuild` skill driving a
Mac over SSH — it builds the pinned XcodeGen itself:

```bash
X=~/.claude/skills/apple-xcodebuild/scripts
python3 $X/xc-doctor.py                         # is the Mac ready?
python3 $X/xc-build.py                          # iOS Simulator + macOS
python3 $X/xc-run.py --platform macos           # or --platform ios-sim --device "iPhone 18 Pro"
python3 $X/xc-shot.py --platform macos          # a screenshot of the running app
```

Signing: builds are ad-hoc signed, which is enough for the simulator and your own Mac. A physical
iPhone or iPad needs your Apple team ID (`.devteam`, or `--team`). Distributed builds must not
carry the `get-task-allow` entitlement (see the spec's decisions).

## Testing

| Suite | What it covers | Run it |
|---|---|---|
| Engine (`Packages/SolitaireEngine`) | every rule, the seeded deal, draw/redeal, tap-to-move, auto-finish, a full winning game | `swift test` in the package — on macOS or Linux (`docker run --rm -v "$PWD":/pkg -w /pkg swift:6.1 swift test --scratch-path /tmp/build`) |
| App unit tests | the store (undo, clock, drag), layout at the spec's sizes, VoiceOver roles, saving and resuming | `xc-test.py --platform macos` / `--platform ios-sim`, or ⌘U in Xcode |
| UI tests | the running app: winning and the win sheet, drag vs tap, draw/undo, menus, the draw-count choice, force-quit and relaunch, exact time after quitting | the same commands |

Every behaviour has a test that was shown to fail with that behaviour broken.

**macOS UI tests** need, once, on the Mac:
`sudo automationmodetool enable-automationmode-without-authentication` — otherwise each run asks for
Touch ID or an Apple Watch. Leave the Mac idle while they run: macOS won't bring the app to the
front while you are using another app, and those tests then fail with "Running Background". UI
tests never touch your real game or settings; they use their own save file and settings.

## Project layout

```
spec.md                          the specification, with a Decisions table that overrides it
project.yml                      XcodeGen spec (the .xcodeproj is generated)
Packages/SolitaireEngine/        the rules: pure Swift, no UI, tested on macOS and Linux
Sources/Solitaire/
  GameStore.swift                the only thing that changes the game: intents, undo, clock, saving
  Persistence.swift              the save file, resume checks, launch decision
  SolitaireApp.swift             app, menus and shortcuts, settings
  ContentView.swift, GameBar.swift   window, toolbar, win sheet, new-game chooser
  HowToPlayView.swift            the in-app help
  Board/                         layout metrics, card drawing, drag and tap, win cascade
  UITestScenario.swift           Debug-only positions for UI tests
Tests/SolitaireTests/            unit tests (Swift Testing)
Tests/SolitaireUITests/          UI tests (XCUITest)
```

## Design decisions

`spec.md` is the source of truth. Its **Decisions** table records every choice made while building
— for example how the board fits short screens, why foundation taps do nothing, why ⌘N deals
straight away, and what "same elapsed time" means after a force quit.

## License

MIT — see [LICENSE](LICENSE).
