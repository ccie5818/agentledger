// swiftlint:disable all
import Amplify
import Foundation

public struct Conversation: Model {
  public let id: String
  internal var _listing: LazyReference<Listing>
  public var listing: Listing?   {
      get async throws { 
        try await _listing.get()
      } 
    }
  public var listingTitle: String
  public var buyerID: String
  public var sellerID: String
  public var lastMessage: String?
  public var lastMessageAt: Temporal.DateTime?
  public var messages: List<Message>?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      listing: Listing? = nil,
      listingTitle: String,
      buyerID: String,
      sellerID: String,
      lastMessage: String? = nil,
      lastMessageAt: Temporal.DateTime? = nil,
      messages: List<Message>? = []) {
    self.init(id: id,
      listing: listing,
      listingTitle: listingTitle,
      buyerID: buyerID,
      sellerID: sellerID,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      messages: messages,
      createdAt: nil,
      updatedAt: nil)
  }
  internal init(id: String = UUID().uuidString,
      listing: Listing? = nil,
      listingTitle: String,
      buyerID: String,
      sellerID: String,
      lastMessage: String? = nil,
      lastMessageAt: Temporal.DateTime? = nil,
      messages: List<Message>? = [],
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self._listing = LazyReference(listing)
      self.listingTitle = listingTitle
      self.buyerID = buyerID
      self.sellerID = sellerID
      self.lastMessage = lastMessage
      self.lastMessageAt = lastMessageAt
      self.messages = messages
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
  public mutating func setListing(_ listing: Listing? = nil) {
    self._listing = LazyReference(listing)
  }
  public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(String.self, forKey: .id)
      _listing = try values.decodeIfPresent(LazyReference<Listing>.self, forKey: .listing) ?? LazyReference(identifiers: nil)
      listingTitle = try values.decode(String.self, forKey: .listingTitle)
      buyerID = try values.decode(String.self, forKey: .buyerID)
      sellerID = try values.decode(String.self, forKey: .sellerID)
      lastMessage = try? values.decode(String?.self, forKey: .lastMessage)
      lastMessageAt = try? values.decode(Temporal.DateTime?.self, forKey: .lastMessageAt)
      messages = try values.decodeIfPresent(List<Message>?.self, forKey: .messages) ?? .init()
      createdAt = try? values.decode(Temporal.DateTime?.self, forKey: .createdAt)
      updatedAt = try? values.decode(Temporal.DateTime?.self, forKey: .updatedAt)
  }
  public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encode(_listing, forKey: .listing)
      try container.encode(listingTitle, forKey: .listingTitle)
      try container.encode(buyerID, forKey: .buyerID)
      try container.encode(sellerID, forKey: .sellerID)
      try container.encode(lastMessage, forKey: .lastMessage)
      try container.encode(lastMessageAt, forKey: .lastMessageAt)
      try container.encode(messages, forKey: .messages)
      try container.encode(createdAt, forKey: .createdAt)
      try container.encode(updatedAt, forKey: .updatedAt)
  }
}