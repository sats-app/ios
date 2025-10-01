// swiftlint:disable all
import Amplify
import Foundation

public struct Transaction: Model {
  public let id: String
  public var transactionId: String
  public var encryptedTransaction: String
  public var owner: String?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      transactionId: String,
      encryptedTransaction: String,
      owner: String? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.transactionId = transactionId
      self.encryptedTransaction = encryptedTransaction
      self.owner = owner
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}