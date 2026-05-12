import Foundation

/// Reads the Northstar masterserver's public server list.
///
/// The endpoint is unauthenticated and returns a JSON array of server records.
public actor ServerBrowserClient {
    public static let shared = ServerBrowserClient()

    private let endpoint = URL(
        string: "https://northstar.tf/client/servers"
    )!

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.httpAdditionalHeaders = ["User-Agent": "Draconis-Launcher"]
        return URLSession(configuration: cfg)
    }()

    public enum BrowserError: Error, LocalizedError {
        case badResponse(Int)
        case decodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .badResponse(let c):     return "Masterserver returned HTTP \(c)."
            case .decodingFailed(let s):  return "Couldn't parse server list: \(s)"
            }
        }
    }

    public func servers() async throws -> [NorthstarServer] {
        let (data, response) = try await session.data(from: endpoint)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BrowserError.badResponse(
                (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        do {
            return try JSONDecoder().decode([NorthstarServer].self, from: data)
        } catch {
            throw BrowserError.decodingFailed(String(describing: error))
        }
    }
}
