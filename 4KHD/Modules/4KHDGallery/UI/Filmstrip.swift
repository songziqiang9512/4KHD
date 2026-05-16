import SwiftUI

/// 详情页底部缩略图条。横向 LazyHStack，按批滚动（不每点一次都 center 当前张）。
/// 倒数第 4 张露面时触发 `onReachedEnd`，让上层拉下一页。
struct Filmstrip: View {
    @Environment(FourKHDGalleryStore.self) private var library

    let slots: [ImageSlot]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onReachedEnd: () -> Void

    var body: some View {
        HorizontalFilmstrip(
            items: slots,
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            onReachedEnd: onReachedEnd
        ) { slot, index, isSelected in
            ZStack(alignment: .bottomLeading) {
                SlotThumbnail(slot: slot)
                Text("#\(slot.displayIndex)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .padding(5)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 0)
            )
        } trailingAccessory: {
            if library.prefetchPageURL != nil {
                LoadingFilmstripTile()
                    .onAppear {
                        DispatchQueue.main.async { onReachedEnd() }
                    }
            }
        }
    }
}
