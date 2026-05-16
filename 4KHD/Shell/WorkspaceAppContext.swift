import SwiftUI

@MainActor
@Observable
final class WorkspaceAppContext {
    let moduleRegistry: WorkspaceModuleRegistry
    let toolbarContext: WorkspaceToolbarContext
    @ObservationIgnored private let importRootFolderAction: () -> Void

    init(
        moduleRegistry: WorkspaceModuleRegistry,
        toolbarContext: WorkspaceToolbarContext,
        importRootFolderAction: @escaping () -> Void
    ) {
        self.moduleRegistry = moduleRegistry
        self.toolbarContext = toolbarContext
        self.importRootFolderAction = importRootFolderAction
    }

    func importRootFolder() {
        importRootFolderAction()
    }
}
