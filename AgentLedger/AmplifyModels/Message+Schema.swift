// swiftlint:disable all
import Amplify
import Foundation

extension Message {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case conversation
    case senderID
    case text
    case isRead
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let message = Message.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read]),
      rule(allow: .private, operations: [.read, .create])
    ]
    
    model.listPluralName = "Messages"
    model.syncPluralName = "Messages"
    
    model.attributes(
      .primaryKey(fields: [message.id])
    )
    
    model.fields(
      .field(message.id, is: .required, ofType: .string),
      .belongsTo(message.conversation, is: .optional, ofType: Conversation.self, targetNames: ["conversationID"]),
      .field(message.senderID, is: .required, ofType: .string),
      .field(message.text, is: .required, ofType: .string),
      .field(message.isRead, is: .optional, ofType: .bool),
      .field(message.createdAt, is: .optional, isReadOnly: true, ofType: .dateTime),
      .field(message.updatedAt, is: .optional, isReadOnly: true, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<Message> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension Message: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == Message {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var conversation: ModelPath<Conversation>   {
      Conversation.Path(name: "conversation", parent: self) 
    }
  public var senderID: FieldPath<String>   {
      string("senderID") 
    }
  public var text: FieldPath<String>   {
      string("text") 
    }
  public var isRead: FieldPath<Bool>   {
      bool("isRead") 
    }
  public var createdAt: FieldPath<Temporal.DateTime>   {
      datetime("createdAt") 
    }
  public var updatedAt: FieldPath<Temporal.DateTime>   {
      datetime("updatedAt") 
    }
}