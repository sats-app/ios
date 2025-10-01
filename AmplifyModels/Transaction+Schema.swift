// swiftlint:disable all
import Amplify
import Foundation

extension Transaction {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case transactionId
    case encryptedTransaction
    case owner
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let transaction = Transaction.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read])
    ]
    
    model.listPluralName = "Transactions"
    model.syncPluralName = "Transactions"
    
    model.attributes(
      .primaryKey(fields: [transaction.id])
    )
    
    model.fields(
      .field(transaction.id, is: .required, ofType: .string),
      .field(transaction.transactionId, is: .required, ofType: .string),
      .field(transaction.encryptedTransaction, is: .required, ofType: .string),
      .field(transaction.owner, is: .optional, ofType: .string),
      .field(transaction.createdAt, is: .optional, ofType: .dateTime),
      .field(transaction.updatedAt, is: .optional, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<Transaction> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension Transaction: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == Transaction {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var transactionId: FieldPath<String>   {
      string("transactionId") 
    }
  public var encryptedTransaction: FieldPath<String>   {
      string("encryptedTransaction") 
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