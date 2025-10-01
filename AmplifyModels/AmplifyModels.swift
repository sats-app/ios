// swiftlint:disable all
import Amplify
import Foundation

// Contains the set of classes that conforms to the `Model` protocol. 

final public class AmplifyModels: AmplifyModelRegistration {
  public let version: String = "db4c8425e7de9243ed13ee6680e71bf5"
  
  public func registerModels(registry: ModelRegistry.Type) {
    ModelRegistry.register(modelType: MintQuote.self)
    ModelRegistry.register(modelType: MeltQuote.self)
    ModelRegistry.register(modelType: Proof.self)
    ModelRegistry.register(modelType: Transaction.self)
    ModelRegistry.register(modelType: WalletMetadata.self)
  }
}