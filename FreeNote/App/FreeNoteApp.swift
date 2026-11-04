import SwiftUI

@main
struct FreeNoteApp: App {
    @StateObject private var store = FreeNoteStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(store)
        }
    }
}
