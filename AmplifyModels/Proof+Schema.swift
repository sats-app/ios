// swiftlint:disable all
import Amplify
import Foundation

extension Proof {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case proofId
    case encryptedProof
    case state
    case owner
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let proof = Proof.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read])
    ]
    
    model.listPluralName = "Proofs"
    model.syncPluralName = "Proofs"
    
    model.attributes(
      .index(fields: ["state", "createdAt"], name: "proofsByStateAndCreatedAt"),
      .primaryKey(fields: [proof.id])
    )
    
    model.fields(
      .field(proof.id, is: .required, ofType: .string),
      .field(proof.proofId, is: .required, ofType: .string),
      .field(proof.encryptedProof, is: .required, ofType: .string),
      .field(proof.state, is: .optional, ofType: .enum(type: ProofState.self)),
      .field(proof.owner, is: .optional, ofType: .string),
      .field(proof.createdAt, is: .optional, ofType: .dateTime),
      .field(proof.updatedAt, is: .optional, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<Proof> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension Proof: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == Proof {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var proofId: FieldPath<String>   {
      string("proofId") 
    }
  public var encryptedProof: FieldPath<String>   {
      string("encryptedProof") 
    }
  public var owner: FieldPath<String>   {
      string("owner") 
    }
  public var createdAt: FieldPath<Temporal.DateTime>   {
      datetime("createdAt") 
    }
  public var updatedAt: FieldPath<Temporal.DateTime>   {
      datetime("updatedAt") 
    }
}