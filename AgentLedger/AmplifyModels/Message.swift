// swiftlint:disable all
import Amplify
import Foundation

public struct Message: Model {
  public let id: String
  internal var _conversation: LazyReference<Conversation>
  public var conversation: Conversation?   {
      get async throws { 
        try await _conversation.get()
      } 
    }
  public var senderID: String
  public var text: String
  public var isRead: Bool?
  public var createdAt: Temporal.DateTime?
  public var updatedAt: Temporal.DateTime?
  
  public init(id: String = UUID().uuidString,
      conversation: Conversation? = nil,
      senderID: String,
      text: String,
      isRead: Bool? = nil) {
    self.init(id: id,
      conversation: conversation,
      senderID: senderID,
      text: text,
      isRead: isRead,
      createdAt: nil,
      updatedAt: nil)
  }
  internal init(id: String = UUID().uuidString,
      conversation: Conversation? = nil,
      senderID: String,
      text: String,
      isRead: Bool? = nil,
      createdAt: Temporal.DateTime? = nil,
      updatedAt: Temporal.DateTime? = nil) {
      self.id = id
      self._conversation = LazyReference(conversation)
      self.senderID = senderID
      self.text = text
      self.isRead = isRead
      self.createdAt = createdAt
      self.updatedAt = updatedAt
  }
  public mutating func setConversation(_ conversation: Conversation? = nil) {
    self._conversation = LazyReference(conversation)
  }
  public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      id = try values.decode(String.self, forKey: .id)
      _conversation = try values.decodeIfPresent(LazyReference<Conversation>.self, forKey: .conversation) ?? LazyReference(identifiers: nil)
      senderID = try values.decode(String.self, forKey: .senderID)
      text = try values.decode(String.self, forKey: .text)
      isRead = try? values.decode(Bool?.self, forKey: .isRead)
      createdAt = try? values.decode(Temporal.DateTime?.self, forKey: .createdAt)
      updatedAt = try? values.decode(Temporal.DateTime?.self, forKey: .updatedAt)
  }
  public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encode(_conversation, forKey: .conversation)
      try container.encode(senderID, forKey: .senderID)
      try container.encode(text, forKey: .text)
      try container.encode(isRead, forKey: .isRead)
      try container.encode(createdAt, forKey: .createdAt)
      try container.encode(updatedAt, forKey: .updatedAt)
  }
}