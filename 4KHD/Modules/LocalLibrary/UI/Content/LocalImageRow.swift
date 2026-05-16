import SwiftUI

struct LocalImageRow: View {
    let image: LocalImageItem
    let metadata: LocalImageMetadata?

    var body: some View {
        HStack(spacing: 10) {
            RemoteImageView(url: image.url, contentMode: .fill, priority: .utility, localMaxPixelSize: 160) {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
            .frame(width: 56, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(image.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let resolutionText {
                    Text(resolutionText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                if let secondaryMetadataText {
                    Text(secondaryMetadataText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var resolutionText: String? {
        formattedResolution(metadata)
    }

    private var secondaryMetadataText: String? {
        formattedSecondaryMetadata(metadata)
    }
}
