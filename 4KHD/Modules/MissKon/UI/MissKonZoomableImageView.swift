import AppKit
import Nuke

@MainActor
final class MissKonZoomableImageView: WorkspaceZoomableImageView {
    private var imageTask: ImageTask?
    // ImageTask is automatically cancelled when the view is deallocated
    // because Nuke's ImagePipeline uses weak references.

    func loadImage(from url: URL) {
        imageTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: url, priority: .veryHigh, maxPixelSize: 4096,
            configureURLRequest: MissKonRequestFactory.configureImageRequest
        )
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            Task { @MainActor [weak self] in
                guard let self, let image else { return }
                self.imageView.image = image
                self.fitImage(resetMagnification: true)
            }
        }
    }
}
