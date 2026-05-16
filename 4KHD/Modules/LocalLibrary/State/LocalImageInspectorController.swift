import Foundation
import Observation

@MainActor
@Observable
final class LocalImageInspectorController {
    var presentedImageID: LocalImageItem.ID?

    func isShowing(_ image: LocalImageItem) -> Bool {
        presentedImageID == image.id
    }

    func toggle(_ image: LocalImageItem) {
        if presentedImageID == image.id {
            presentedImageID = nil
        } else {
            presentedImageID = image.id
        }
    }

    func dismiss() {
        presentedImageID = nil
    }

    func syncSelection(_ image: LocalImageItem?) {
        guard presentedImageID != nil else { return }
        presentedImageID = image?.id
    }
}
