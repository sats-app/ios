import Foundation

struct MintListItem: Identifiable, Codable {
    let id: Int
    let url: String
    let name: String?
    let state: String
    private let infoString: String?

    struct MintInfo: Codable {
        let name: String?
        let description: String?
        let iconUrl: String?

        enum CodingKeys: String, CodingKey {
            case name, description
            case iconUrl = "icon_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, url, name, state
        case infoString = "info"
    }

    private var parsedInfo: MintInfo? {
        guard let infoString = infoString,
              let data = infoString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MintInfo.self, from: data)
    }

    var displayName: String {
        parsedInfo?.name ?? name ?? URL(string: url)?.host ?? "Unknown Mint"
    }

    var displayDescription: String? {
        parsedInfo?.description
    }

    var iconURL: URL? {
        guard let urlString = parsedInfo?.iconUrl else { return nil }
        return URL(string: urlString)
    }
}

class MintDirectoryService {
    static let shared = MintDirectoryService()
    private let apiURL = "https://api.audit.8333.space/mints/?skip=0&limit=100"

    private init() {}

    func fetchMints() async throws -> [MintListItem] {
        guard let url = URL(string: apiURL) else {
            throw MintDirectoryError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MintDirectoryError.networkError
        }

        let mints = try JSONDecoder().decode([MintListItem].self, from: data)

        // Filter only, preserve API order
        let filtered = mints
            .filter { $0.state == "OK" }
            .filter { !$0.url.contains(".onion") }

        return filtered
    }
}

enum MintDirectoryError: LocalizedError {
    case invalidURL
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError:
            return "Failed to fetch mint directory"
        case .decodingError:
            return "Failed to parse mint data"
        }
    }
}
