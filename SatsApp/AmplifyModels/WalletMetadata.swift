// swiftlint:disable all
import Amplify
import Foundation

public struct WalletMetadata: Model {
  public let id: String
  public var mintUrls: [String?]?
  public var defaultMintUrl: String?
  public var owner: String?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      mintUrls: [String?]? = nil,
      defaultMintUrl: String? = nil,
      owner: String? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.mintUrls = mintUrls
      self.defaultMintUrl = defaultMintUrl
      self.owner = owner
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}