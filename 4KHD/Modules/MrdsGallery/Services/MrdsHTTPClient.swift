import Foundation

enum MrdsHTTPClientError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .badStatus(status): "每日大赛服务器返回状态码 \(status)"
        }
    }
}

enum MrdsHTTPClient {
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await OnlineSourceSession.mrdsHTML.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw MrdsHTTPClientError.badStatus(response.statusCode)
        }
        return (data, response)
    }
}
