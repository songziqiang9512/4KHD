import Foundation
import Nuke

enum AlbumDownloadEvent {
    case pageResolved(pageIndex: Int, pageCount: Int, imageCount: Int)
    case pageFailed(pageIndex: Int, pageCount: Int)
    case imageSucceeded(pageIndex: Int, fileURL: URL)
    case imageFailed(pageIndex: Int, imageURL: URL)
}

struct AlbumDownloadSummary {
    var completedCount = 0
    var failedCount = 0
    var failedPageCount = 0
    var cancelled = false
    var folderCreationError: String?
}

/// 拉取单张图片数据的函数形状;引擎内按页并发调用,失败返回 nil。
/// 默认实现走 RemoteImagePipeline.loadData(失败自动重试一次);测试注入假实现。
typealias AlbumImageDataFetcher = @Sendable (URL, ImageTaskRegistry) async -> Data?

/// 图集批量下载引擎:逐页串行解析、页内图片按 maxConcurrentImages 并发
/// 拉取、逐张原子写盘。纯逻辑,不持有 UI 状态。
enum AlbumDownloadOrchestrator {
    nonisolated static func run(
        source: AlbumDownloadSource,
        destinationFolder: URL,
        maxConcurrentImages: Int = 3,
        registry: ImageTaskRegistry,
        emit: @escaping @Sendable (AlbumDownloadEvent) -> Void,
        fetcher: AlbumImageDataFetcher? = nil
    ) async -> AlbumDownloadSummary {
        guard createDirectory(destinationFolder) else {
            return AlbumDownloadSummary(folderCreationError: "无法创建保存目录")
        }

        let resolvedFetcher = fetcher ?? makeDefaultFetcher(configureImageRequest: source.configureImageRequest)

        var worklist = source.initialPageURLs.isEmpty ? [source.detailURL] : source.initialPageURLs
        let allocator = AlbumFileNameAllocator(folder: destinationFolder)
        var summary = AlbumDownloadSummary()
        var pageIndex = 0
        // 首次解析成功后以其 pageURLs 为权威分页列表整体替换;替换后从头
        // 扫描,已解析过的页在循环开头跳过——入口页不是第 1 页时也不会
        // 漏页或重复解析。
        var didReplaceWorklist = false
        var restartScan = false
        var resolvedPageURLs = Set<String>()
        // 已下载/已排队的图片,跨页去重(分页边界常重复最后一张)。
        var handledImageURLs = Set<String>()

        while pageIndex < worklist.count {
            if Task.isCancelled {
                summary.cancelled = true
                break
            }

            let pageURL = worklist[pageIndex]
            if resolvedPageURLs.contains(pageURL.absoluteString) {
                pageIndex += 1
                continue
            }

            var page: AlbumResolvedPage?
            do {
                page = try await resolvePageWithRetry(source: source, pageURL: pageURL)
                try Task.checkCancellation()
            } catch is CancellationError {
                summary.cancelled = true
                break
            } catch {
                page = nil
            }

            guard let page else {
                summary.failedPageCount += 1
                emit(.pageFailed(pageIndex: pageIndex, pageCount: worklist.count))
                // 失败页按顺序推进;不消费 restartScan 的话,下一张成功页会
                // 把扫描拉回起点,失败页被重复解析。
                restartScan = false
                pageIndex += 1
                continue
            }

            resolvedPageURLs.insert(pageURL.absoluteString)
            if !didReplaceWorklist {
                worklist = page.pageURLs.isEmpty ? [page.pageURL] : page.pageURLs
                didReplaceWorklist = true
                restartScan = true
            }
            emit(.pageResolved(pageIndex: pageIndex, pageCount: worklist.count, imageCount: page.imageURLs.count))

            // 跨页重复的图片只下载一次。
            let pageImageURLs = page.imageURLs.filter { handledImageURLs.insert($0.absoluteString).inserted }

            let chunkSize = max(maxConcurrentImages, 1)
            var offset = 0
            while offset < pageImageURLs.count {
                if Task.isCancelled {
                    summary.cancelled = true
                    break
                }
                let chunk = Array(pageImageURLs[offset ..< min(offset + chunkSize, pageImageURLs.count)])
                offset += chunk.count

                await withTaskGroup(of: (imageURL: URL, data: Data?, extensionName: String?).self) { group in
                    for imageURL in chunk {
                        group.addTask {
                            // 失败自动重试一次(重试前检查取消)。
                            var data = await resolvedFetcher(imageURL, registry)
                            if data == nil, !Task.isCancelled {
                                data = await resolvedFetcher(imageURL, registry)
                            }
                            // WebP 转无损 PNG;转换失败退回原数据。
                            let converted = data.map { AlbumImageFormatConverter.convertingToPNGIfWebP($0) }
                            return (imageURL, converted?.data, converted?.extensionName)
                        }
                    }
                    for await (imageURL, data, extensionName) in group {
                        guard !Task.isCancelled else { continue }
                        if let data {
                            let fileURL = allocator.allocate(for: imageURL, preferredExtension: extensionName)
                            if writeImageData(data, to: fileURL) {
                                summary.completedCount += 1
                                emit(.imageSucceeded(pageIndex: pageIndex, fileURL: fileURL))
                            } else {
                                summary.failedCount += 1
                                emit(.imageFailed(pageIndex: pageIndex, imageURL: imageURL))
                            }
                        } else {
                            summary.failedCount += 1
                            emit(.imageFailed(pageIndex: pageIndex, imageURL: imageURL))
                        }
                    }
                }
            }

            // 替换清单后从头扫描(当前页在 resolvedPageURLs 中会被跳过);
            // 否则顺序推进。
            if restartScan {
                restartScan = false
                pageIndex = 0
            } else {
                pageIndex += 1
            }
        }

        if summary.cancelled {
            registry.cancelAll()
        }
        return summary
    }

    // MARK: - 页解析

    /// 解析单页,失败自动重试一次(重试前检查取消)。瞬时网络错误
    /// 不应让整页图片全部漏掉。
    private nonisolated static func resolvePageWithRetry(
        source: AlbumDownloadSource,
        pageURL: URL
    ) async throws -> AlbumResolvedPage {
        do {
            return try await source.resolvePage(pageURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return try await source.resolvePage(pageURL)
        }
    }

    // MARK: - 默认 fetcher

    /// 默认实现:包装 RemoteImagePipeline.loadData,continuation 桥接 +
    /// registry 登记,单次拉取。失败重试由引擎统一处理。
    private nonisolated static func makeDefaultFetcher(
        configureImageRequest: @escaping @Sendable (inout URLRequest) -> Void
    ) -> AlbumImageDataFetcher {
        { imageURL, registry in
            await loadImageDataOnce(
                for: imageURL,
                configureImageRequest: configureImageRequest,
                registry: registry
            )
        }
    }

    @MainActor
    private static func loadImageDataOnce(
        for imageURL: URL,
        configureImageRequest: @escaping @Sendable (inout URLRequest) -> Void,
        registry: ImageTaskRegistry
    ) async -> Data? {
        let request = RemoteImagePipeline.shared.request(
            for: imageURL,
            priority: .high,
            configureURLRequest: configureImageRequest
        )
        return await withCheckedContinuation { continuation in
            let task = RemoteImagePipeline.shared.loadData(with: request) { data in
                continuation.resume(returning: data)
            }
            registry.register(task)
        }
    }

    private nonisolated static func createDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func writeImageData(_ data: Data, to fileURL: URL) -> Bool {
        do {
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
