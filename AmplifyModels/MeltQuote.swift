// swiftlint:disable all
import Amplify
import Foundation

public struct MeltQuote: Model {
  public let id: String
  public var quoteId: String
  public var encryptedQuote: String
  public var state: MeltQuoteState?
  public var owner: String?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      quoteId: String,
      encryptedQuote: String,
      state: MeltQuoteState? = nil,
      owner: String? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.quoteId = quoteId
      self.encryptedQuote = encryptedQuote
      self.state = state
      self.owner = owner
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}