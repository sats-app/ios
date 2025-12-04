import Foundation

struct MintListItem: Identifiable, Codable {
    let id: Int
    let url: String
    let name: String?
    let state: String
    private let infoString: String?

    /// Memberwise initializer for creating instances (e.g., for previews)
    init(id: Int, url: String, name: String?, state: String, infoString: String? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.state = state
        self.infoString = infoString
    }

    /// Initialize from a custom mint URL and its fetched info
    init(url: String, info: MintInfoResponse) {
        self.id = url.hashValue
        self.url = url
        self.name = info.name
        self.state = "OK"
        // Encode the info as JSON string for infoString
        let mintInfo = MintInfo(name: info.name, description: info.description, iconUrl: info.iconUrl)
        if let data = try? JSONEncoder().encode(mintInfo),
           let jsonString = String(data: data, encoding: .utf8) {
            self.infoString = jsonString
        } else {
            self.infoString = nil
        }
    }

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
