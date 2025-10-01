// swiftlint:disable all
import Amplify
import Foundation

extension MintQuote {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case quoteId
    case encryptedQuote
    case state
    case owner
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let mintQuote = MintQuote.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read])
    ]
    
    model.listPluralName = "MintQuotes"
    model.syncPluralName = "MintQuotes"
    
    model.attributes(
      .index(fields: ["state", "createdAt"], name: "mintQuotesByStateAndCreatedAt"),
      .primaryKey(fields: [mintQuote.id])
    )
    
    model.fields(
      .field(mintQuote.id, is: .required, ofType: .string),
      .field(mintQuote.quoteId, is: .required, ofType: .string),
      .field(mintQuote.encryptedQuote, is: .required, ofType: .string),
      .field(mintQuote.state, is: .optional, ofType: .enum(type: MintQuoteState.self)),
      .field(mintQuote.owner, is: .optional, ofType: .string),
      .field(mintQuote.createdAt, is: .optional, ofType: .dateTime),
      .field(mintQuote.updatedAt, is: .optional, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<MintQuote> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension MintQuote: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == MintQuote {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var quoteId: FieldPath<String>   {
      string("quoteId") 
    }
  public var encryptedQuote: FieldPath<String>   {
      string("encryptedQuote") 
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