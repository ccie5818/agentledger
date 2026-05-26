// swiftlint:disable all
import Amplify
import Foundation

extension Listing {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case title
    case description
    case price
    case category
    case subcategory
    case imageKeys
    case location
    case neighborhood
    case condition
    case sellerID
    case sellerName
    case isActive
    case conversations
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let listing = Listing.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read]),
      rule(allow: .private, operations: [.read]),
      rule(allow: .public, provider: .iam, operations: [.read])
    ]
    
    model.listPluralName = "Listings"
    model.syncPluralName = "Listings"
    
    model.attributes(
      .primaryKey(fields: [listing.id])
    )
    
    model.fields(
      .field(listing.id, is: .required, ofType: .string),
      .field(listing.title, is: .required, ofType: .string),
      .field(listing.description, is: .required, ofType: .string),
      .field(listing.price, is: .optional, ofType: .double),
      .field(listing.category, is: .optional, ofType: .enum(type: ListingCategory.self)),
      .field(listing.subcategory, is: .required, ofType: .string),
      .field(listing.imageKeys, is: .optional, ofType: .embeddedCollection(of: String.self)),
      .field(listing.location, is: .required, ofType: .string),
      .field(listing.neighborhood, is: .required, ofType: .string),
      .field(listing.condition, is: .optional, ofType: .enum(type: ListingCondition.self)),
      .field(listing.sellerID, is: .required, ofType: .string),
      .field(listing.sellerName, is: .required, ofType: .string),
      .field(listing.isActive, is: .optional, ofType: .bool),
      .hasMany(listing.conversations, is: .optional, ofType: Conversation.self, associatedFields: [Conversation.keys.listing]),
      .field(listing.createdAt, is: .optional, isReadOnly: true, ofType: .dateTime),
      .field(listing.updatedAt, is: .optional, isReadOnly: true, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<Listing> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension Listing: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == Listing {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var title: FieldPath<String>   {
      string("title") 
    }
  public var description: FieldPath<String>   {
      string("description") 
    }
  public var price: FieldPath<Double>   {
      double("price") 
    }
  public var subcategory: FieldPath<String>   {
      string("subcategory") 
    }
  public var imageKeys: FieldPath<String>   {
      string("imageKeys") 
    }
  public var location: FieldPath<String>   {
      string("location") 
    }
  public var neighborhood: FieldPath<String>   {
      string("neighborhood") 
    }
  public var sellerID: FieldPath<String>   {
      string("sellerID") 
    }
  public var sellerName: FieldPath<String>   {
      string("sellerName") 
    }
  public var isActive: FieldPath<Bool>   {
      bool("isActive") 
    }
  public var conversations: ModelPath<Conversation>   {
      Conversation.Path(name: "conversations", isCollection: true, parent: self) 
    }
  public var createdAt: FieldPath<Temporal.DateTime>   {
      datetime("createdAt") 
    }
  public var updatedAt: FieldPath<Temporal.DateTime>   {
      datetime("updatedAt") 
    }
}