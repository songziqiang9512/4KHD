import SwiftUI

@main
struct FourKHDApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            GalleryWorkspaceView()
                .environmentObject(library)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
