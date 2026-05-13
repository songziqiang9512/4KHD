import SwiftUI

@main
struct FourKHDApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var localLibrary = LocalLibraryStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceShell()
                .environmentObject(library)
                .environmentObject(localLibrary)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            SidebarCommands()
            ToolbarCommands()
        }
    }
}
