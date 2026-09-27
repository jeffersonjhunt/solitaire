import SwiftUI

@main
struct SolitaireApp: App {
    @State private var store = GameStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    store.isActive = phase == .active
                }
        }
    }
}
