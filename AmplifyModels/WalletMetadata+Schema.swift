// swiftlint:disable all
import Amplify
import Foundation

extension WalletMetadata {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case mintUrls
    case defaultMintUrl
    case owner
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let walletMetadata = WalletMetadata.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read])
    ]
    
    model.listPluralName = "WalletMetadata"
    model.syncPluralName = "WalletMetadata"
    
    model.attributes(
      .primaryKey(fields: [walletMetadata.id])
    )
    
    model.fields(
      .field(walletMetadata.id, is: .required, ofType: .string),
      .field(walletMetadata.mintUrls, is: .optional, ofType: .embeddedCollection(of: String.self)),
      .field(walletMetadata.defaultMintUrl, is: .optional, ofType: .string),
      .field(walletMetadata.owner, is: .optional, ofType: .string),
      .field(walletMetadata.createdAt, is: .optional, ofType: .dateTime),
      .field(walletMetadata.updatedAt, is: .optional, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<WalletMetadata> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension WalletMetadata: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == WalletMetadata {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var mintUrls: FieldPath<String>   {
      string("mintUrls") 
    }
  public var defaultMintUrl: FieldPath<String>   {
      string("defaultMintUrl") 
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