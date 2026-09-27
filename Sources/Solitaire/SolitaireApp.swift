import SwiftUI

@main
struct SolitaireApp: App {
    @State private var store = SolitaireApp.makeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.isActive = phase == .active
                }
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 420)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1000, height: 760)
        #endif
        .commands { GameCommands(store: store) }
    }

    private static func makeStore() -> GameStore {
        #if DEBUG
        if let store = UITestScenario.storeFromEnvironment() { return store }
        #endif
        return GameStore()
    }
}

/// Menus and keyboard shortcuts (spec: New Game ⌘N, Undo ⌘Z, Draw space, Auto-finish ⌘⏎, and
/// Toggle draw mode in a Game menu; the standard window and help groups stay). The same
/// commands give iPadOS its hardware-keyboard shortcuts.
struct GameCommands: Commands {
    let store: GameStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Game") { store.newGame() }
                .keyboardShortcut("n")
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

