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

struct GalleryGridCard: View {
    @Environment(LibraryStore.self) private var library
    let item: GalleryItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                PosterWebImage(url: item.coverURL, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.74, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        KindBadge(kind: item.kind)
                        Text("\(item.imageCount)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text("\(item.pageCount) 页")
                        Spacer(minLength: 2)
                        if library.isFavorite(item) {
                            Image(systemName: "bookmark.fill")
                        }
                        if library.isCached(item) {
                            Image(systemName: "externaldrive.fill")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
