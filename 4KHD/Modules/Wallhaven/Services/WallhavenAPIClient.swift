import Foundation

enum WallhavenAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case rateLimited
    case badStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Wallhaven 请求地址无效"
        case .unauthorized:
            "Wallhaven API Key 无效，或该内容需要登录权限"
        case .rateLimited:
            "Wallhaven 请求过快，请稍后再试"
        case .badStatus(let status):
            "Wallhaven 请求失败（HTTP \(status)）"
        case .decodingFailed:
            "Wallhaven 返回数据无法解析"
        }
    }
}

struct WallhavenAPIClient {
    private let baseURL = URL(string: "https://wallhaven.cc/api/v1")!
    private let decoder: JSONDecoder

    init() {
        decoder = JSONDecoder()
    }

    private static let maxRetries = 2
    private static let retryDelay: UInt64 = 2_000_000_000 // 2 seconds

    func search(parameters: WallhavenSearchParameters, apiKey: String?) async throws -> WallhavenPage {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "categories", value: parameters.category.apiValue),
            URLQueryItem(name: "purity", value: parameters.purity.apiValue),
            URLQueryItem(name: "sorting", value: parameters.sorting.rawValue),
            URLQueryItem(name: "order", value: parameters.order.rawValue),
            URLQueryItem(name: "page", value: "\(parameters.page)")
        ]
        if let query = parameters.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if parameters.sorting == .toplist {
            queryItems.append(URLQueryItem(name: "topRange", value: parameters.topRange.rawValue))
        }
        if let resolution = parameters.resolution.apiValue {
            queryItems.append(URLQueryItem(name: "resolutions", value: resolution))
        }
        if let ratio = parameters.ratio.apiValue {
            queryItems.append(URLQueryItem(name: "ratios", value: ratio))
        }
        if parameters.sorting == .random, let seed = parameters.seed {
            queryItems.append(URLQueryItem(name: "seed", value: seed))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw WallhavenAPIError.invalidURL }
        return try await requestPage(url: url, apiKey: apiKey)
    }

    func wallpaper(id: String, apiKey: String?) async throws -> Wallpaper {
        let url = baseURL.appendingPathComponent("w").appendingPathComponent(id)
        let response: DetailResponse = try await request(url: url, apiKey: apiKey)
        guard let wallpaper = response.data.wallpaper else {
            throw WallhavenAPIError.decodingFailed
        }
        return wallpaper
    }

    private func requestPage(url: URL, apiKey: String?) async throws -> WallhavenPage {
        let response: SearchResponse = try await request(url: url, apiKey: apiKey)
        return WallhavenPage(
            wallpapers: response.data.compactMap(\.wallpaper),
            currentPage: response.meta?.currentPage ?? 1,
            lastPage: response.meta?.lastPage ?? 1,
            total: response.meta?.total,
            seed: response.meta?.seed
        )
    }

    private func request<Response: Decodable>(url: URL, apiKey: String?) async throws -> Response {
        var lastError: Error?
        for attempt in 0..<Self.maxRetries {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: Self.retryDelay)
            }
            let urlRequest = try WallhavenRequestFactory.makeAPIRequest(url: url, apiKey: apiKey)
            let (data, response) = try await OnlineSourceSession.wallhavenAPI.data(for: urlRequest)
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200..<300:
                    break
                case 401:
                    throw WallhavenAPIError.unauthorized
                case 429:
                    lastError = WallhavenAPIError.rateLimited
                    continue
                default:
                    throw WallhavenAPIError.badStatus(httpResponse.statusCode)
                }
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw WallhavenAPIError.decodingFailed
            }
        }
        throw lastError ?? WallhavenAPIError.rateLimited
    }
}

private struct SearchResponse: Decodable {
    let data: [WallhavenWallpaperDTO]
    let meta: WallhavenMetaDTO?
}

private struct DetailResponse: Decodable {
    let data: WallhavenWallpaperDTO
}

private struct WallhavenMetaDTO: Decodable {
    let currentPage: Int?
    let lastPage: Int?
    let total: Int?
    let seed: String?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case total
        case seed
    }
}

private struct WallhavenWallpaperDTO: Decodable {
    let id: String?
    let url: String?
    let shortURL: String?
    let views: Int?
    let favorites: Int?
    let source: String?
    let purity: String?
    let category: String?
    let dimensionX: Int?
    let dimensionY: Int?
    let resolution: String?
    let fileSize: Int64?
    let fileType: String?
    let createdAt: String?
    let colors: [String]?
    let path: String?
    let thumbs: Thumbs?
    let tags: [Tag]?
    let uploader: Uploader?

    struct Uploader: Decodable {
        let username: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case shortURL = "short_url"
        case views
        case favorites
        case source
        case purity
        case category
        case dimensionX = "dimension_x"
        case dimensionY = "dimension_y"
        case resolution
        case fileSize = "file_size"
        case fileType = "file_type"
        case createdAt = "created_at"
        case colors
        case path
        case thumbs
        case tags
        case uploader
    }

    struct Thumbs: Decodable {
        let large: String?
        let original: String?
        let small: String?
    }

    struct Tag: Decodable {
        let name: String?
    }

    var wallpaper: Wallpaper? {
        guard let id,
              let sourcePageUrl = url.flatMap(URL.init(string:)),
              OnlineSourcePolicy.allows(sourcePageUrl, source: .wallhaven, resource: .html) else {
            return nil
        }
        // `source` is publisher-provided metadata and is never fetched automatically.
        let sourceURL = source.flatMap(URL.init(string:))
        let thumbnailURL = thumbs?.small.flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media) ? $0 : nil }
        let previewURL = (thumbs?.large.flatMap(URL.init(string:)) ?? thumbs?.original.flatMap(URL.init(string:)))
            .flatMap { OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media) ? $0 : nil }
        let fullImageURL = path.flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .wallhaven, resource: .media) ? $0 : nil }
        let width = dimensionX
        let height = dimensionY
        let resolutionText: String
        if let resolution, !resolution.isEmpty {
            resolutionText = resolution
        } else if let width, let height {
            resolutionText = "\(width)x\(height)"
        } else {
            resolutionText = "-"
        }
        return Wallpaper(
            id: id,
            displayName: "Wallhaven \(id)",
            source: .wallhaven,
            sourcePageUrl: sourcePageUrl,
            sourceUrl: sourceURL,
            thumbnailUrl: thumbnailURL,
            previewUrl: previewURL,
            fullImageUrl: fullImageURL,
            width: width,
            height: height,
            resolutionText: resolutionText,
            fileSize: fileSize,
            fileType: fileType,
            colors: colors ?? [],
            tags: tags?.compactMap(\.name) ?? [],
            createdAt: createdAt.flatMap(WallhavenDateParser.date(from:)),
            purity: WallhavenPurity.fromAPIValue(purity),
            category: category,
            views: views,
            favorites: favorites,
            uploader: uploader?.username
        )
    }
}

private enum WallhavenDateParser {
    nonisolated static func date(from text: String) -> Date? {
        formatter.date(from: text)
    }

    private nonisolated static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
