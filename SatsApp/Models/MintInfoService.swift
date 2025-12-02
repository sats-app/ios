import Foundation

/// Response from a Cashu mint's /v1/info endpoint (NUT-06)
struct MintInfoResponse: Codable {
    let name: String?
    let pubkey: String?
    let version: String?
    let description: String?
    let descriptionLong: String?
    let contact: [[String: String]]?
    let motd: String?
    let iconUrl: String?
    let tosUrl: String?
    let nuts: [String: NutInfo]?

    enum CodingKeys: String, CodingKey {
        case name, pubkey, version, description, contact, motd, nuts
        case descriptionLong = "description_long"
        case iconUrl = "icon_url"
        case tosUrl = "tos_url"
    }

    /// Formatted contact information for display
    var formattedContacts: [(method: String, info: String)] {
        guard let contacts = contact else { return [] }
        return contacts.compactMap { dict in
            guard let method = dict["method"], let info = dict["info"] else { return nil }
            return (method: method, info: info)
        }
    }

    /// Supported NUT numbers
    var supportedNuts: [Int] {
        guard let nuts = nuts else { return [] }
        return nuts.keys.compactMap { Int($0) }.sorted()
    }
}

/// Information about a specific NUT support level
struct NutInfo: Codable {
    let supported: Bool?
    let disabled: Bool?

    // NUT-specific fields can be added as needed
    init(from decoder: Decoder) throws {
        // Handle both simple boolean and complex object responses
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            supported = try container.decodeIfPresent(Bool.self, forKey: .supported)
            disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        } else {
            // Some nuts return just metadata without supported/disabled
            supported = nil
            disabled = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case supported, disabled
    }
}

enum MintInfoError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid mint URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse mint info: \(error.localizedDescription)"
        }
    }
}

class MintInfoService {
    static let shared = MintInfoService()

    private init() {}

    /// Fetches mint information from the mint's /v1/info endpoint
    func fetchMintInfo(mintUrl: String) async throws -> MintInfoResponse {
        // Normalize the URL and append /v1/info
        var baseUrl = mintUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseUrl.hasSuffix("/") {
            baseUrl = String(baseUrl.dropLast())
        }

        let infoUrlString = "\(baseUrl)/v1/info"
        guard let url = URL(string: infoUrlString) else {
            throw MintInfoError.invalidURL
        }

        AppLogger.network.debug("Fetching mint info from: \(infoUrlString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw MintInfoError.networkError(
                    NSError(domain: "MintInfoService", code: -1,
                           userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                )
            }

            let decoder = JSONDecoder()
            let mintInfo = try decoder.decode(MintInfoResponse.self, from: data)
            AppLogger.network.debug("Successfully fetched mint info for: \(mintInfo.name ?? "Unknown")")
            return mintInfo
        } catch let error as MintInfoError {
            throw error
        } catch let error as DecodingError {
            AppLogger.network.error("Decoding error: \(error)")
            throw MintInfoError.decodingError(error)
        } catch {
            AppLogger.network.error("Network error: \(error)")
            throw MintInfoError.networkError(error)
        }
    }
}
