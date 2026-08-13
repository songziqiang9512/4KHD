import Foundation

/// 单页解析结果:页面 URL、页面内图片列表、权威分页列表。
struct AlbumResolvedPage {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
}

/// 一次图集批量下载的完整来源描述。
/// 引擎不依赖任何模块;Gallery/MissKon 各自提供工厂方法。
struct AlbumDownloadSource {
    let detailURL: URL
    let title: String
    let estimatedImageCount: Int
    /// 分页工作清单的初始值(item.pageURLs;收藏由 bridge 重建 1..N)。
    /// 首页解析成功后会以其 pageURLs 整体替换。
    let initialPageURLs: [URL]
    /// 逐页解析闭包。解析器默认 MainActor 隔离,闭包必须标 @MainActor;
    /// 引擎在 nonisolated 上下文 await 时自动切换。
    let resolvePage: @Sendable @MainActor (URL) async throws -> AlbumResolvedPage
    let configureImageRequest: @Sendable (inout URLRequest) -> Void
}
