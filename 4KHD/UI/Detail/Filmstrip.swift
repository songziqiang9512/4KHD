import SwiftUI

/// 详情页底部缩略图条。横向 LazyHStack，按批滚动（不每点一次都 center 当前张）。
/// 倒数第 4 张露面时触发 `onReachedEnd`，让上层拉下一页。
struct Filmstrip: View {
    @Environment(LibraryStore.self) private var library

    let slots: [ImageSlot]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onReachedEnd: () -> Void

    @State private var viewportWidth: CGFloat = 0
    @State private var lastBatchStart: Int = -1
    private let tilePitch: CGFloat = 82   // 72 缩略图 + 10 间距

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(slots.indices, id: \.self) { index in
                        let slot = slots[index]
                        Button {
                            onSelect(index)
                        } label: {
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
                                    .stroke(selectedIndex == index ? Color.accentColor : Color.clear,
                                            lineWidth: selectedIndex == index ? 2 : 0)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .onAppear {
                            // 倒数 4 张以内任何一张露面就续接下一页。
                            // 推后到下一轮 runloop 避免在 view update 阶段写 @Published。
                            if index >= slots.count - 4 {
                                DispatchQueue.main.async { onReachedEnd() }
                            }
                        }
                    }

                    if library.prefetchPageURL != nil {
                        LoadingFilmstripTile()
                            .onAppear {
                                DispatchQueue.main.async { onReachedEnd() }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 112)
            .background(.background)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewportWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, value in viewportWidth = value }
                }
            )
            .onChange(of: selectedIndex) { _, index in
                guard slots.indices.contains(index) else { return }
                // 只在选中的缩略图跨过整批可见窗口时才滚动，让用户能在一屏内连续切换。
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                let batchStart = (index / tilesPerBatch) * tilesPerBatch
                guard batchStart != lastBatchStart else { return }
                lastBatchStart = batchStart
                withAnimation(.snappy(duration: 0.22)) {
                    scrollProxy.scrollTo(batchStart, anchor: .leading)
                }
            }
            .onAppear {
                guard slots.indices.contains(selectedIndex) else { return }
                let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
                lastBatchStart = (selectedIndex / tilesPerBatch) * tilesPerBatch
                scrollProxy.scrollTo(lastBatchStart, anchor: .leading)
            }
        }
    }
}
