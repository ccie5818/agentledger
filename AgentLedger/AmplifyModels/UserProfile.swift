// swiftlint:disable all
import Amplify
import Foundation

public struct UserProfile: Model {
  public let id: String
  public var name: String
  public var email: String
  public var phone: String?
  public var location: String?
  public var neighborhood: String?
  public var avatarKey: String?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      name: String,
      email: String,
      phone: String? = nil,
      location: String? = nil,
      neighborhood: String? = nil,
      avatarKey: String? = nil) {
    self.init(id: id,
      name: name,
      email: email,
      phone: phone,
      location: location,
      neighborhood: neighborhood,
      avatarKey: avatarKey,
      createdAt: nil,
      updatedAt: nil)
  }
  internal init(id: String = UUID().uuidString,
      name: String,
      email: String,
      phone: String? = nil,
      location: String? = nil,
      neighborhood: String? = nil,
      avatarKey: String? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.name = name
      self.email = email
      self.phone = phone
      self.location = location
      self.neighborhood = neighborhood
      self.avatarKey = avatarKey
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}