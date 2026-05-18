import AppKit

struct WorkspaceCommandValidationState {
    let currentModuleID: WorkspaceModuleID
    let currentReference: WorkspaceCurrentReference?
    let searchFieldIsAvailable: Bool
    let isSidebarCollapsed: Bool
    let isContentCollapsed: Bool
    let isDetailCollapsed: Bool
    let isImmersive: Bool
}

@MainActor
final class WorkspaceCommandValidator {
    private let appContext: WorkspaceAppContext

    init(appContext: WorkspaceAppContext) {
        self.appContext = appContext
    }

    func validate(
        _ item: NSValidatedUserInterfaceItem,
        state: WorkspaceCommandValidationState
    ) -> Bool {
        switch item.action {
        case #selector(WorkspaceSplitViewController.moveFocusToSearchField(_:)):
            return state.searchFieldIsAvailable
        case #selector(WorkspaceSplitViewController.refreshCurrentContent(_:)):
            return canRefreshCurrentModule(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.toggleCurrentFavorite(_:)):
            updateFavoriteValidationItem(item, moduleID: state.currentModuleID)
            return canFavoriteCurrentItem(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.selectPreviousImage(_:)):
            return canStepImage(-1, moduleID: state.currentModuleID)
        case #selector(WorkspaceSplitViewController.selectNextImage(_:)):
            return canStepImage(1, moduleID: state.currentModuleID)
        case #selector(WorkspaceSplitViewController.setContentListLayout(_:)):
            updateLayoutValidationItem(item, moduleID: state.currentModuleID, isList: true)
            return true
        case #selector(WorkspaceSplitViewController.setContentGridLayout(_:)):
            updateLayoutValidationItem(item, moduleID: state.currentModuleID, isList: false)
            return true
        case #selector(WorkspaceSplitViewController.selectLocalSortFieldFromMenu(_:)):
            updateLocalSortFieldValidationItem(item, moduleID: state.currentModuleID)
            return state.currentModuleID == .localLibrary
        case #selector(WorkspaceSplitViewController.selectLocalSortDirectionFromMenu(_:)):
            updateLocalSortDirectionValidationItem(item, moduleID: state.currentModuleID)
            return state.currentModuleID == .localLibrary
        case #selector(WorkspaceSplitViewController.openCurrentReference(_:)):
            return state.currentReference != nil
        case #selector(WorkspaceSplitViewController.showCurrentInspector(_:)):
            return canInspectCurrentItem(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.saveCurrentImage(_:)):
            return canSaveCurrentImage(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.resetCurrentZoom(_:)):
            return canResetCurrentZoom(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.copyCurrentReference(_:)):
            updateCopyReferenceValidationItem(item, reference: state.currentReference)
            return state.currentReference != nil
        case #selector(WorkspaceSplitViewController.revealCurrentFileInFinder(_:)),
             #selector(WorkspaceSplitViewController.quickLookCurrentFile(_:)),
             #selector(WorkspaceSplitViewController.setCurrentFileAsDesktopWallpaper(_:)):
            return state.currentReference?.fileURL != nil
        case #selector(WorkspaceSplitViewController.shareCurrentContent(_:)):
            return canShareCurrentModule(state.currentModuleID)
        case #selector(WorkspaceSplitViewController.importLocalFolder(_:)):
            return true
        case #selector(WorkspaceSplitViewController.toggleWorkspaceSidebar(_:)):
            updateToggleSidebarValidationItem(item, isCollapsed: state.isSidebarCollapsed)
            return true
        case #selector(WorkspaceSplitViewController.toggleWorkspaceDetailPane(_:)):
            updateToggleDetailPaneValidationItem(item, isCollapsed: state.isDetailCollapsed)
            return true
        case #selector(WorkspaceSplitViewController.toggleImmersiveMode(_:)):
            updateImmersiveValidationItem(item, isImmersive: state.isImmersive)
            return state.currentReference != nil
        case #selector(WorkspaceSplitViewController.navigateToSidebar(_:)):
            return !state.isSidebarCollapsed
        case #selector(WorkspaceSplitViewController.navigateToContent(_:)):
            return !state.isContentCollapsed
        case #selector(WorkspaceSplitViewController.navigateToDetail(_:)):
            return !state.isDetailCollapsed
        default:
            return true
        }
    }

    private func canRefreshCurrentModule(_ moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return !snapshot.isRefreshing
        case .local(let snapshot):
            return !snapshot.isRefreshing && snapshot.hasSelection
        }
    }

    private func canShareCurrentModule(_ moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return snapshot.canShare
        case .local(let snapshot):
            return snapshot.canShare
        }
    }

    private func canSaveCurrentImage(_ moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return snapshot.canSaveImage
        case .local(let snapshot):
            return snapshot.canSaveImage
        }
    }

    private func canResetCurrentZoom(_ moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return snapshot.canResetZoom
        case .local(let snapshot):
            return snapshot.canResetZoom
        }
    }

    private func canInspectCurrentItem(_ moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return snapshot.canShare
        case .local(let snapshot):
            return snapshot.hasSelection
        }
    }

    private func canFavoriteCurrentItem(_ moduleID: WorkspaceModuleID) -> Bool {
        guard case .gallery(let snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else {
            return false
        }
        return snapshot.canFavorite
    }

    private func canStepImage(_ delta: Int, moduleID: WorkspaceModuleID) -> Bool {
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            return delta < 0 ? snapshot.canSelectPreviousImage : snapshot.canSelectNextImage
        case .local(let snapshot):
            return delta < 0 ? snapshot.canSelectPreviousImage : snapshot.canSelectNextImage
        }
    }

    private func updateFavoriteValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        guard case .gallery(let snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else {
            menuItem.title = "Favorite"
            menuItem.state = .off
            return
        }
        menuItem.title = snapshot.isFavorite ? "Unfavorite" : "Favorite"
        menuItem.state = snapshot.isFavorite ? .on : .off
    }

    private func updateLayoutValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID,
        isList: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        let selectedLayoutIsList: Bool
        switch appContext.toolbarContext.snapshot(for: moduleID) {
        case .gallery(let snapshot):
            selectedLayoutIsList = snapshot.layout == .list
        case .local(let snapshot):
            selectedLayoutIsList = snapshot.layout == .list
        }
        menuItem.state = selectedLayoutIsList == isList ? .on : .off
    }

    private func updateLocalSortFieldValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem,
              let field = menuItem.representedObject as? LocalImageSortField,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else { return }
        menuItem.state = field == snapshot.sortField ? .on : .off
    }

    private func updateLocalSortDirectionValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem,
              let direction = menuItem.representedObject as? LocalImageSortDirection,
              case .local(let snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else { return }
        menuItem.state = direction == snapshot.sortDirection ? .on : .off
    }

    private func updateCopyReferenceValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        reference: WorkspaceCurrentReference?
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = reference?.copyMenuTitle ?? "Copy Link"
    }

    private func updateToggleSidebarValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        isCollapsed: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = isCollapsed ? "Show Sidebar" : "Hide Sidebar"
        menuItem.state = isCollapsed ? .off : .on
    }

    private func updateToggleDetailPaneValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        isCollapsed: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = isCollapsed ? "Show Detail" : "Hide Detail"
        menuItem.state = isCollapsed ? .off : .on
    }

    private func updateImmersiveValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        isImmersive: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = isImmersive ? "Exit Immersive Mode" : "Enter Immersive Mode"
        menuItem.state = isImmersive ? .on : .off
    }
}
