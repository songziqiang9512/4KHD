import AppKit
import Nuke

@MainActor
final class DetailRecommendationsView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onOpenRecommendation: ((OnlineGalleryRecommendation) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "推荐图集")
    private let subtitleLabel = NSTextField(labelWithString: "继续浏览相关内容")
    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private var recommendations: [OnlineGalleryRecommendation] = []
    private var requestConfigurator: ((inout URLRequest) -> Void)?
    private var lastLayoutWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func update(
        recommendations: [OnlineGalleryRecommendation],
        requestConfigurator: ((inout URLRequest) -> Void)?
    ) {
        self.requestConfigurator = requestConfigurator
        guard self.recommendations != recommendations else { return }
        self.recommendations = recommendations
        titleLabel.stringValue = "推荐图集（\(recommendations.count)）"
        lastLayoutWidth = 0
        collectionView.reloadData()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let contentWidth = max(scrollView.contentSize.width, 1)
        guard abs(contentWidth - lastLayoutWidth) > 0.5 else { return }
        lastLayoutWidth = contentWidth

        let minimumSideInset: CGFloat = 20
        let spacing: CGFloat = 16
        let usableWidth = max(contentWidth - minimumSideInset * 2, 1)
        let maximumColumns = min(3, max(recommendations.count, 1))
        let columnCount: Int
        if maximumColumns >= 3, usableWidth >= 3 * 150 + 2 * spacing {
            columnCount = 3
        } else if maximumColumns >= 2, usableWidth >= 2 * 150 + spacing {
            columnCount = 2
        } else {
            columnCount = 1
        }

        let unconstrainedWidth = floor(
            (usableWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        )
        let itemWidth = min(unconstrainedWidth, 220)
        let gridWidth = itemWidth * CGFloat(columnCount) + spacing * CGFloat(columnCount - 1)
        let sideInset = max(minimumSideInset, floor((contentWidth - gridWidth) / 2))

        flowLayout.itemSize = NSSize(width: itemWidth, height: floor(itemWidth * 0.68))
        flowLayout.minimumInteritemSpacing = spacing
        flowLayout.minimumLineSpacing = spacing
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: sideInset, bottom: 32, right: sideInset)
        flowLayout.invalidateLayout()
    }

    func numberOfSections(in _: NSCollectionView) -> Int {
        1
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        recommendations.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: DetailRecommendationCollectionItem.reuseID,
            for: indexPath
        )
        guard let item = item as? DetailRecommendationCollectionItem,
              recommendations.indices.contains(indexPath.item) else { return item }
        item.configure(
            recommendation: recommendations[indexPath.item],
            requestConfigurator: requestConfigurator
        )
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let indexPath = indexPaths.first,
              recommendations.indices.contains(indexPath.item) else { return }
        let recommendation = recommendations[indexPath.item]
        collectionView.deselectItems(at: indexPaths)
        onOpenRecommendation?(recommendation)
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        isHidden = true

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        flowLayout.minimumInteritemSpacing = 14
        flowLayout.minimumLineSpacing = 14
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: 20, bottom: 24, right: 20)
        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            DetailRecommendationCollectionItem.self,
            forItemWithIdentifier: DetailRecommendationCollectionItem.reuseID
        )

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView

        for subview in [titleLabel, subtitleLabel, scrollView] {
            addSubview(subview)
            subview.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),

            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

@MainActor
private final class DetailRecommendationCollectionItem: NSCollectionViewItem {
    static let reuseID = NSUserInterfaceItemIdentifier("DetailRecommendationCollectionItem")

    private let cardView = WorkspaceThumbnailGridCardView()
    private var imageTask: RemoteImageLoadTask?
    private var representedID: OnlineGalleryRecommendation.ID?
    private var currentCoverURL: URL?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(cardView)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: view.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        representedID = nil
        currentCoverURL = nil
        cardView.resetForReuse()
    }

    func configure(
        recommendation: OnlineGalleryRecommendation,
        requestConfigurator: ((inout URLRequest) -> Void)?
    ) {
        let contentChanged = representedID != recommendation.id || currentCoverURL != recommendation.coverURL
        representedID = recommendation.id
        currentCoverURL = recommendation.coverURL
        cardView.setText(
            title: recommendation.title,
            metadata: recommendation.imageCount.map { "\($0) 张图片" } ?? "推荐图集"
        )
        cardView.applySelectionState(false)
        guard contentChanged else { return }

        imageTask?.cancel()
        imageTask = nil
        guard let coverURL = recommendation.coverURL else {
            cardView.setImage(nil)
            cardView.setPlaceholder("暂无缩略图", isVisible: true)
            return
        }

        let request = RemoteImagePipeline.shared.request(
            for: coverURL,
            priority: .normal,
            maxPixelSize: 640,
            configureURLRequest: requestConfigurator
        )
        if let cached = RemoteImagePipeline.shared.cachedImage(with: request) {
            cardView.setImage(cached, animated: false)
            return
        }
        cardView.setImage(nil)

        cardView.setPlaceholder("加载中...", isVisible: true)
        imageTask = RemoteImagePipeline.shared.loadImage(with: request) { [weak self] image in
            guard let self, self.representedID == recommendation.id else { return }
            if let image {
                self.cardView.setImage(image)
            } else {
                self.cardView.setPlaceholder("缩略图不可用", isVisible: true)
            }
        }
    }
}
