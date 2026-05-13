import SwiftUI

struct GalleryRow: View {
    @Environment(LibraryStore.self) private var library
    let item: GalleryItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PosterWebImage(url: item.coverURL, contentMode: .fill)
                .frame(width: 64, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    KindBadge(kind: item.kind)
                    Text("\(item.imageCount) 张 · \(item.pageCount) 页")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 9) {
                    if library.isFavorite(item) {
                        Image(systemName: "bookmark.fill")
                            .symbolRenderingMode(.hierarchical)
                            .help("已收藏")
                    }
                    if library.isCached(item) {
                        Image(systemName: "externaldrive.fill")
                            .symbolRenderingMode(.hierarchical)
                            .help("已缓存")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

struct FavoriteAuthorSectionHeader: View {
    let group: FavoriteAuthorGroup
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
            Text(group.author)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 4)
            Text("\(group.items.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct ListFooterStatus: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: 8) {
            if library.isRefreshingList {
                ProgressView()
                    .controlSize(.small)
                Text("加载下一页")
            } else if library.canLoadMoreList {
                Image(systemName: "arrow.down")
                Text("继续加载")
            } else if !library.visibleItems.isEmpty {
                Text("已到末尾")
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}
