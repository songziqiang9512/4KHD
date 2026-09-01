import AppKit

enum WorkspaceAppAssembly {
    @MainActor
    static func makeAppContext() -> WorkspaceAppContext {
        let favoritesStore = FavoritesStore()
        let favoritesModuleStore = FavoritesModuleStore(favoritesStore: favoritesStore)
        let favoritesPreferences = FavoritesContentPreferences()
        let favoritesDetailStore = FavoritesDetailStore()
        let favoritesDetailInteraction = FavoritesDetailInteractionController()
        let fourKHDGalleryStore = FourKHDGalleryStore(favorites: favoritesStore)
        let galleryPreferences = GalleryContentPreferences()
        let galleryDetailInteraction = GalleryDetailInteractionController()
        let missKonFeedStore = MissKonFeedStore()
        let missKonDetailStore = MissKonDetailStore()
        let missKonStore = MissKonGalleryStore(feed: missKonFeedStore, detail: missKonDetailStore, favorites: favoritesStore)
        let missKonPreferences = MissKonContentPreferences()
        let missKonDetailInteraction = MissKonDetailInteractionController()
        let wallhavenAccountStore = WallhavenAccountStore()
        let wallhavenPreferences = WallhavenContentPreferences()
        let wallhavenFeedStore = WallhavenFeedStore(accountStore: wallhavenAccountStore, preferences: wallhavenPreferences)
        let knitStore = KnitGalleryStore(favorites: favoritesStore)
        let knitPreferences = KnitContentPreferences()
        let downloadStore = DownloadStore()
        let knitDetailInteraction = KnitDetailInteractionController(downloadStore: downloadStore)
        let knitVideoPlayer = KnitVideoPlayerWindowController()
        let mrdsStore = MrdsGalleryStore(favorites: favoritesStore)
        let mrdsPreferences = MrdsContentPreferences()
        let mrdsDetailInteraction = MrdsDetailInteractionController(downloadStore: downloadStore)
        let quanjiStore = QuanjiGalleryFactory.makeStore(favorites: favoritesStore)
        let quanjiPreferences = OnlineVideoContentPreferences(
            layoutKey: "com.songziqiang.4khd.quanji.layout",
            gridColumnsKey: "com.songziqiang.4khd.quanji.gridColumns"
        )
        let quanjiDetailInteraction = OnlineVideoDetailInteractionController(
            downloadStore: downloadStore,
            policySource: .quanji,
            sourceTitle: "木瓜视频",
            userAgent: QuanjiRequestFactory.userAgent,
            referer: QuanjiRequestFactory.htmlOrigin
        )
        let pornyStore = PornyGalleryFactory.makeStore(favorites: favoritesStore)
        let pornyPreferences = OnlineVideoContentPreferences(
            layoutKey: "com.songziqiang.4khd.porny.layout",
            gridColumnsKey: "com.songziqiang.4khd.porny.gridColumns"
        )
        let pornyDetailInteraction = OnlineVideoDetailInteractionController(
            downloadStore: downloadStore,
            policySource: .porny,
            sourceTitle: "91PORNY",
            userAgent: PornyRequestFactory.userAgent,
            referer: PornyRequestFactory.htmlOrigin
        )
        let tangxinStore = TangxinGalleryFactory.makeStore(favorites: favoritesStore)
        let tangxinPreferences = OnlineVideoContentPreferences(
            layoutKey: "com.songziqiang.4khd.tangxin.layout",
            gridColumnsKey: "com.songziqiang.4khd.tangxin.gridColumns"
        )
        let tangxinDetailInteraction = OnlineVideoDetailInteractionController(
            downloadStore: downloadStore,
            policySource: .tangxin,
            sourceTitle: "糖心Vlog",
            userAgent: TangxinRequestFactory.userAgent,
            referer: TangxinRequestFactory.htmlOrigin
        )
        configureFavoriteSourceAdapters(
            wallhavenPageResolver: { detailPageURL in
                let detail = try await wallhavenFeedStore.favoriteDetail(forDetailPageURL: detailPageURL)
                return FavoriteResolvedImagePage(
                    imageURLs: [detail.imageURL],
                    pageURLs: [detailPageURL],
                    metadata: detail.wallpaper.map(makeWallhavenFavoriteMetadata)
                )
            },
            knitVideoActions: FavoriteVideoActions(
                play: { record, sourceURL in
                    guard let item = KnitFavoritesBridge.item(from: record) else { return }
                    knitVideoPlayer.play(url: sourceURL, title: record.title) {
                        knitDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                    }
                },
                saveAsMP4: { record, sourceURL in
                    guard let item = KnitFavoritesBridge.item(from: record) else { return }
                    knitDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                },
                preparePlay: { record in
                    knitVideoPlayer.beginPreparingPlayback(title: record.title, source: .knit)
                },
                playFailed: { message in
                    knitVideoPlayer.presentResolveFailure(message: message)
                }
            ),
            mrdsVideoActions: FavoriteVideoActions(
                play: { record, sourceURL in
                    guard let item = MrdsFavoritesBridge.item(from: record) else { return }
                    knitVideoPlayer.play(
                        url: sourceURL,
                        title: record.title,
                        source: .mrds,
                        userAgent: MrdsRequestFactory.userAgent
                    ) {
                        mrdsDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                    }
                },
                saveAsMP4: { record, sourceURL in
                    guard let item = MrdsFavoritesBridge.item(from: record) else { return }
                    mrdsDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                },
                preparePlay: { record in
                    knitVideoPlayer.beginPreparingPlayback(title: record.title, source: .mrds)
                },
                playFailed: { message in
                    knitVideoPlayer.presentResolveFailure(message: message)
                }
            ),
            quanjiVideoActions: FavoriteVideoActions(
                play: { record, sourceURL in
                    guard let item = QuanjiFavoritesBridge.item(from: record) else { return }
                    knitVideoPlayer.play(
                        url: sourceURL,
                        title: record.title,
                        source: .quanji,
                        userAgent: QuanjiRequestFactory.userAgent
                    ) {
                        quanjiDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                    }
                },
                saveAsMP4: { record, sourceURL in
                    guard let item = QuanjiFavoritesBridge.item(from: record) else { return }
                    quanjiDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                },
                preparePlay: { record in
                    knitVideoPlayer.beginPreparingPlayback(title: record.title, source: .quanji)
                },
                playFailed: { message in
                    knitVideoPlayer.presentResolveFailure(message: message)
                }
            ),
            pornyVideoActions: FavoriteVideoActions(
                play: { record, sourceURL in
                    guard let item = PornyFavoritesBridge.item(from: record) else { return }
                    knitVideoPlayer.play(
                        url: sourceURL,
                        title: record.title,
                        source: .porny,
                        userAgent: PornyRequestFactory.userAgent
                    ) {
                        pornyDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                    }
                },
                saveAsMP4: { record, sourceURL in
                    guard let item = PornyFavoritesBridge.item(from: record) else { return }
                    pornyDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                },
                preparePlay: { record in
                    knitVideoPlayer.beginPreparingPlayback(title: record.title, source: .porny)
                },
                playFailed: { message in
                    knitVideoPlayer.presentResolveFailure(message: message)
                }
            ),
            tangxinVideoActions: FavoriteVideoActions(
                play: { record, sourceURL in
                    guard let item = TangxinFavoritesBridge.item(from: record) else { return }
                    knitVideoPlayer.play(
                        url: sourceURL,
                        title: record.title,
                        source: .tangxin,
                        userAgent: TangxinRequestFactory.userAgent,
                        referer: TangxinRequestFactory.htmlOrigin
                    ) {
                        tangxinDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                    }
                },
                saveAsMP4: { record, sourceURL in
                    guard let item = TangxinFavoritesBridge.item(from: record) else { return }
                    tangxinDetailInteraction.saveVideo(item: item, sourceURL: sourceURL)
                },
                preparePlay: { record in
                    knitVideoPlayer.beginPreparingPlayback(title: record.title, source: .tangxin)
                },
                playFailed: { message in
                    knitVideoPlayer.presentResolveFailure(message: message)
                }
            )
        )
        let wallhavenStore = WallhavenGalleryStore(feed: wallhavenFeedStore, favorites: favoritesStore)
        let wallhavenDetailInteraction = WallhavenDetailInteractionController()
        let localLibraryStore = LocalLibraryStore()
        let localPreferences = LocalLibraryContentPreferences()
        let localDetailInteraction = LocalDetailInteractionController()
        let filmstripVisibility = FilmstripVisibilityController()
        let detailPaneController = WorkspaceDetailPaneController()
        let importRootFolderAction = {
            guard let folderURL = LocalLibraryImportService.chooseFolder() else { return }
            localLibraryStore.importRootFolder(folderURL)
        }
        let moduleRegistry = makeModuleRegistry(
            fourKHDGalleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            missKonStore: missKonStore,
            missKonPreferences: missKonPreferences,
            missKonDetailInteraction: missKonDetailInteraction,
            wallhavenStore: wallhavenStore,
            wallhavenPreferences: wallhavenPreferences,
            wallhavenDetailInteraction: wallhavenDetailInteraction,
            knitStore: knitStore,
            knitPreferences: knitPreferences,
            knitDetailInteraction: knitDetailInteraction,
            knitVideoPlayer: knitVideoPlayer,
            mrdsStore: mrdsStore,
            mrdsPreferences: mrdsPreferences,
            mrdsDetailInteraction: mrdsDetailInteraction,
            quanjiStore: quanjiStore,
            quanjiPreferences: quanjiPreferences,
            quanjiDetailInteraction: quanjiDetailInteraction,
            pornyStore: pornyStore,
            pornyPreferences: pornyPreferences,
            pornyDetailInteraction: pornyDetailInteraction,
            tangxinStore: tangxinStore,
            tangxinPreferences: tangxinPreferences,
            tangxinDetailInteraction: tangxinDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            favoritesModuleStore: favoritesModuleStore,
            favoritesPreferences: favoritesPreferences,
            favoritesDetailStore: favoritesDetailStore,
            favoritesDetailInteraction: favoritesDetailInteraction,
            filmstripVisibility: filmstripVisibility,
            importRootFolderAction: importRootFolderAction
        )
        let toolbarContext = WorkspaceToolbarContext(
            galleryStore: fourKHDGalleryStore,
            galleryPreferences: galleryPreferences,
            galleryDetailInteraction: galleryDetailInteraction,
            missKonStore: missKonStore,
            missKonPreferences: missKonPreferences,
            missKonDetailInteraction: missKonDetailInteraction,
            wallhavenStore: wallhavenStore,
            wallhavenPreferences: wallhavenPreferences,
            wallhavenDetailInteraction: wallhavenDetailInteraction,
            knitStore: knitStore,
            knitPreferences: knitPreferences,
            knitDetailInteraction: knitDetailInteraction,
            mrdsStore: mrdsStore,
            mrdsPreferences: mrdsPreferences,
            mrdsDetailInteraction: mrdsDetailInteraction,
            quanjiStore: quanjiStore,
            quanjiPreferences: quanjiPreferences,
            quanjiDetailInteraction: quanjiDetailInteraction,
            pornyStore: pornyStore,
            pornyPreferences: pornyPreferences,
            pornyDetailInteraction: pornyDetailInteraction,
            tangxinStore: tangxinStore,
            tangxinPreferences: tangxinPreferences,
            tangxinDetailInteraction: tangxinDetailInteraction,
            localLibraryStore: localLibraryStore,
            localPreferences: localPreferences,
            localDetailInteraction: localDetailInteraction,
            favoritesModuleStore: favoritesModuleStore,
            favoritesPreferences: favoritesPreferences,
            favoritesDetailStore: favoritesDetailStore,
            favoritesDetailInteraction: favoritesDetailInteraction,
            filmstripVisibility: filmstripVisibility,
            detailPaneController: detailPaneController,
            downloadStore: downloadStore,
            importRootFolderAction: importRootFolderAction
        )
        let routeController = WorkspaceRouteController(
            defaultRoute: moduleRegistry.defaultRoute(),
            normalizeRoute: { moduleRegistry.normalizedRoute($0) },
            applyRoute: { moduleRegistry.apply($0) }
        )

        return WorkspaceAppContext(
            moduleRegistry: moduleRegistry,
            routeController: routeController,
            detailPaneController: detailPaneController,
            galleryStore: fourKHDGalleryStore,
            missKonStore: missKonStore,
            wallhavenStore: wallhavenStore,
            knitStore: knitStore,
            mrdsStore: mrdsStore,
            quanjiStore: quanjiStore,
            pornyStore: pornyStore,
            tangxinStore: tangxinStore,
            localLibraryStore: localLibraryStore,
            favoritesStore: favoritesStore,
            favoritesModuleStore: favoritesModuleStore,
            favoritesDetailStore: favoritesDetailStore,
            favoritesPreferences: favoritesPreferences,
            toolbarContext: toolbarContext,
            downloadStore: downloadStore,
            importRootFolderAction: importRootFolderAction
        )
    }

    @MainActor
    static func configureFavoriteSourceAdapters(
        wallhavenPageResolver: @escaping (URL) async throws -> FavoriteResolvedImagePage,
        knitVideoActions: FavoriteVideoActions? = nil,
        mrdsVideoActions: FavoriteVideoActions? = nil,
        quanjiVideoActions: FavoriteVideoActions? = nil,
        pornyVideoActions: FavoriteVideoActions? = nil,
        tangxinVideoActions: FavoriteVideoActions? = nil
    ) {
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: { record in
                    guard let item = GalleryFavoritesBridge.galleryItems(from: [record]).first else { return nil }
                    return .paged(
                        pageURLs: item.pageURLs,
                        estimatedImageCount: item.imageCount,
                        pageImageCapacity: 20
                    )
                },
                resolvePage: { url in
                    let page = try await DetailImageResolver.resolvePageWithFallback(url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations
                    )
                },
                configureImageRequest: GalleryRequestFactory.configureImageRequest,
                detailMetadata: { record in
                    GalleryFavoritesBridge.galleryItems(from: [record]).first.map(makeGalleryFavoriteMetadata)
                }
            ),
            FavoriteSourceAdapter(
                source: .missKon,
                detailContent: { record in
                    guard let item = MissKonFavoritesBridge.missKonItems(from: [record]).first else { return nil }
                    return .paged(
                        pageURLs: item.pageURLs,
                        estimatedImageCount: item.imageCount,
                        pageImageCapacity: 12
                    )
                },
                resolvePage: { url in
                    let page = try await MissKonDetailResolver.resolve(pageURL: url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations,
                        externalAction: page.mediaFireURL.map {
                            FavoriteDetailExternalAction(title: "MediaFire 下载", url: $0)
                        }
                    )
                },
                configureImageRequest: MissKonRequestFactory.configureImageRequest,
                detailMetadata: { record in
                    MissKonFavoritesBridge.missKonItems(from: [record]).first.map(makeMissKonFavoriteMetadata)
                },
                cachedExternalAction: { pageURL in
                    MissKonDetailMetadataCache.shared.metadata(for: pageURL)?.mediaFireURL.map {
                        FavoriteDetailExternalAction(title: "MediaFire 下载", url: $0)
                    }
                }
            ),
            FavoriteSourceAdapter(
                source: .wallhaven,
                detailContent: { record in
                    guard let wallpaper = WallhavenFavoritesBridge.wallpapers(from: [record]).first else { return nil }
                    return .paged(
                        pageURLs: [wallpaper.sourcePageUrl],
                        estimatedImageCount: 1,
                        pageImageCapacity: 1
                    )
                },
                resolvePage: { url in
                    try await wallhavenPageResolver(url)
                },
                configureImageRequest: WallhavenRequestFactory.configureImageRequest,
                detailMetadata: { record in
                    WallhavenFavoritesBridge.wallpapers(from: [record]).first.map(makeWallhavenFavoriteMetadata)
                },
                navigationMode: .sourceRecords
            ),
            FavoriteSourceAdapter(
                source: .knit,
                detailContent: { record in
                    guard let item = KnitFavoritesBridge.item(from: record) else { return nil }
                    let count = min(max(record.pageCount, 1), KnitDetailResolver.maximumDetailPageCount)
                    let pageURLs = (1 ... count).compactMap { page -> URL? in
                        if page == 1 { return item.detailURL }
                        var components = URLComponents(url: item.detailURL, resolvingAgainstBaseURL: false)
                        components?.path = "/article/\(item.id)/page/\(page)/"
                        return components?.url
                    }
                    return .paged(
                        pageURLs: pageURLs,
                        estimatedImageCount: record.imageCount,
                        pageImageCapacity: 10
                    )
                },
                resolvePage: { url in
                    let page = try await KnitDetailResolver.resolve(pageURL: url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations,
                        metadata: page.metadata.map {
                            makeKnitFavoriteMetadata(
                                $0,
                                sourceURL: page.pageURLs.first ?? url
                            )
                        },
                        videoURL: page.videoURL
                    )
                },
                configureImageRequest: KnitRequestFactory.configureImageRequest,
                detailMetadata: { record in
                    KnitFavoritesBridge.item(from: record).map {
                        makeKnitFavoriteMetadata($0, record: record)
                    }
                },
                videoActions: knitVideoActions
            ),
            FavoriteSourceAdapter(
                source: .mrds,
                detailContent: { record in
                    guard let item = MrdsFavoritesBridge.item(from: record) else { return nil }
                    return .paged(
                        pageURLs: [item.detailURL],
                        estimatedImageCount: max(record.imageCount, 1),
                        pageImageCapacity: max(record.imageCount, 1)
                    )
                },
                resolvePage: { url in
                    let page = try await MrdsDetailResolver.resolve(pageURL: url)
                    return FavoriteResolvedImagePage(
                        imageURLs: page.imageURLs,
                        pageURLs: page.pageURLs,
                        recommendations: page.recommendations,
                        metadata: page.metadata.map {
                            makeMrdsFavoriteMetadata($0, sourceURL: page.pageURLs.first ?? url)
                        },
                        videoURL: page.videoURL
                    )
                },
                configureImageRequest: MrdsRequestFactory.configureImageRequest,
                detailMetadata: { record in
                    MrdsFavoritesBridge.item(from: record).map {
                        makeMrdsFavoriteMetadata($0, record: record)
                    }
                },
                videoActions: mrdsVideoActions
            ),
            makeVideoFavoriteAdapter(
                source: .quanji,
                itemFromRecord: QuanjiFavoritesBridge.item(from:),
                resolve: QuanjiDetailResolver.resolve,
                configureImageRequest: QuanjiRequestFactory.configureImageRequest,
                sourceTitle: "木瓜视频",
                videoActions: quanjiVideoActions
            ),
            makeVideoFavoriteAdapter(
                source: .porny,
                itemFromRecord: PornyFavoritesBridge.item(from:),
                resolve: PornyDetailResolver.resolve,
                configureImageRequest: PornyRequestFactory.configureImageRequest,
                sourceTitle: "91PORNY",
                videoActions: pornyVideoActions
            ),
            makeVideoFavoriteAdapter(
                source: .tangxin,
                itemFromRecord: TangxinFavoritesBridge.item(from:),
                resolve: TangxinDetailResolver.resolve,
                configureImageRequest: TangxinRequestFactory.configureImageRequest,
                sourceTitle: "糖心Vlog",
                videoActions: tangxinVideoActions
            ),
        ])
    }

    private static func makeVideoFavoriteAdapter(
        source: FavoriteSource,
        itemFromRecord: @escaping (FavoriteRecord) -> OnlineVideoItem?,
        resolve: @escaping (URL) async throws -> OnlineVideoResolvedDetail,
        configureImageRequest: @escaping (inout URLRequest) -> Void,
        sourceTitle: String,
        videoActions: FavoriteVideoActions?
    ) -> FavoriteSourceAdapter {
        FavoriteSourceAdapter(
            source: source,
            detailContent: { record in
                guard let item = itemFromRecord(record) else { return nil }
                return .paged(
                    pageURLs: [item.detailURL],
                    estimatedImageCount: 1,
                    pageImageCapacity: 1
                )
            },
            resolvePage: { url in
                let detail = try await resolve(url)
                return FavoriteResolvedImagePage(
                    imageURLs: [detail.coverURL].compactMap { $0 },
                    pageURLs: [url],
                    metadata: nil,
                    videoURL: detail.videoURL
                )
            },
            configureImageRequest: configureImageRequest,
            detailMetadata: { record in
                guard let item = itemFromRecord(record) else { return nil }
                return makeOnlineVideoFavoriteMetadata(item, record: record, sourceTitle: sourceTitle)
            },
            videoActions: videoActions,
            navigationMode: .sourceRecords
        )
    }

    private static func makeOnlineVideoFavoriteMetadata(
        _ item: OnlineVideoItem,
        record: FavoriteRecord,
        sourceTitle: String
    ) -> FavoriteDetailMetadata {
        FavoriteDetailMetadata(
            title: item.title,
            detailText: record.subtitle,
            sourceTitle: "来源: \(sourceTitle)",
            sourceURL: item.detailURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: [
                .init(label: "时长", value: item.durationText.isEmpty ? record.subtitle : item.durationText),
            ].filter { !$0.value.isEmpty }
        )
    }

    private static func makeWallhavenFavoriteMetadata(_ wallpaper: Wallpaper) -> FavoriteDetailMetadata {
        var facts: [FavoriteDetailFact] = []
        if wallpaper.resolutionText != "-" {
            facts.append(.init(label: "分辨率", value: wallpaper.resolutionText))
        }
        if wallpaper.formattedFileSize != "-" {
            facts.append(.init(label: "大小", value: wallpaper.formattedFileSize))
        }
        if let fileType = wallpaper.fileType?.replacingOccurrences(of: "image/", with: "").uppercased() {
            facts.append(.init(label: "格式", value: fileType))
        }
        if let category = wallpaper.category {
            facts.append(.init(label: "分类", value: WallhavenCategory(rawValue: category)?.title ?? category))
        }
        facts.append(.init(label: "内容分级", value: wallpaper.purity.title))
        if let uploader = wallpaper.uploader {
            facts.append(.init(label: "上传者", value: uploader))
        }
        if let createdAt = wallpaper.createdAt {
            facts.append(.init(label: "上传日期", value: createdAt.formatted(date: .abbreviated, time: .shortened)))
        }
        if let views = wallpaper.views {
            facts.append(.init(label: "浏览数", value: views.formatted()))
        }
        if let favorites = wallpaper.favorites {
            facts.append(.init(label: "站内收藏", value: favorites.formatted()))
        }
        if !wallpaper.tags.isEmpty {
            facts.append(.init(label: "标签", value: wallpaper.tags.joined(separator: ", ")))
        }
        return FavoriteDetailMetadata(
            title: wallpaper.displayName,
            detailText: wallpaper.detailInfoText,
            sourceTitle: "来源: Wallhaven",
            sourceURL: wallpaper.sourcePageUrl,
            secondaryTitle: wallpaper.uploader.map { "\($0) 的作品" },
            secondaryURL: wallpaper.uploaderProfileURL,
            supportsDesktopWallpaper: true,
            facts: facts
        )
    }

    private static func makeGalleryFavoriteMetadata(_ item: GalleryItem) -> FavoriteDetailMetadata {
        let kindTitle = switch item.kind {
        case .gallery: "图集"
        case .recommended: "推荐"
        case .advertisement: "广告"
        }
        return FavoriteDetailMetadata(
            title: item.title,
            detailText: item.subtitle,
            sourceTitle: "来源: 4KHD",
            sourceURL: item.detailURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: [
                .init(label: "类型", value: kindTitle),
                .init(label: "栏目", value: item.section.title),
                .init(label: "图片数", value: item.imageCount > 0 ? item.imageCount.formatted() : "未知"),
                .init(label: "页数", value: item.pageCount.formatted()),
            ]
        )
    }

    private static func makeMissKonFavoriteMetadata(_ item: MissKonItem) -> FavoriteDetailMetadata {
        var facts = [
            FavoriteDetailFact(label: "栏目", value: item.section.title),
            FavoriteDetailFact(label: "图片数", value: item.imageCount > 0 ? item.imageCount.formatted() : "未知"),
            FavoriteDetailFact(label: "页数", value: item.pageCount.formatted()),
        ]
        if !item.tags.isEmpty {
            facts.append(.init(label: "标签", value: item.tags.joined(separator: ", ")))
        }
        return FavoriteDetailMetadata(
            title: item.title,
            detailText: item.tags.joined(separator: " · "),
            sourceTitle: "来源: MissKon",
            sourceURL: item.detailURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: facts
        )
    }

    private static func makeKnitFavoriteMetadata(
        _ item: KnitGalleryItem,
        record: FavoriteRecord
    ) -> FavoriteDetailMetadata {
        let category = record.subtitle.components(separatedBy: " · ").first ?? item.category
        return FavoriteDetailMetadata(
            title: item.title,
            detailText: record.subtitle,
            sourceTitle: "来源: 爱妹子",
            sourceURL: item.detailURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: [
                .init(label: "分类", value: category),
                .init(label: "图片数", value: record.imageCount > 0 ? record.imageCount.formatted() : "未知"),
                .init(label: "页数", value: record.pageCount.formatted()),
            ]
        )
    }

    private static func makeKnitFavoriteMetadata(
        _ metadata: KnitDetailMetadata,
        sourceURL: URL
    ) -> FavoriteDetailMetadata {
        var facts = [
            FavoriteDetailFact(label: "实际图片", value: metadata.totalImages.formatted()),
            FavoriteDetailFact(label: "图集页数", value: metadata.totalPages.formatted()),
        ]
        if !metadata.tags.isEmpty {
            facts.append(.init(label: "标签", value: metadata.tags.joined(separator: ", ")))
        }
        if !metadata.description.isEmpty {
            facts.append(.init(label: "描述", value: metadata.description))
        }
        return FavoriteDetailMetadata(
            title: "",
            detailText: [metadata.description, metadata.tags.joined(separator: " · ")]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            sourceTitle: "来源: 爱妹子",
            sourceURL: sourceURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: facts
        )
    }

    private static func makeMrdsFavoriteMetadata(
        _ item: MrdsGalleryItem,
        record: FavoriteRecord
    ) -> FavoriteDetailMetadata {
        let category = record.subtitle.components(separatedBy: " · ").first ?? item.category
        return FavoriteDetailMetadata(
            title: item.title,
            detailText: record.subtitle,
            sourceTitle: "来源: 每日大赛",
            sourceURL: item.detailURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: [
                .init(label: "分类", value: category),
                .init(label: "图片数", value: record.imageCount > 0 ? record.imageCount.formatted() : "未知"),
            ]
        )
    }

    private static func makeMrdsFavoriteMetadata(
        _ metadata: MrdsDetailMetadata,
        sourceURL: URL
    ) -> FavoriteDetailMetadata {
        var facts = [
            FavoriteDetailFact(label: "实际图片", value: metadata.totalImages.formatted()),
        ]
        if !metadata.tags.isEmpty {
            facts.append(.init(label: "标签", value: metadata.tags.joined(separator: ", ")))
        }
        if !metadata.description.isEmpty {
            facts.append(.init(label: "描述", value: metadata.description))
        }
        return FavoriteDetailMetadata(
            title: "",
            detailText: [metadata.description, metadata.tags.joined(separator: " · ")]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            sourceTitle: "来源: 每日大赛",
            sourceURL: sourceURL,
            secondaryTitle: nil,
            secondaryURL: nil,
            supportsDesktopWallpaper: false,
            facts: facts
        )
    }

    @MainActor
    private static func makeModuleRegistry(
        fourKHDGalleryStore: FourKHDGalleryStore,
        galleryPreferences: GalleryContentPreferences,
        galleryDetailInteraction: GalleryDetailInteractionController,
        missKonStore: MissKonGalleryStore,
        missKonPreferences: MissKonContentPreferences,
        missKonDetailInteraction: MissKonDetailInteractionController,
        wallhavenStore: WallhavenGalleryStore,
        wallhavenPreferences: WallhavenContentPreferences,
        wallhavenDetailInteraction: WallhavenDetailInteractionController,
        knitStore: KnitGalleryStore,
        knitPreferences: KnitContentPreferences,
        knitDetailInteraction: KnitDetailInteractionController,
        knitVideoPlayer: KnitVideoPlayerWindowController,
        mrdsStore: MrdsGalleryStore,
        mrdsPreferences: MrdsContentPreferences,
        mrdsDetailInteraction: MrdsDetailInteractionController,
        quanjiStore: OnlineVideoGalleryStore,
        quanjiPreferences: OnlineVideoContentPreferences,
        quanjiDetailInteraction: OnlineVideoDetailInteractionController,
        pornyStore: OnlineVideoGalleryStore,
        pornyPreferences: OnlineVideoContentPreferences,
        pornyDetailInteraction: OnlineVideoDetailInteractionController,
        tangxinStore: OnlineVideoGalleryStore,
        tangxinPreferences: OnlineVideoContentPreferences,
        tangxinDetailInteraction: OnlineVideoDetailInteractionController,
        localLibraryStore: LocalLibraryStore,
        localPreferences: LocalLibraryContentPreferences,
        localDetailInteraction: LocalDetailInteractionController,
        favoritesModuleStore: FavoritesModuleStore,
        favoritesPreferences: FavoritesContentPreferences,
        favoritesDetailStore: FavoritesDetailStore,
        favoritesDetailInteraction: FavoritesDetailInteractionController,
        filmstripVisibility: FilmstripVisibilityController,
        importRootFolderAction: @escaping () -> Void
    ) -> WorkspaceModuleRegistry {
        return WorkspaceModuleRegistry(
            modules: [
                WorkspaceModuleDescriptor(
                    id: .localLibrary,
                    displayName: "LocalLibrary",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: true, showsImportFolder: true,
                        showsFavorite: false, showsOnlineSave: false, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .selection,
                        refreshRequiresSelection: true, detailActions: .localFile
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                    },
                    makeContentController: { context in
                        LocalImageContentViewController(
                            localLibrary: localLibraryStore,
                            preferences: localPreferences,
                            detailPane: context.detailPaneController,
                            importRootFolderAction: importRootFolderAction
                        )
                    },
                    makeDetailController: { context in
                        LocalImageDetailViewController(
                            localLibrary: localLibraryStore,
                            immersive: context.immersive,
                            detailInteraction: localDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        if localLibraryStore.isAllImagesFolderID(route.itemID) {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                        }
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            return WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id)
                        }
                        return WorkspaceRoute(moduleID: .localLibrary, itemID: LocalLibraryStore.allImagesFolderID)
                    },
                    applyRoute: { route in
                        if localLibraryStore.isAllImagesFolderID(route.itemID) {
                            localLibraryStore.selectAllImages()
                            return
                        }
                        if let folder = localLibraryStore.findFolder(id: route.itemID) {
                            localLibraryStore.selectFolder(folder)
                        }
                    },
                    bootstrap: {}
                ),
                WorkspaceModuleDescriptor(
                    id: .fourKHDGallery,
                    displayName: "4KHDGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .fourKHDGallery, itemID: GallerySection.latest.rawValue)
                    },
                    makeContentController: { context in
                        GalleryContentViewController(
                            library: fourKHDGalleryStore,
                            preferences: galleryPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        GalleryImageDetailViewController(
                            library: fourKHDGalleryStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: galleryDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = GallerySection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .fourKHDGallery, itemID: GallerySection.latest.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = GallerySection(rawValue: route.itemID) else { return }
                        if fourKHDGalleryStore.section != section {
                            fourKHDGalleryStore.section = section
                        }
                    },
                    bootstrap: {
                        fourKHDGalleryStore.bootstrapIfNeeded()
                    }
                ),
                WorkspaceModuleDescriptor(
                    id: .missKon,
                    displayName: "MissKon",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, filmstripAvailability: .resolvedImage,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .missKon, itemID: MissKonSection.latest.rawValue)
                    },
                    makeContentController: { context in
                        MissKonContentViewController(
                            library: missKonStore,
                            preferences: missKonPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        MissKonImageDetailViewController(
                            library: missKonStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: missKonDetailInteraction,
                            filmstripVisibility: filmstripVisibility
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = MissKonSection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .missKon, itemID: MissKonSection.latest.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .missKon, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = MissKonSection(rawValue: route.itemID) else { return }
                        if missKonStore.section != section {
                            missKonStore.section = section
                        }
                    },
                    bootstrap: {
                        missKonStore.bootstrapIfNeeded()
                    }
                ),
                WorkspaceModuleDescriptor(
                    id: .wallhaven,
                    displayName: "Wallhaven",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: false, showsWallhavenControls: true,
                        showsFavoritesFilter: false, filmstripAvailability: .none,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .wallhaven, itemID: WallhavenSection.browse.rawValue)
                    },
                    makeContentController: { context in
                        WallhavenContentViewController(
                            library: wallhavenStore,
                            preferences: wallhavenPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        WallhavenImageDetailViewController(
                            library: wallhavenStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: wallhavenDetailInteraction
                        )
                    },
                    normalizeRoute: { route in
                        guard let section = WallhavenSection(rawValue: route.itemID) else {
                            return WorkspaceRoute(moduleID: .wallhaven, itemID: WallhavenSection.browse.rawValue)
                        }
                        return WorkspaceRoute(moduleID: .wallhaven, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = WallhavenSection(rawValue: route.itemID) else { return }
                        if wallhavenStore.section != section {
                            wallhavenStore.setSection(section)
                        }
                    },
                    bootstrap: {
                        wallhavenStore.bootstrapIfNeeded()
                    }
                ),
                WorkspaceModuleDescriptor(
                    id: .favorites,
                    displayName: "Favorites",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: true, showsVideoSave: true,
                        filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .favorites, itemID: FavoriteSourceFilter.all.rawValue)
                    },
                    makeContentController: { context in
                        FavoritesContentViewController(
                            moduleStore: favoritesModuleStore,
                            preferences: favoritesPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        FavoritesImageDetailViewController(
                            moduleStore: favoritesModuleStore,
                            detailStore: favoritesDetailStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            detailInteraction: favoritesDetailInteraction,
                            filmstripVisibility: filmstripVisibility,
                            onOpenSecondaryMetadata: { record, metadata in
                                guard FavoriteSource.source(for: record) == .wallhaven,
                                      let profileURL = metadata.secondaryURL,
                                      let username = profileURL.pathComponents.last,
                                      !username.isEmpty else { return false }
                                context.appContext.routeController.select(
                                    WorkspaceRoute(
                                        moduleID: .wallhaven,
                                        itemID: WallhavenSection.browse.rawValue
                                    )
                                )
                                wallhavenStore.showUploaderWorks(username: username)
                                return true
                            },
                            onOpenRecommendation: { source, recommendation in
                                switch source {
                                case .gallery:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .fourKHDGallery,
                                            itemID: GallerySection.latest.rawValue
                                        )
                                    )
                                    fourKHDGalleryStore.openRecommendation(recommendation)
                                case .missKon:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .missKon,
                                            itemID: MissKonSection.latest.rawValue
                                        )
                                    )
                                    missKonStore.openRecommendation(recommendation)
                                case .wallhaven:
                                    break
                                case .knit:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .knitGallery,
                                            itemID: knitStore.filter.rawValue
                                        )
                                    )
                                    knitStore.openRecommendation(recommendation)
                                case .mrds:
                                    context.appContext.routeController.select(
                                        WorkspaceRoute(
                                            moduleID: .mrdsGallery,
                                            itemID: mrdsStore.filter.rawValue
                                        )
                                    )
                                    mrdsStore.openRecommendation(recommendation)
                                case .quanji, .porny, .tangxin:
                                    break
                                }
                            }
                        )
                    },
                    normalizeRoute: { route in
                        let filter = FavoriteSourceFilter(rawValue: route.itemID) ?? .all
                        return WorkspaceRoute(moduleID: .favorites, itemID: filter.rawValue)
                    },
                    applyRoute: { route in
                        guard let filter = FavoriteSourceFilter(rawValue: route.itemID) else { return }
                        if favoritesModuleStore.filter != filter {
                            favoritesModuleStore.setFilter(filter)
                        }
                    },
                    bootstrap: {}
                ),
                WorkspaceModuleDescriptor(
                    id: .knitGallery,
                    displayName: "KnitGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, showsKnitFilters: true, showsVideoSave: true,
                        filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .knitGallery, itemID: KnitBrowseFilter.all.rawValue)
                    },
                    makeContentController: { context in
                        KnitContentViewController(
                            store: knitStore,
                            preferences: knitPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        KnitImageDetailViewController(
                            store: knitStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            interaction: knitDetailInteraction,
                            filmstripVisibility: filmstripVisibility,
                            onPlayVideo: { item, url in
                                knitVideoPlayer.play(url: url, title: item.title) {
                                    knitDetailInteraction.saveVideo(item: item, sourceURL: url)
                                }
                            }
                        )
                    },
                    normalizeRoute: { route in
                        let filter = KnitBrowseFilter.filter(forRouteItemID: route.itemID) ?? .all
                        return WorkspaceRoute(moduleID: .knitGallery, itemID: filter.rawValue)
                    },
                    applyRoute: { route in
                        guard let filter = KnitBrowseFilter.filter(forRouteItemID: route.itemID) else { return }
                        if knitStore.filter != filter {
                            knitStore.setFilter(filter)
                        }
                    },
                    bootstrap: { knitStore.bootstrapIfNeeded() }
                ),
                WorkspaceModuleDescriptor(
                    id: .mrdsGallery,
                    displayName: "MrdsGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, showsKnitFilters: false, showsVideoSave: true,
                        filmstripAvailability: .detail,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .mrdsGallery, itemID: MrdsSection.latest.rawValue)
                    },
                    makeContentController: { context in
                        MrdsContentViewController(
                            store: mrdsStore,
                            preferences: mrdsPreferences,
                            detailPane: context.detailPaneController
                        )
                    },
                    makeDetailController: { context in
                        MrdsImageDetailViewController(
                            store: mrdsStore,
                            immersive: context.immersive,
                            detailPane: context.detailPaneController,
                            interaction: mrdsDetailInteraction,
                            filmstripVisibility: filmstripVisibility,
                            onPlayVideo: { item, url in
                                knitVideoPlayer.play(
                                    url: url,
                                    title: item.title,
                                    source: .mrds,
                                    userAgent: MrdsRequestFactory.userAgent
                                ) {
                                    mrdsDetailInteraction.saveVideo(item: item, sourceURL: url)
                                }
                            }
                        )
                    },
                    normalizeRoute: { route in
                        let section = MrdsSection(rawValue: route.itemID) ?? .latest
                        return WorkspaceRoute(moduleID: .mrdsGallery, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = MrdsSection(rawValue: route.itemID) else { return }
                        if mrdsStore.filter != section {
                            mrdsStore.setFilter(section)
                        }
                    },
                    bootstrap: { mrdsStore.bootstrapIfNeeded() }
                ),
                WorkspaceModuleDescriptor(
                    id: .quanjiGallery,
                    displayName: "QuanjiGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, showsKnitFilters: false, showsVideoSave: true,
                        showsDetailPane: false,
                        filmstripAvailability: .none,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .quanjiGallery, itemID: QuanjiSection.home.rawValue)
                    },
                    makeContentController: { _ in
                        OnlineVideoFeedViewController(
                            store: quanjiStore,
                            preferences: quanjiPreferences,
                            configureImageRequest: QuanjiRequestFactory.configureImageRequest,
                            onPlayVideo: { item, url in
                                knitVideoPlayer.play(
                                    url: url,
                                    title: item.title,
                                    source: .quanji,
                                    userAgent: QuanjiRequestFactory.userAgent
                                ) {
                                    quanjiDetailInteraction.saveVideo(item: item, sourceURL: url)
                                }
                            },
                            onSaveVideo: { item, url in
                                quanjiDetailInteraction.saveVideo(item: item, sourceURL: url)
                            },
                            onPreparePlay: { item in
                                knitVideoPlayer.beginPreparingPlayback(title: item.title, source: .quanji)
                            },
                            onPlayFailed: { message in
                                knitVideoPlayer.presentResolveFailure(message: message)
                            }
                        )
                    },
                    makeDetailController: { _ in
                        NSViewController()
                    },
                    normalizeRoute: { route in
                        let section = QuanjiSection(rawValue: route.itemID) ?? .home
                        return WorkspaceRoute(moduleID: .quanjiGallery, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = QuanjiSection(rawValue: route.itemID) else { return }
                        if quanjiStore.filter != section.rawValue {
                            quanjiStore.setFilter(section.rawValue)
                        }
                    },
                    bootstrap: { quanjiStore.bootstrapIfNeeded() }
                ),
                WorkspaceModuleDescriptor(
                    id: .pornyGallery,
                    displayName: "PornyGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, showsKnitFilters: false, showsVideoSave: true,
                        showsDetailPane: false,
                        filmstripAvailability: .none,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .pornyGallery, itemID: PornySection.latest.rawValue)
                    },
                    makeContentController: { _ in
                        OnlineVideoFeedViewController(
                            store: pornyStore,
                            preferences: pornyPreferences,
                            configureImageRequest: PornyRequestFactory.configureImageRequest,
                            onPlayVideo: { item, url in
                                knitVideoPlayer.play(
                                    url: url,
                                    title: item.title,
                                    source: .porny,
                                    userAgent: PornyRequestFactory.userAgent
                                ) {
                                    pornyDetailInteraction.saveVideo(item: item, sourceURL: url)
                                }
                            },
                            onSaveVideo: { item, url in
                                pornyDetailInteraction.saveVideo(item: item, sourceURL: url)
                            },
                            onPreparePlay: { item in
                                knitVideoPlayer.beginPreparingPlayback(title: item.title, source: .porny)
                            },
                            onPlayFailed: { message in
                                knitVideoPlayer.presentResolveFailure(message: message)
                            }
                        )
                    },
                    makeDetailController: { _ in
                        NSViewController()
                    },
                    normalizeRoute: { route in
                        let section = PornySection(rawValue: route.itemID) ?? .latest
                        return WorkspaceRoute(moduleID: .pornyGallery, itemID: section.rawValue)
                    },
                    applyRoute: { route in
                        guard let section = PornySection(rawValue: route.itemID) else { return }
                        if pornyStore.filter != section.rawValue {
                            pornyStore.setFilter(section.rawValue)
                        }
                    },
                    bootstrap: { pornyStore.bootstrapIfNeeded() }
                ),
                WorkspaceModuleDescriptor(
                    id: .tangxinGallery,
                    displayName: "TangxinGallery",
                    presentation: WorkspaceModulePresentationProfile(
                        showsGridColumns: true, showsLocalSort: false, showsImportFolder: false,
                        showsFavorite: true, showsOnlineSave: true, showsWallhavenControls: false,
                        showsFavoritesFilter: false, showsKnitFilters: false, showsVideoSave: true,
                        showsDetailPane: false,
                        filmstripAvailability: .none,
                        refreshRequiresSelection: false, detailActions: .none
                    ),
                    defaultRoute: {
                        WorkspaceRoute(moduleID: .tangxinGallery, itemID: TangxinSection.latest.rawValue)
                    },
                    makeContentController: { context in
                        OnlineVideoFeedViewController(
                            store: tangxinStore,
                            preferences: tangxinPreferences,
                            configureImageRequest: TangxinRequestFactory.configureImageRequest,
                            onPlayVideo: { item, url in
                                knitVideoPlayer.play(
                                    url: url,
                                    title: item.title,
                                    source: .tangxin,
                                    userAgent: TangxinRequestFactory.userAgent,
                                    referer: TangxinRequestFactory.htmlOrigin
                                ) {
                                    tangxinDetailInteraction.saveVideo(item: item, sourceURL: url)
                                }
                            },
                            onSaveVideo: { item, url in
                                tangxinDetailInteraction.saveVideo(item: item, sourceURL: url)
                            },
                            onPreparePlay: { item in
                                knitVideoPlayer.beginPreparingPlayback(title: item.title, source: .tangxin)
                            },
                            onPlayFailed: { message in
                                knitVideoPlayer.presentResolveFailure(message: message)
                            },
                            onOpenFilter: { filter in
                                context.appContext.routeController.select(
                                    WorkspaceRoute(moduleID: .tangxinGallery, itemID: filter)
                                )
                            }
                        )
                    },
                    makeDetailController: { _ in
                        NSViewController()
                    },
                    normalizeRoute: { route in
                        let parsed = TangxinRoute.parse(route.itemID) ?? .latest
                        return WorkspaceRoute(moduleID: .tangxinGallery, itemID: parsed.itemID)
                    },
                    applyRoute: { route in
                        guard let parsed = TangxinRoute.parse(route.itemID) else { return }
                        if tangxinStore.filter != parsed.itemID {
                            tangxinStore.setFilter(parsed.itemID)
                        }
                    },
                    bootstrap: { tangxinStore.bootstrapIfNeeded() }
                ),
            ]
        )
    }
}
