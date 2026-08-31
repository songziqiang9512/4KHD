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
        case #selector(WorkspaceSplitViewController.increaseLocalGridColumns(_:)):
            return canAdjustLocalGridColumns(1, moduleID: state.currentModuleID)
        case #selector(WorkspaceSplitViewController.decreaseLocalGridColumns(_:)):
            return canAdjustLocalGridColumns(-1, moduleID: state.currentModuleID)
        case #selector(WorkspaceSplitViewController.selectLocalSortFieldFromMenu(_:)):
            updateLocalSortFieldValidationItem(item, moduleID: state.currentModuleID)
            return presentation(for: state.currentModuleID).showsLocalSort
        case #selector(WorkspaceSplitViewController.selectLocalSortDirectionFromMenu(_:)):
            updateLocalSortDirectionValidationItem(item, moduleID: state.currentModuleID)
            return presentation(for: state.currentModuleID).showsLocalSort
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
            guard presentation(for: state.currentModuleID).showsDetailPane else { return false }
            updateToggleDetailPaneValidationItem(item, isCollapsed: state.isDetailCollapsed)
            return true
        case #selector(WorkspaceSplitViewController.toggleImmersiveMode(_:)):
            guard presentation(for: state.currentModuleID).showsDetailPane else { return false }
            updateImmersiveValidationItem(item, isImmersive: state.isImmersive)
            return state.currentReference != nil
        case #selector(WorkspaceSplitViewController.navigateToSidebar(_:)):
            return !state.isSidebarCollapsed
        case #selector(WorkspaceSplitViewController.navigateToContent(_:)):
            return !state.isContentCollapsed
        case #selector(WorkspaceSplitViewController.navigateToDetail(_:)):
            return presentation(for: state.currentModuleID).showsDetailPane && !state.isDetailCollapsed
        default:
            return true
        }
    }

    private func canRefreshCurrentModule(_ moduleID: WorkspaceModuleID) -> Bool {
        let fields = appContext.toolbarContext.snapshot(for: moduleID).fields
        let profile = presentation(for: moduleID)
        return !fields.isRefreshing && (!profile.refreshRequiresSelection || fields.hasSelection)
    }

    private func presentation(for moduleID: WorkspaceModuleID) -> WorkspaceModulePresentationProfile {
        appContext.moduleRegistry.descriptor(for: moduleID)?.presentation ?? .standard
    }

    private func canShareCurrentModule(_ moduleID: WorkspaceModuleID) -> Bool {
        appContext.toolbarContext.snapshot(for: moduleID).fields.canShare
    }

    private func canSaveCurrentImage(_ moduleID: WorkspaceModuleID) -> Bool {
        appContext.toolbarContext.snapshot(for: moduleID).fields.canSaveImage
    }

    private func canResetCurrentZoom(_ moduleID: WorkspaceModuleID) -> Bool {
        appContext.toolbarContext.snapshot(for: moduleID).fields.canResetZoom
    }

    private func canInspectCurrentItem(_ moduleID: WorkspaceModuleID) -> Bool {
        appContext.toolbarContext.currentReference(for: moduleID) != nil
    }

    private func canFavoriteCurrentItem(_ moduleID: WorkspaceModuleID) -> Bool {
        appContext.toolbarContext.snapshot(for: moduleID).fields.canFavorite
    }

    private func canStepImage(_ delta: Int, moduleID: WorkspaceModuleID) -> Bool {
        let fields = appContext.toolbarContext.snapshot(for: moduleID).fields
        return delta < 0 ? fields.canSelectPreviousImage : fields.canSelectNextImage
    }

    private func canAdjustLocalGridColumns(_ delta: Int, moduleID: WorkspaceModuleID) -> Bool {
        let fields = appContext.toolbarContext.snapshot(for: moduleID).fields
        return delta > 0 ? fields.canIncreaseGridColumns : fields.canDecreaseGridColumns
    }

    private func updateFavoriteValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        let fields = appContext.toolbarContext.snapshot(for: moduleID).fields
        guard fields.canFavorite else {
            menuItem.title = "收藏"
            menuItem.state = .off
            return
        }
        let isFavorite = fields.isFavorite
        menuItem.title = isFavorite ? "取消收藏" : "收藏"
        menuItem.state = isFavorite ? .on : .off
    }

    private func updateLayoutValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID,
        isList: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        let selectedLayoutIsList = appContext.toolbarContext.snapshot(for: moduleID).isListLayout
        menuItem.state = selectedLayoutIsList == isList ? .on : .off
    }

    private func updateLocalSortFieldValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem,
              let field = menuItem.representedObject as? LocalImageSortField,
              case let .local(snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else { return }
        menuItem.state = field == snapshot.sortField ? .on : .off
    }

    private func updateLocalSortDirectionValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        moduleID: WorkspaceModuleID
    ) {
        guard let menuItem = item as? NSMenuItem,
              let direction = menuItem.representedObject as? LocalImageSortDirection,
              case let .local(snapshot) = appContext.toolbarContext.snapshot(for: moduleID) else { return }
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
        menuItem.title = isCollapsed ? "显示侧边栏" : "隐藏侧边栏"
        menuItem.state = isCollapsed ? .off : .on
    }

    private func updateToggleDetailPaneValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        isCollapsed: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = isCollapsed ? "显示详情区" : "隐藏详情区"
        menuItem.state = isCollapsed ? .off : .on
    }

    private func updateImmersiveValidationItem(
        _ item: NSValidatedUserInterfaceItem,
        isImmersive: Bool
    ) {
        guard let menuItem = item as? NSMenuItem else { return }
        menuItem.title = isImmersive ? "退出大图模式" : "进入大图模式"
        menuItem.state = isImmersive ? .on : .off
    }
}
