import SwiftUI

struct PosterWebImage: View {
    let url: URL?
    let contentMode: ContentMode

    var body: some View {
        RemoteImageView(
            url: url,
            contentMode: contentMode,
            priority: .background,
            remoteMaxPixelSize: 180,
            remoteRequestConfigurator: GalleryRequestFactory.configureImageRequest
        ) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}

struct SlotThumbnail: View {
    let slot: ImageSlot

    var body: some View {
        RemoteImageView(
            url: slot.knownURL,
            contentMode: .fill,
            priority: .low,
            remoteMaxPixelSize: 220,
            remoteRequestConfigurator: GalleryRequestFactory.configureImageRequest
        ) {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct KindBadge: View {
    let kind: ContentKind

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String {
        switch kind {
        case .gallery: "图集"
        case .recommended: "推荐"
        case .advertisement: "广告"
        }
    }

    private var color: Color {
        switch kind {
        case .gallery: .secondary
        case .recommended: .blue
        case .advertisement: .orange
        }
    }
}
