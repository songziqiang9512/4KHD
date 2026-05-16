import SwiftUI

struct HorizontalFilmstrip<Item: Identifiable, Tile: View, TrailingAccessory: View>: View {
    let items: [Item]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onReachedEnd: (() -> Void)?
    @ViewBuilder let tile: (Item, Int, Bool) -> Tile
    @ViewBuilder let trailingAccessory: () -> TrailingAccessory

    @State private var viewportWidth: CGFloat = 0
    @State private var lastBatchStart: Int = -1
    private let tilePitch: CGFloat = 82

    init(
        items: [Item],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        onReachedEnd: (() -> Void)? = nil,
        @ViewBuilder tile: @escaping (Item, Int, Bool) -> Tile,
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onReachedEnd = onReachedEnd
        self.tile = tile
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            onSelect(index)
                        } label: {
                            tile(item, index, selectedIndex == index)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .onAppear {
                            guard let onReachedEnd, index >= items.count - 4 else { return }
                            DispatchQueue.main.async { onReachedEnd() }
                        }
                    }

                    trailingAccessory()
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
                scrollToBatchIfNeeded(selectedIndex: index, scrollProxy: scrollProxy)
            }
            .onAppear {
                scrollToInitialBatch(scrollProxy: scrollProxy)
            }
        }
    }

    private func scrollToBatchIfNeeded(selectedIndex: Int, scrollProxy: ScrollViewProxy) {
        guard items.indices.contains(selectedIndex) else { return }
        let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
        let batchStart = (selectedIndex / tilesPerBatch) * tilesPerBatch
        guard batchStart != lastBatchStart else { return }
        lastBatchStart = batchStart
        withAnimation(.snappy(duration: 0.22)) {
            scrollProxy.scrollTo(batchStart, anchor: .leading)
        }
    }

    private func scrollToInitialBatch(scrollProxy: ScrollViewProxy) {
        guard items.indices.contains(selectedIndex) else { return }
        let tilesPerBatch = max(Int((viewportWidth - 28) / tilePitch), 1)
        lastBatchStart = (selectedIndex / tilesPerBatch) * tilesPerBatch
        scrollProxy.scrollTo(lastBatchStart, anchor: .leading)
    }
}

extension HorizontalFilmstrip where TrailingAccessory == EmptyView {
    init(
        items: [Item],
        selectedIndex: Int,
        onSelect: @escaping (Int) -> Void,
        onReachedEnd: (() -> Void)? = nil,
        @ViewBuilder tile: @escaping (Item, Int, Bool) -> Tile
    ) {
        self.init(
            items: items,
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            onReachedEnd: onReachedEnd,
            tile: tile,
            trailingAccessory: { EmptyView() }
        )
    }
}
