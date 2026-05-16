import SwiftUI

@main
struct FourKHDApp: App {
    @State private var appContext = WorkspaceAppAssembly.makeAppContext()

    var body: some Scene {
        WindowGroup {
            WorkspaceShell()
                .environment(appContext)
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
