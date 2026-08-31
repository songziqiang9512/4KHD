import Foundation

enum WorkspaceModuleID: String, Hashable, Codable, Identifiable {
    case fourKHDGallery = "4khdGallery"
    case localLibrary
    case missKon
    case wallhaven
    case favorites
    case knitGallery
    case mrdsGallery

    var id: String {
        rawValue
    }
}

struct WorkspaceRoute: Hashable {
    let moduleID: WorkspaceModuleID
    let itemID: String

    init(moduleID: WorkspaceModuleID, itemID: String) {
        self.moduleID = moduleID
        self.itemID = itemID
    }

    var rawValue: String {
        let encoded = Data(itemID.utf8).base64EncodedString()
        return "\(moduleID.rawValue)|\(encoded)"
    }

    init?(rawValue: String) {
        let parts = rawValue.split(
            separator: "|",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 2,
              let moduleID = WorkspaceModuleID(rawValue: parts[0]),
              let data = Data(base64Encoded: parts[1]),
              let itemID = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        self.moduleID = moduleID
        self.itemID = itemID
    }
}
