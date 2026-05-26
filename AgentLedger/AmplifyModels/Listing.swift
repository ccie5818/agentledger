// swiftlint:disable all
import Amplify
import Foundation

public struct Listing: Model {
  public let id: String
  public var title: String
  public var description: String
  public var price: Double?
  public var category: ListingCategory?
  public var subcategory: String
  public var imageKeys: [String?]?
  public var location: String
  public var neighborhood: String
  public var condition: ListingCondition?
  public var sellerID: String
  public var sellerName: String
  public var isActive: Bool?
  public var conversations: List<Conversation>?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      title: String,
      description: String,
      price: Double? = nil,
      category: ListingCategory? = nil,
      subcategory: String,
      imageKeys: [String?]? = nil,
      location: String,
      neighborhood: String,
      condition: ListingCondition? = nil,
      sellerID: String,
      sellerName: String,
      isActive: Bool? = nil,
      conversations: List<Conversation>? = []) {
    self.init(id: id,
      title: title,
      description: description,
      price: price,
      category: category,
      subcategory: subcategory,
      imageKeys: imageKeys,
      location: location,
      neighborhood: neighborhood,
      condition: condition,
      sellerID: sellerID,
      sellerName: sellerName,
      isActive: isActive,
      conversations: conversations,
      createdAt: nil,
      updatedAt: nil)
  }
  internal init(id: String = UUID().uuidString,
      title: String,
      description: String,
      price: Double? = nil,
      category: ListingCategory? = nil,
      subcategory: String,
      imageKeys: [String?]? = nil,
      location: String,
      neighborhood: String,
      condition: ListingCondition? = nil,
      sellerID: String,
      sellerName: String,
      isActive: Bool? = nil,
      conversations: List<Conversation>? = [],
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self.title = title
      self.description = description
      self.price = price
      self.category = category
      self.subcategory = subcategory
      self.imageKeys = imageKeys
      self.location = location
      self.neighborhood = neighborhood
      self.condition = condition
      self.sellerID = sellerID
      self.sellerName = sellerName
      self.isActive = isActive
      self.conversations = conversations
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
}