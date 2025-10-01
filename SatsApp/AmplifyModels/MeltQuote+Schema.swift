// swiftlint:disable all
import Amplify
import Foundation

extension MeltQuote {
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
    let meltQuote = MeltQuote.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read])
    ]
    
    model.listPluralName = "MeltQuotes"
    model.syncPluralName = "MeltQuotes"
    
    model.attributes(
      .index(fields: ["state", "createdAt"], name: "meltQuotesByStateAndCreatedAt"),
      .primaryKey(fields: [meltQuote.id])
    )
    
    model.fields(
      .field(meltQuote.id, is: .required, ofType: .string),
      .field(meltQuote.quoteId, is: .required, ofType: .string),
      .field(meltQuote.encryptedQuote, is: .required, ofType: .string),
      .field(meltQuote.state, is: .optional, ofType: .enum(type: MeltQuoteState.self)),
      .field(meltQuote.owner, is: .optional, ofType: .string),
      .field(meltQuote.createdAt, is: .optional, ofType: .dateTime),
      .field(meltQuote.updatedAt, is: .optional, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<MeltQuote> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension MeltQuote: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == MeltQuote {
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