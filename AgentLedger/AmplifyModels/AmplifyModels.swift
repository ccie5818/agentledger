// swiftlint:disable all
import Amplify
import Foundation

// Contains the set of classes that conforms to the `Model` protocol. 

final public class AmplifyModels: AmplifyModelRegistration {
  public let version: String = "7c92d05099a3faec21ad1ed9ba97972b"
  
  public func registerModels(registry: ModelRegistry.Type) {
    ModelRegistry.register(modelType: Listing.self)
    ModelRegistry.register(modelType: Conversation.self)
    ModelRegistry.register(modelType: Message.self)
    ModelRegistry.register(modelType: UserProfile.self)
  }
}