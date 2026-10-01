import SwiftUI

@main
struct SolitaireApp: App {
    @State private var store = SolitaireApp.makeStore()
    @State private var ui = AppUI()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.register()
    }

    /// The smallest Mac window: tall enough that, under the header and the bottom bar, cards stay
    /// about 50 pt wide or more.
    static let minimumWindow = CGSize(width: 600, height: 520)

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, ui: ui)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.isActive = phase == .active
                    if phase != .active { store.saveNow() }          // leaving the foreground
                }
                #if os(macOS)
                .frame(minWidth: Self.minimumWindow.width, minHeight: Self.minimumWindow.height)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 760)
        #endif
        .commands {
            GameCommands(store: store)
            HelpCommands(ui: ui)
            #if os(macOS)
            AboutCommands()
            #endif
        }

        #if os(macOS)
        Window("How to Play", id: HelpCommands.windowID) {
            HowToPlayView()
                .frame(minWidth: 420, idealWidth: 520, minHeight: 480, idealHeight: 640)
        }
        .defaultSize(width: 520, height: 640)

        Settings {
            SettingsView(store: store)
                .frame(width: 440, height: 720)
        }

        Window("About Solitaire", id: AboutCommands.windowID) {
            AboutView()
                .frame(width: 380)
        }
        .windowResizability(.contentSize)
        #endif
    }

    /// Resume the saved game if the player wants that and it is valid; otherwise deal fresh in the
    /// remembered draw mode. Undo always starts empty.
    private static func makeStore() -> GameStore {
        SaveLocation.resetForTests()
        let url = SaveLocation.url()
        let saver = url.map(GameSaver.init)
        let store: GameStore
        #if DEBUG
        if let scenario = UITestScenario.storeFromEnvironment() {
            scenario.saver = saver
            store = scenario
        } else {
            store = launchFromSave(url: url, saver: saver)
        }
        #else
        store = launchFromSave(url: url, saver: saver)
        #endif
        store.rememberDrawCount = { AppSettings.defaults.set($0, forKey: AppSettings.drawCountKey) }
        saveBeforeTheProcessMayEnd(store)
        return store
    }

    private static func launchFromSave(url: URL?, saver: GameSaver?) -> GameStore {
        let defaults = AppSettings.defaults
        let drawCount = defaults.object(forKey: AppSettings.drawCountKey) as? Int ?? 1
        let resume = defaults.object(forKey: AppSettings.resumeKey) as? Bool ?? true
        let plan = LaunchPlan.decide(saved: url.flatMap(GameSaver.load(from:)), resumePreferred: resume,
                                     drawCount: drawCount)
        return GameStore.launch(plan, drawCount: drawCount, saver: saver)
    }

    /// Quitting on the Mac and backgrounding on iOS may end the process moments later, so wait for
    /// the save to reach disk there — not just start it. (A force quit gives the app no chance at
    /// all; then the last save stands: after every change and every fifth second.) Observers, not
    /// view modifiers, so this works with no window open.
    private static func saveBeforeTheProcessMayEnd(_ store: GameStore) {
        #if os(macOS)
        let name = NSApplication.willTerminateNotification
        #else
        let name = UIApplication.didEnterBackgroundNotification
        #endif
        _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { store.flushSaves() }
        }
    }
}

/// Settings live in UserDefaults (spec): the draw count for the next deal (default 1) and whether
/// to resume the game in progress at launch (default yes). Debug builds let UI tests use their own
/// suite, so a test choosing Draw 3 never changes the player's real preference.
enum AppSettings {
    static let drawCountKey = "drawCount"
    static let resumeKey = "resumeOnLaunch"
    /// The card face and back (spec "Card styles"); an unknown stored value reads as the default.
    static let cardFaceKey = "cardFace"
    static let cardBackKey = "cardBack"

    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["SOLITAIRE_DEFAULTS_SUITE"],
           let custom = UserDefaults(suiteName: suite) {
            return custom
        }
        #endif
        return .standard
    }
}

/// Menus and keyboard shortcuts (spec: New Game ⌘N, Undo ⌘Z, Draw space, Auto-finish ⌘⏎, and
/// Toggle draw mode in a Game menu; the standard window and help groups stay). On the Mac, the
/// File menu also carries the new-game draw-count pair. The same commands give iPadOS its
/// hardware-keyboard shortcuts.
struct GameCommands: Commands {
    let store: GameStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game") { store.newGame() }
                .keyboardShortcut("n")
            Divider()
            Button("New Game: Draw 1") { store.newGame(drawCount: 1) }
            Button("New Game: Draw 3") { store.newGame(drawCount: 3) }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { store.undo() }
                .keyboardShortcut("z")
                .disabled(!store.canUndo)
        }
        CommandMenu("Game") {
            Button("Draw") { store.tapStock() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Auto-finish") { store.autoFinish() }
                .keyboardShortcut(.return)
                .disabled(!store.canAutoFinish)
            Divider()
            Toggle("Draw Three", isOn: Binding(
                get: { store.preferredDrawCount == 3 },
                set: { _ in store.toggleDrawMode() }))
        }
    }
}


/// State for presentations that are not game state: the How to Play sheet on iPhone and iPad.
@Observable @MainActor
final class AppUI {
    var showingHelp = false
    /// Settings and About as sheets on iPhone and iPad (the Mac uses its own windows).
    var showingSettings = false
    var showingAbout = false
}

/// Help ▸ Solitaire Help (⌘?): the How to Play window on the Mac, the help sheet on iPad with a
/// keyboard. Replaces the standard "help isn't available" item.
struct HelpCommands: Commands {
    static let windowID = "how-to-play"
    let ui: AppUI
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Solitaire Help") {
                #if os(macOS)
                openWindow(id: Self.windowID)
                #else
                ui.showingHelp = true
                #endif
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

#if os(macOS)
/// Solitaire ▸ About Solitaire opens the app's own About window, replacing the standard panel.
struct AboutCommands: Commands {
    static let windowID = "about"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Solitaire") { openWindow(id: Self.windowID) }
        }
    }
}
#endif
