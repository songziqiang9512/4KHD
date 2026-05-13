import SwiftUI

@main
struct FourKHDApp: App {
    // @Observable stores 用 @State 持有；通过 .environment(_:) 注入。
    @State private var library = LibraryStore()
    @State private var localLibrary = LocalLibraryStore()

    var body: some Scene {
        WindowGroup {
            WorkspaceShell()
                .environment(library)
                .environment(localLibrary)
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
