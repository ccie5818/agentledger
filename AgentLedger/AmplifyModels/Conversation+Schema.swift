// swiftlint:disable all
import Amplify
import Foundation

extension Conversation {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case listing
    case listingTitle
    case buyerID
    case sellerID
    case lastMessage
    case lastMessageAt
    case messages
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let conversation = Conversation.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read]),
      rule(allow: .private, operations: [.read, .create])
    ]
    
    model.listPluralName = "Conversations"
    model.syncPluralName = "Conversations"
    
    model.attributes(
      .primaryKey(fields: [conversation.id])
    )
    
    model.fields(
      .field(conversation.id, is: .required, ofType: .string),
      .belongsTo(conversation.listing, is: .optional, ofType: Listing.self, targetNames: ["listingID"]),
      .field(conversation.listingTitle, is: .required, ofType: .string),
      .field(conversation.buyerID, is: .required, ofType: .string),
      .field(conversation.sellerID, is: .required, ofType: .string),
      .field(conversation.lastMessage, is: .optional, ofType: .string),
      .field(conversation.lastMessageAt, is: .optional, ofType: .dateTime),
      .hasMany(conversation.messages, is: .optional, ofType: Message.self, associatedFields: [Message.keys.conversation]),
      .field(conversation.createdAt, is: .optional, isReadOnly: true, ofType: .dateTime),
      .field(conversation.updatedAt, is: .optional, isReadOnly: true, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<Conversation> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension Conversation: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == Conversation {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var listing: ModelPath<Listing>   {
      Listing.Path(name: "listing", parent: self) 
    }
  public var listingTitle: FieldPath<String>   {
      string("listingTitle") 
    }
  public var buyerID: FieldPath<String>   {
      string("buyerID") 
    }
  public var sellerID: FieldPath<String>   {
      string("sellerID") 
    }
  public var lastMessage: FieldPath<String>   {
      string("lastMessage") 
    }
  public var lastMessageAt: FieldPath<Temporal.DateTime>   {
      datetime("lastMessageAt") 
    }
  public var messages: ModelPath<Message>   {
      Message.Path(name: "messages", isCollection: true, parent: self) 
    }
  public var createdAt: FieldPath<Temporal.DateTime>   {
      datetime("createdAt") 
    }
  public var updatedAt: FieldPath<Temporal.DateTime>   {
      datetime("updatedAt") 
    }
}