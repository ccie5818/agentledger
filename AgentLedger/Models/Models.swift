import Foundation
import SwiftUI

// MARK: - Listing Model
struct Listing: Identifiable, Hashable {
    let id: UUID
    var title: String
    var description: String
    var price: Double?
    var category: ListingCategory
    var subcategory: String
    var images: [String] // image asset names or URLs
    var localImages: [UIImage] = [] // local photos not yet uploaded
    var coverImageIndex: Int = 0 // which photo to use as display thumbnail
    var location: String
    var neighborhood: String
    var postedDate: Date
    var sellerID: String
    var sellerName: String
    var condition: ItemCondition?
    var status: ListingStatus = .active
    var isFavorited: Bool = false

    static func == (lhs: Listing, rhs: Listing) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var formattedPrice: String {
        guard let price = price else { return "Free" }
        if price == 0 { return "Free" }
        return "$\(Int(price))"
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(postedDate)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if days > 0 { return "\(days)d ago" }
        if hours > 0 { return "\(hours)h ago" }
        if minutes > 0 { return "\(minutes)m ago" }
        return "Just now"
    }
}

// MARK: - Category
enum ListingCategory: String, CaseIterable, Identifiable {
    case forSale = "For Sale"
    case housing = "Housing"
    case jobs = "Jobs"
    case services = "Services"
    case community = "Community"
    case gigs = "Gigs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .forSale: return "tag.fill"
        case .housing: return "house.fill"
        case .jobs: return "briefcase.fill"
        case .services: return "wrench.and.screwdriver.fill"
        case .community: return "person.3.fill"
        case .gigs: return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .forSale: return .purple
        case .housing: return .blue
        case .jobs: return .green
        case .services: return .orange
        case .community: return .pink
        case .gigs: return .yellow
        }
    }

    var subcategories: [String] {
        switch self {
        case .forSale:
            return ["Electronics", "Furniture", "Cars & Trucks", "Motorcycles", "Clothing", "Appliances", "Phones", "Computers", "Sporting Goods", "Toys & Games", "Books", "Tools", "Jewelry", "Antiques", "Free Stuff"]
        case .housing:
            return ["Apartments", "Houses", "Rooms & Shares", "Sublets", "Vacation Rentals", "Parking & Storage", "Office & Commercial"]
        case .jobs:
            return ["Accounting", "Admin & Office", "Customer Service", "Education", "Engineering", "Food & Bev", "Healthcare", "Legal", "Marketing", "Retail", "Sales", "Software", "Tech Support", "Writing"]
        case .services:
            return ["Automotive", "Beauty", "Cleaning", "Computer", "Creative", "Financial", "Health", "Household", "Labor & Moving", "Legal", "Lessons & Tutoring", "Pet", "Real Estate"]
        case .community:
            return ["Activities", "Artists", "Childcare", "Events", "Groups", "Local News", "Lost & Found", "Musicians", "Pets", "Politics", "Rideshare", "Volunteers"]
        case .gigs:
            return ["Computer", "Creative", "Crew", "Domestic", "Event", "Labor", "Talent", "Writing"]
        }
    }
}

// MARK: - Listing Status
enum ListingStatus: String, CaseIterable, Identifiable, Codable {
    case active = "Active"
    case sold = "Sold"
    case withdrawn = "Withdrawn"

    var id: String { rawValue }
}

// MARK: - Item Condition
enum ItemCondition: String, CaseIterable, Identifiable {
    case new = "New"
    case likeNew = "Like New"
    case good = "Good"
    case fair = "Fair"
    case salvage = "Salvage"

    var id: String { rawValue }
}

// MARK: - Conversation Model
struct Conversation: Identifiable, Hashable, Codable {
    let id: UUID
    let listingID: UUID
    let listingTitle: String
    let listingImage: String
    let buyerID: String
    var buyerName: String
    let sellerID: String
    var sellerName: String
    let otherUserID: String
    var otherUserName: String
    var messages: [Message]
    var lastMessageDate: Date

    // Hash and equality by ID only — messages change frequently
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }

    var lastMessagePreview: String {
        messages.last?.text ?? ""
    }

    var unreadCount: Int {
        messages.filter { !$0.isRead && !$0.isFromCurrentUser }.count
    }

    /// Returns the recipientID for a message sent by the current user
    func recipientID(currentUserID: String) -> String {
        currentUserID == buyerID ? sellerID : buyerID
    }

    /// Returns the other user's profile name (buyer or seller)
    func otherProfileName(currentUserID: String) -> String {
        if currentUserID == buyerID {
            return sellerName.isEmpty ? "Seller" : sellerName
        } else {
            return buyerName.isEmpty ? "Buyer" : buyerName
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, listingID, listingTitle, listingImage, buyerID, buyerName, sellerID, sellerName, otherUserID, otherUserName, messages, lastMessageDate
    }
}

// MARK: - Message Model
struct Message: Identifiable, Hashable, Codable {
    var id: UUID
    let text: String
    let timestamp: Date
    let isFromCurrentUser: Bool
    var isRead: Bool

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    enum CodingKeys: String, CodingKey {
        case id, text, timestamp, isFromCurrentUser, isRead
    }
}

// MARK: - User Model
struct UserProfile: Identifiable {
    let id: UUID
    var name: String
    var email: String
    var phone: String
    var location: String
    var joinDate: Date
    var avatarInitials: String {
        let parts = name.split(separator: " ")
        let initials = parts.prefix(2).compactMap { $0.first }.map(String.init)
        return initials.joined()
    }
    var activeListings: Int
    var totalSold: Int
}

// MARK: - Search Filter
struct SearchFilter {
    var query: String = ""
    var categories: Set<ListingCategory> = []
    var subcategory: String?
    var minPrice: Double?
    var maxPrice: Double?
    var condition: ItemCondition?
    var location: String = ""
    var sortBy: SortOption = .newest
    var searchRadius: Double = 25
}

enum SortOption: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case priceLow = "Price: Low to High"
    case priceHigh = "Price: High to Low"
    case nearest = "Nearest"

    var id: String { rawValue }
}
