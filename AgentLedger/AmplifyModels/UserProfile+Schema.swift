// swiftlint:disable all
import Amplify
import Foundation

extension UserProfile {
  // MARK: - CodingKeys 
   public enum CodingKeys: String, ModelKey {
    case id
    case name
    case email
    case phone
    case location
    case neighborhood
    case avatarKey
    case createdAt
    case updatedAt
  }
  
  public static let keys = CodingKeys.self
  //  MARK: - ModelSchema 
  
  public static let schema = defineSchema { model in
    let userProfile = UserProfile.keys
    
    model.authRules = [
      rule(allow: .owner, ownerField: "owner", identityClaim: "cognito:username", provider: .userPools, operations: [.create, .update, .delete, .read]),
      rule(allow: .private, operations: [.read])
    ]
    
    model.listPluralName = "UserProfiles"
    model.syncPluralName = "UserProfiles"
    
    model.attributes(
      .primaryKey(fields: [userProfile.id])
    )
    
    model.fields(
      .field(userProfile.id, is: .required, ofType: .string),
      .field(userProfile.name, is: .required, ofType: .string),
      .field(userProfile.email, is: .required, ofType: .string),
      .field(userProfile.phone, is: .optional, ofType: .string),
      .field(userProfile.location, is: .optional, ofType: .string),
      .field(userProfile.neighborhood, is: .optional, ofType: .string),
      .field(userProfile.avatarKey, is: .optional, ofType: .string),
      .field(userProfile.createdAt, is: .optional, isReadOnly: true, ofType: .dateTime),
      .field(userProfile.updatedAt, is: .optional, isReadOnly: true, ofType: .dateTime)
    )
    }
    public class Path: ModelPath<UserProfile> { }
    
    public static var rootPath: PropertyContainerPath? { Path() }
}

extension UserProfile: ModelIdentifiable {
  public typealias IdentifierFormat = ModelIdentifierFormat.Default
  public typealias IdentifierProtocol = DefaultModelIdentifier<Self>
}
extension ModelPath where ModelType == UserProfile {
  public var id: FieldPath<String>   {
      string("id") 
    }
  public var name: FieldPath<String>   {
      string("name") 
    }
  public var email: FieldPath<String>   {
      string("email") 
    }
  public var phone: FieldPath<String>   {
      string("phone") 
    }
  public var location: FieldPath<String>   {
      string("location") 
    }
  public var neighborhood: FieldPath<String>   {
      string("neighborhood") 
    }
  public var avatarKey: FieldPath<String>   {
      string("avatarKey") 
    }
  public var createdAt: FieldPath<Temporal.DateTime>   {
      datetime("createdAt") 
    }
  public var updatedAt: FieldPath<Temporal.DateTime>   {
      datetime("updatedAt") 
    }
}