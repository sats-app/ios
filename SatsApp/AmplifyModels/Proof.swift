// swiftlint:disable all
import Amplify
import Foundation

public struct Proof: Model {
  public let id: String
  public var proofId: String
  public var encryptedProof: String
  public var state: ProofState?
  public var owner: String?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      proofId: String,
      encryptedProof: String,
      state: ProofState? = nil,
      owner: String? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.proofId = proofId
      self.encryptedProof = encryptedProof
      self.state = state
      self.owner = owner
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}