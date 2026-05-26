import Foundation
import CoreLocation

// MARK: - Sample Data Generator
struct SampleData {
    static let currentUserID = UUID()
    static let currentUser = UserProfile(
        id: currentUserID,
        name: "Tony Martinez",
        email: "tony@example.com",
        phone: "(555) 123-4567",
        location: "San Mateo, CA",
        joinDate: Calendar.current.date(byAdding: .month, value: -8, to: Date())!,
        activeListings: 3,
        totalSold: 12
    )

    static let sellerIDs = (0..<10).map { _ in UUID().uuidString }
    static let sellerNames = [
        "Sarah K.", "Mike R.", "Lisa T.", "James W.", "Amy C.",
        "David L.", "Rachel M.", "Chris P.", "Nicole B.", "Alex H."
    ]

    static let neighborhoods = [
        "Downtown San Mateo", "Hillsdale", "Hayward Park", "Beresford",
        "Fiesta Gardens", "Baywood", "San Mateo Park", "Aragon",
        "Sugarloaf", "Laurelwood", "Shoreview", "North Central",
        "East San Mateo", "Westborough", "Foster City", "Belmont"
    ]

    static let neighborhoodCoordinates: [String: CLLocationCoordinate2D] = [
        "Downtown San Mateo": CLLocationCoordinate2D(latitude: 37.5630, longitude: -122.3255),
        "Hillsdale": CLLocationCoordinate2D(latitude: 37.5435, longitude: -122.3340),
        "Hayward Park": CLLocationCoordinate2D(latitude: 37.5520, longitude: -122.3195),
        "Beresford": CLLocationCoordinate2D(latitude: 37.5490, longitude: -122.3280),
        "Fiesta Gardens": CLLocationCoordinate2D(latitude: 37.5460, longitude: -122.3110),
        "Baywood": CLLocationCoordinate2D(latitude: 37.5510, longitude: -122.3380),
        "San Mateo Park": CLLocationCoordinate2D(latitude: 37.5560, longitude: -122.3350),
        "Aragon": CLLocationCoordinate2D(latitude: 37.5450, longitude: -122.3400),
        "Sugarloaf": CLLocationCoordinate2D(latitude: 37.5350, longitude: -122.3450),
        "Laurelwood": CLLocationCoordinate2D(latitude: 37.5300, longitude: -122.3380),
        "Shoreview": CLLocationCoordinate2D(latitude: 37.5580, longitude: -122.3100),
        "North Central": CLLocationCoordinate2D(latitude: 37.5680, longitude: -122.3220),
        "East San Mateo": CLLocationCoordinate2D(latitude: 37.5550, longitude: -122.3050),
        "Westborough": CLLocationCoordinate2D(latitude: 37.5250, longitude: -122.3500),
        "Foster City": CLLocationCoordinate2D(latitude: 37.5585, longitude: -122.2711),
        "Belmont": CLLocationCoordinate2D(latitude: 37.5202, longitude: -122.2758),
    ]

    /// Default coordinate for San Mateo, CA
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.5540, longitude: -122.3130)

    static func generateListings() -> [Listing] {
        var listings: [Listing] = []

        // Electronics
        let electronics: [(String, String, Double, String)] = [
            ("MacBook Pro 14\" M3 - Like New", "2023 MacBook Pro with M3 chip, 16GB RAM, 512GB SSD. Barely used, still under AppleCare. Comes with original box and charger. No scratches or dents.", 1450, "Electronics"),
            ("iPhone 15 Pro Max 256GB", "Unlocked iPhone 15 Pro Max in Natural Titanium. Perfect condition, always had a case and screen protector. Includes original box and cable.", 850, "Electronics"),
            ("Sony WH-1000XM5 Headphones", "Best noise cancelling headphones. Black color, excellent condition. Includes carrying case and all cables.", 220, "Electronics"),
            ("iPad Air 5th Gen 64GB WiFi", "Space gray iPad Air M1 chip. Pristine screen, comes with Apple Pencil 2nd gen and magnetic case.", 380, "Electronics"),
            ("Samsung 55\" 4K Smart TV", "Samsung Crystal UHD 4K TV. Moving and can't take it. Works perfectly, wall mount included. Remote and original stand.", 275, "Electronics"),
            ("Nintendo Switch OLED Bundle", "White OLED Switch with 8 games including Zelda TOTK, Mario Kart 8, Smash Bros. Two pro controllers. All in great condition.", 320, "Electronics"),
            ("Canon EOS R6 Mark II Body", "Professional mirrorless camera body. Low shutter count (~5000). Includes extra battery, charger, and camera bag.", 1800, "Electronics"),
            ("AirPods Pro 2nd Generation", "Used for about 3 months. Excellent battery life, USB-C case. Includes all original ear tips and box.", 160, "Electronics"),
        ]

        for (i, item) in electronics.enumerated() {
            let sellerIdx = i % sellerIDs.count
            listings.append(Listing(
                id: UUID(),
                title: item.0,
                description: item.1,
                price: item.2,
                category: .forSale,
                subcategory: item.3,
                images: ["photo"],
                location: "San Mateo, CA",
                neighborhood: neighborhoods[i % neighborhoods.count],
                postedDate: Calendar.current.date(byAdding: .hour, value: -(i * 3 + 1), to: Date())!,
                sellerID: sellerIDs[sellerIdx],
                sellerName: sellerNames[sellerIdx],
                condition: [.likeNew, .good, .new][i % 3]
            ))
        }

        // Furniture
        let furniture: [(String, String, Double)] = [
            ("Mid-Century Modern Sofa", "Beautiful walnut frame sofa with teal cushions. Very comfortable, no stains or tears. Moving sale - must go this weekend!", 650),
            ("IKEA KALLAX Shelf Unit 4x4", "White KALLAX bookshelf in great condition. Already disassembled for easy transport. Hardware included.", 55),
            ("Solid Oak Dining Table + 6 Chairs", "Farmhouse style dining set. Table seats 6-8. Minor wear consistent with age. Very sturdy.", 400),
            ("Herman Miller Aeron Chair Size B", "Fully loaded Aeron chair. Adjustable arms, lumbar support, tilt. Some wear on mesh but fully functional.", 550),
            ("Queen Memory Foam Mattress", "Casper Original mattress, queen size. 2 years old, always used with protector. Very clean, no stains.", 200),
            ("Standing Desk - Electric Adjustable", "Uplift V2 standing desk with bamboo top. 60x30 inches. Programmable height presets. Like new.", 475),
        ]

        for (i, item) in furniture.enumerated() {
            let sellerIdx = (i + 3) % sellerIDs.count
            listings.append(Listing(
                id: UUID(),
                title: item.0,
                description: item.1,
                price: item.2,
                category: .forSale,
                subcategory: "Furniture",
                images: ["photo"],
                location: "San Mateo, CA",
                neighborhood: neighborhoods[(i + 4) % neighborhoods.count],
                postedDate: Calendar.current.date(byAdding: .hour, value: -(i * 5 + 2), to: Date())!,
                sellerID: sellerIDs[sellerIdx],
                sellerName: sellerNames[sellerIdx],
                condition: [.good, .likeNew, .fair][i % 3]
            ))
        }

        // Housing
        let housing: [(String, String, Double, String)] = [
            ("Sunny 1BR in Mission - Laundry In-Unit", "Beautiful 1 bedroom apartment on Valencia St. Hardwood floors, updated kitchen, in-unit washer/dryer. Steps from BART. No pets. Available May 1.", 2800, "Apartments"),
            ("Spacious 2BR/2BA Pacific Heights", "Gorgeous flat with bay windows and city views. Newly renovated kitchen and bathrooms. Parking spot included. Cat OK.", 4200, "Apartments"),
            ("Room in 3BR House - Sunset", "Private room in shared 3BR house. Shared bathroom, full kitchen access. Quiet neighborhood near Golden Gate Park. WiFi included.", 1400, "Rooms & Shares"),
            ("Charming Studio - North Beach", "Cozy studio apartment above cafe. Lots of character, exposed brick. Utilities included. Walk to everything!", 2100, "Apartments"),
            ("3BR Victorian House - Castro", "Stunning Victorian with original details. 3 bedrooms, 1.5 baths, backyard, garage. Washer/dryer. Small dog OK.", 5500, "Houses"),
        ]

        for (i, item) in housing.enumerated() {
            let sellerIdx = (i + 5) % sellerIDs.count
            listings.append(Listing(
                id: UUID(),
                title: item.0,
                description: item.1,
                price: item.2,
                category: .housing,
                subcategory: item.3,
                images: ["photo"],
                location: "San Mateo, CA",
                neighborhood: neighborhoods[(i + 2) % neighborhoods.count],
                postedDate: Calendar.current.date(byAdding: .hour, value: -(i * 8 + 3), to: Date())!,
                sellerID: sellerIDs[sellerIdx],
                sellerName: sellerNames[sellerIdx]
            ))
        }

        // Jobs
        let jobs: [(String, String, Double?, String)] = [
            ("Senior iOS Developer - Startup", "Fast-growing fintech startup looking for experienced iOS developer. Swift/SwiftUI required. Remote-friendly. Equity included.", 180000, "Software"),
            ("Barista - Specialty Coffee Shop", "Join our team! Part-time and full-time positions available. Experience preferred but will train the right person. Tips + free coffee.", 22, "Food & Bev"),
            ("Marketing Manager", "B2B SaaS company seeking marketing manager to lead campaigns and grow pipeline. 5+ years experience. Hybrid role.", 120000, "Marketing"),
            ("Dog Walker / Pet Sitter", "Looking for reliable pet care providers. Set your own schedule, $25-35/walk. Must love animals and be available weekdays.", nil, "Gigs"),
        ]

        for (i, item) in jobs.enumerated() {
            let sellerIdx = (i + 7) % sellerIDs.count
            listings.append(Listing(
                id: UUID(),
                title: item.0,
                description: item.1,
                price: item.2,
                category: item.2 != nil && item.2! > 1000 ? .jobs : .gigs,
                subcategory: item.3,
                images: ["photo"],
                location: "San Mateo, CA",
                neighborhood: neighborhoods[(i + 6) % neighborhoods.count],
                postedDate: Calendar.current.date(byAdding: .hour, value: -(i * 12 + 5), to: Date())!,
                sellerID: sellerIDs[sellerIdx],
                sellerName: sellerNames[sellerIdx]
            ))
        }

        // Services
        let services: [(String, String, Double?, String)] = [
            ("House Cleaning - Eco-Friendly Products", "Professional house cleaning service. Licensed and insured. We use only eco-friendly products. Weekly, biweekly, or one-time deep clean available.", 150, "Cleaning"),
            ("Guitar Lessons - All Levels", "Professional musician offering guitar lessons. 15 years teaching experience. Acoustic, electric, bass. Your place or mine. First lesson free!", 60, "Lessons & Tutoring"),
            ("Handyman Services - No Job Too Small", "Licensed handyman for all your home repair needs. Plumbing, electrical, drywall, painting, furniture assembly. Free estimates.", nil, "Household"),
        ]

        for (i, item) in services.enumerated() {
            let sellerIdx = (i + 2) % sellerIDs.count
            listings.append(Listing(
                id: UUID(),
                title: item.0,
                description: item.1,
                price: item.2,
                category: .services,
                subcategory: item.3,
                images: ["photo"],
                location: "San Mateo, CA",
                neighborhood: neighborhoods[(i + 8) % neighborhoods.count],
                postedDate: Calendar.current.date(byAdding: .hour, value: -(i * 6 + 4), to: Date())!,
                sellerID: sellerIDs[sellerIdx],
                sellerName: sellerNames[sellerIdx]
            ))
        }

        // Free stuff
        listings.append(Listing(
            id: UUID(),
            title: "FREE: Moving Boxes & Packing Paper",
            description: "About 20 moving boxes of various sizes plus packing paper and bubble wrap. All in good condition. Must pick up today or tomorrow. First come first served.",
            price: 0,
            category: .forSale,
            subcategory: "Free Stuff",
            images: ["photo"],
            location: "San Mateo, CA",
            neighborhood: "SoMa",
            postedDate: Calendar.current.date(byAdding: .minute, value: -45, to: Date())!,
            sellerID: sellerIDs[4],
            sellerName: sellerNames[4],
            condition: .good
        ))

        return listings.shuffled()
    }

    static func generateConversations(listings: [Listing]) -> [Conversation] {
        guard listings.count >= 3 else { return [] }
        let sampleBuyerID = "sample-buyer-\(UUID().uuidString.prefix(8))"

        return [
            Conversation(
                id: UUID(),
                listingID: listings[0].id,
                listingTitle: listings[0].title,
                listingImage: "photo",
                buyerID: sampleBuyerID,
                buyerName: "You",
                sellerID: listings[0].sellerID,
                sellerName: listings[0].sellerName,
                otherUserID: listings[0].sellerID,
                otherUserName: listings[0].sellerName,
                messages: [
                    Message(id: UUID(), text: "Hi! Is this still available?", timestamp: Calendar.current.date(byAdding: .hour, value: -2, to: Date())!, isFromCurrentUser: true, isRead: true),
                    Message(id: UUID(), text: "Yes it is! Would you like to come see it?", timestamp: Calendar.current.date(byAdding: .hour, value: -1, to: Date())!, isFromCurrentUser: false, isRead: true),
                    Message(id: UUID(), text: "Absolutely! Are you free this weekend?", timestamp: Calendar.current.date(byAdding: .minute, value: -45, to: Date())!, isFromCurrentUser: true, isRead: true),
                    Message(id: UUID(), text: "Saturday afternoon works for me. How about 2pm?", timestamp: Calendar.current.date(byAdding: .minute, value: -20, to: Date())!, isFromCurrentUser: false, isRead: false),
                ],
                lastMessageDate: Calendar.current.date(byAdding: .minute, value: -20, to: Date())!
            ),
            Conversation(
                id: UUID(),
                listingID: listings[1].id,
                listingTitle: listings[1].title,
                listingImage: "photo",
                buyerID: sampleBuyerID,
                buyerName: "You",
                sellerID: listings[1].sellerID,
                sellerName: listings[1].sellerName,
                otherUserID: listings[1].sellerID,
                otherUserName: listings[1].sellerName,
                messages: [
                    Message(id: UUID(), text: "Would you take $50 less?", timestamp: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, isFromCurrentUser: true, isRead: true),
                    Message(id: UUID(), text: "I can do $25 off, that's the best I can do.", timestamp: Calendar.current.date(byAdding: .hour, value: -20, to: Date())!, isFromCurrentUser: false, isRead: true),
                    Message(id: UUID(), text: "Deal! When can I pick it up?", timestamp: Calendar.current.date(byAdding: .hour, value: -18, to: Date())!, isFromCurrentUser: true, isRead: true),
                ],
                lastMessageDate: Calendar.current.date(byAdding: .hour, value: -18, to: Date())!
            ),
            Conversation(
                id: UUID(),
                listingID: listings[2].id,
                listingTitle: listings[2].title,
                listingImage: "photo",
                buyerID: sampleBuyerID,
                buyerName: "You",
                sellerID: listings[2].sellerID,
                sellerName: listings[2].sellerName,
                otherUserID: listings[2].sellerID,
                otherUserName: listings[2].sellerName,
                messages: [
                    Message(id: UUID(), text: "Does this come with the original accessories?", timestamp: Calendar.current.date(byAdding: .day, value: -3, to: Date())!, isFromCurrentUser: true, isRead: true),
                    Message(id: UUID(), text: "Yes, everything in the original box!", timestamp: Calendar.current.date(byAdding: .day, value: -3, to: Date())!, isFromCurrentUser: false, isRead: true),
                ],
                lastMessageDate: Calendar.current.date(byAdding: .day, value: -3, to: Date())!
            ),
        ]
    }
}
