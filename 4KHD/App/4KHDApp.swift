import SwiftUI

@main
struct FourKHDApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var localLibrary = LocalLibraryStore()

    var body: some Scene {
        WindowGroup {
            GalleryWorkspaceView()
                .environmentObject(library)
                .environmentObject(localLibrary)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
