import Foundation
import Observation

@MainActor
@Observable
final class SidebarDisclosureState {
    private var collapsedFolderIDs = Set<String>()

    func isExpanded(_ folderID: String) -> Bool {
        !collapsedFolderIDs.contains(folderID)
    }

    func setExpanded(_ isExpanded: Bool, for folderID: String) {
        if isExpanded {
            collapsedFolderIDs.remove(folderID)
        } else {
            collapsedFolderIDs.insert(folderID)
        }
    }
}
