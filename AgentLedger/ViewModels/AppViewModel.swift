import Foundation
import SwiftUI
import Combine

class AppViewModel: ObservableObject {
    @Published var listings: [Listing] = []
    @Published var conversations: [Conversation] = []
    @Published var currentUser: UserProfile
    @Published var searchFilter = SearchFilter()
    @Published var favoriteIDs: Set<UUID> = []
    @Published var myListingIDs: Set<UUID> = []
    private var deletedListingIDs: Set<UUID> = []
    private var deletedConversationIDs: Set<UUID> = []
    private var deletedMessageIDs: Set<UUID> = []
    @Published var isBackendLoaded = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Local Persistence

    private static var conversationsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("saved_conversations.json")
    }

    private static var deletedConvoIDsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("deleted_conversation_ids.json")
    }

    private static var deletedMsgIDsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("deleted_message_ids.json")
    }

    private static var readConvoIDsFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("read_conversation_ids.json")
    }

    private func saveDeletedIDsToLocal() {
        if let data = try? JSONEncoder().encode(deletedConversationIDs.map { $0.uuidString }) {
            try? data.write(to: Self.deletedConvoIDsFileURL, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(deletedMessageIDs.map { $0.uuidString }) {
            try? data.write(to: Self.deletedMsgIDsFileURL, options: .atomic)
        }
    }

    private func saveReadIDsToLocal() {
        if let data = try? JSONEncoder().encode(readConversationIDs.map { $0.uuidString }) {
            try? data.write(to: Self.readConvoIDsFileURL, options: .atomic)
        }
    }

    private static func loadDeletedConvoIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: deletedConvoIDsFileURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func loadDeletedMsgIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: deletedMsgIDsFileURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private static func loadReadConvoIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: readConvoIDsFileURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private func saveConversationsToLocal() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: Self.conversationsFileURL, options: .atomic)
            print("[SAVE] Saved \(conversations.count) conversations to local storage")
        } catch {
            print("[SAVE] Failed to save conversations: \(error)")
        }
    }

    private static func loadConversationsFromLocal() -> [Conversation]? {
        guard FileManager.default.fileExists(atPath: conversationsFileURL.path) else {
            print("[LOAD] No local conversations file found")
            return nil
        }
        do {
            let data = try Data(contentsOf: conversationsFileURL)
            let convos = try JSONDecoder().decode([Conversation].self, from: data)
            print("[LOAD] Loaded \(convos.count) conversations from local storage")
            return convos
        } catch {
            print("Failed to load conversations: \(error)")
            return nil
        }
    }

    init() {
        self.currentUser = SampleData.currentUser
        self.listings = SampleData.generateListings()

        // Always start fresh — don't persist deleted IDs across launches.
        // Backend deletion is the source of truth. If backend delete succeeded,
        // the conversation won't come back. If it failed, user can delete again.
        try? FileManager.default.removeItem(at: Self.deletedConvoIDsFileURL)
        try? FileManager.default.removeItem(at: Self.deletedMsgIDsFileURL)
        self.deletedConversationIDs = []
        self.deletedMessageIDs = []
        self.readConversationIDs = Self.loadReadConvoIDs()
        print("[INIT] Clean start — no persisted deleted IDs")

        // Load saved conversations from disk (no sample data — real conversations come from the backend)
        if let saved = Self.loadConversationsFromLocal(), !saved.isEmpty {
            var filtered = saved.filter { !deletedConversationIDs.contains($0.id) }
            for i in filtered.indices {
                filtered[i].messages.removeAll { deletedMessageIDs.contains($0.id) }
            }
            self.conversations = filtered
        } else {
            self.conversations = []
        }

        // Mark a few as user's own listings
        let userListings = listings.prefix(3)
        for listing in userListings {
            myListingIDs.insert(listing.id)
        }

        // Auto-save conversations whenever they change (using Combine instead of didSet to avoid interfering with @Published)
        $conversations
            .dropFirst() // skip the initial value set above
            .removeDuplicates { $0.count == 0 && $1.count == 0 } // don't save when transitioning through empty
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveConversationsToLocal()
            }
            .store(in: &cancellables)

        // Also save immediately when app goes to background (debounce may not fire in time)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.saveConversationsToLocal()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.saveConversationsToLocal()
            }
            .store(in: &cancellables)
    }

    /// Sync profile with Amplify user data and load real data from backend
    func syncWithAmplify(_ amplifyService: AmplifyService) {
        if amplifyService.isSignedIn {
            if let name = amplifyService.currentUserName {
                currentUser.name = name
            }
            if let email = amplifyService.currentUserEmail {
                currentUser.email = email
            }
            // Reset sample data fields to real defaults
            currentUser.location = ""
            currentUser.phone = ""
            currentUser.joinDate = Date()
            currentUser.activeListings = 0
            currentUser.totalSold = 0

            // Clear demo content — real data comes from AWS
            listings = []
            myListingIDs = []
            favoriteIDs = []

            // Restore saved conversations from local cache
            if let saved = Self.loadConversationsFromLocal(), !saved.isEmpty {
                conversations = saved
                print("[SYNC] Restored \(saved.count) conversations from local storage")
            } else {
                conversations = []
                print("[SYNC] No local conversations found")
            }

            // Load real data from backend (will merge with local conversations)
            Task {
                await loadFromBackend(amplifyService)
            }
        }
    }

    /// Load listings, conversations, and favorites from AWS
    func loadFromBackend(_ amplifyService: AmplifyService) async {
        let fetchedListings = await amplifyService.fetchListings()
        let fetchedConversations = await amplifyService.fetchConversations()

        let profile = await amplifyService.fetchUserProfile()
        if profile == nil {
            _ = await amplifyService.createUserProfile()
        }
        let favIDs = Set((profile?.favoriteIDs ?? []).compactMap { UUID(uuidString: $0) })
        let uid = amplifyService.currentUserID

        // Clear any stale hiddenConversationIDs from backend profile (no longer used)
        let hiddenIDs = profile?.hiddenConversationIDs ?? []
        if !hiddenIDs.isEmpty {
            print("[INIT] Clearing \(hiddenIDs.count) stale hiddenConversationIDs from backend profile")
            await amplifyService.updateHiddenConversations([])
        }

        await applyBackendData(listings: fetchedListings, conversations: fetchedConversations, favoriteIDs: favIDs, userID: uid)

        await MainActor.run {
            isBackendLoaded = true
            print("[INIT] Backend data loaded: \(conversations.count) conversations, \(listings.count) listings")
        }

        // Resolve buyer names from backend profiles
        await resolveUnknownNames(amplifyService)

        // Push token saving is handled by RootView.setupPushOnce()
    }

    @MainActor
    private func applyBackendData(listings: [Listing], conversations: [Conversation], favoriteIDs: Set<UUID>, userID: String?) {
        // Preserve localImages from existing listings
        let existingLocalImages = Dictionary(uniqueKeysWithValues:
            self.listings.filter { !$0.localImages.isEmpty }.map { ($0.id, $0.localImages) }
        )
        var mergedListings = listings.filter { !deletedListingIDs.contains($0.id) }
        for i in mergedListings.indices {
            if let localImgs = existingLocalImages[mergedListings[i].id] {
                mergedListings[i].localImages = localImgs
            }
        }
        self.listings = mergedListings
        self.favoriteIDs = favoriteIDs

        // MERGE conversations: never wipe local data with empty backend response.
        // When backend returns data, merge messages from both sources.
        if !conversations.isEmpty {
            // Filter out deleted conversations and messages
            var backendConvos = conversations.filter { !deletedConversationIDs.contains($0.id) }
            for i in backendConvos.indices {
                backendConvos[i].messages.removeAll { deletedMessageIDs.contains($0.id) }
            }

            // Build lookup of existing local conversations for message merging
            let localByID = Dictionary(uniqueKeysWithValues: self.conversations.map { ($0.id, $0) })

            for i in backendConvos.indices {
                if let local = localByID[backendConvos[i].id] {
                    // Merge messages: keep local messages that backend doesn't have
                    let backendMsgIDs = Set(backendConvos[i].messages.map { $0.id })
                    let backendMsgKeys = Set(backendConvos[i].messages.map { "\($0.text)|\(Int($0.timestamp.timeIntervalSince1970 / 5))" })
                    let localOnlyMsgs = local.messages.filter { msg in
                        guard !backendMsgIDs.contains(msg.id) && !deletedMessageIDs.contains(msg.id) else { return false }
                        let key = "\(msg.text)|\(Int(msg.timestamp.timeIntervalSince1970 / 5))"
                        return !backendMsgKeys.contains(key)
                    }
                    if !localOnlyMsgs.isEmpty {
                        backendConvos[i].messages.append(contentsOf: localOnlyMsgs)
                        backendConvos[i].messages.sort { $0.timestamp < $1.timestamp }
                    }
                    // Preserve read status
                    if readConversationIDs.contains(backendConvos[i].id) {
                        for j in backendConvos[i].messages.indices {
                            backendConvos[i].messages[j].isRead = true
                        }
                    }
                    // Preserve resolved name
                    if local.otherUserName != local.otherUserID {
                        backendConvos[i].otherUserName = local.otherUserName
                    }
                }
            }

            // Keep local-only conversations not yet on backend
            let backendIDs = Set(backendConvos.map { $0.id })
            let localOnly = self.conversations.filter {
                !backendIDs.contains($0.id) && !deletedConversationIDs.contains($0.id)
            }
            self.conversations = backendConvos + localOnly
            print("applyBackendData: \(backendConvos.count) merged + \(localOnly.count) local-only")
        } else {
            print("applyBackendData: backend returned 0 conversations, keeping \(self.conversations.count) local")
        }

        if let userID = userID {
            for listing in mergedListings {
                if listing.sellerID == userID {
                    myListingIDs.insert(listing.id)
                }
            }
            currentUser.activeListings = myListingIDs.count
        }
    }

    /// Post a listing to AWS backend
    func postListingToBackend(_ amplifyService: AmplifyService, title: String, description: String, price: Double?, category: ListingCategory, subcategory: String, location: String, neighborhood: String, condition: ItemCondition?, imageKeys: [String], localImages: [UIImage] = [], coverImageIndex: Int = 0) async -> Bool {
        if let listing = await amplifyService.createListing(
            title: title,
            description: description,
            price: price,
            category: category,
            subcategory: subcategory,
            location: location,
            neighborhood: neighborhood,
            condition: condition,
            imageKeys: imageKeys
        ) {
            let finalListing: Listing = {
                var l = listing
                l.localImages = localImages
                l.coverImageIndex = coverImageIndex
                return l
            }()
            await MainActor.run {
                self.listings.insert(finalListing, at: 0)
                self.myListingIDs.insert(finalListing.id)
                self.currentUser.activeListings = self.myListingIDs.count
            }
            return true
        }
        return false
    }

    /// Start a conversation via AWS backend
    func startConversationOnBackend(_ amplifyService: AmplifyService, for listing: Listing, initialMessage: String) async -> UUID? {
        guard let userID = amplifyService.currentUserID else {
            print("[MSG] ERROR: no currentUserID, cannot start conversation")
            return nil
        }
        print("[MSG] startConversation: userID=\(userID), listing=\(listing.id), seller=\(listing.sellerID)")

        // Check if a conversation already exists locally for this buyer + listing
        let existingID: UUID? = await MainActor.run {
            let match = conversations.first(where: {
                $0.listingID == listing.id && $0.buyerID == userID
            })
            print("[MSG] Local check: \(conversations.count) conversations, match=\(match?.id.uuidString ?? "none")")
            return match?.id
        }

        if let convoID = existingID {
            print("[MSG] Reusing existing local convo \(convoID)")
            await sendMessageOnBackend(amplifyService, in: convoID, text: initialMessage)
            return convoID
        }

        // Also check backend in case local list is stale
        print("[MSG] No local match, checking backend...")
        let backendConvos = await amplifyService.fetchConversations()
        let backendMatch = backendConvos.first(where: {
            $0.listingID == listing.id && $0.buyerID == userID
        })
        if let existing = backendMatch {
            print("[MSG] Found existing convo \(existing.id) on backend")
            await MainActor.run {
                if !self.conversations.contains(where: { $0.id == existing.id }) {
                    self.conversations.insert(existing, at: 0)
                    print("[MSG] Added backend convo to local list, total: \(self.conversations.count)")
                }
            }
            await sendMessageOnBackend(amplifyService, in: existing.id, text: initialMessage)
            return existing.id
        }

        // No existing conversation — create a new one
        print("[MSG] No existing conversation found, creating new one...")
        if let conversation = await amplifyService.createConversation(listing: listing, initialMessage: initialMessage) {
            await MainActor.run {
                // Guard against duplicate insertion (refresh timer may have already added it)
                if !self.conversations.contains(where: { $0.id == conversation.id }) {
                    self.conversations.insert(conversation, at: 0)
                    print("[MSG] SUCCESS: Created convo \(conversation.id) with \(conversation.messages.count) msg(s), total convos: \(self.conversations.count)")
                } else {
                    // Conversation already exists (added by refresh) — just make sure the message is there
                    if let idx = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        let existingMsgIDs = Set(self.conversations[idx].messages.map { $0.id })
                        for msg in conversation.messages where !existingMsgIDs.contains(msg.id) {
                            self.conversations[idx].messages.append(msg)
                        }
                        self.conversations[idx].lastMessageDate = Date()
                        print("[MSG] Convo \(conversation.id) already existed (from refresh), merged messages")
                    }
                }
                self.saveConversationsToLocal()
            }
            return conversation.id
        }
        print("[MSG] ERROR: createConversation returned nil — check backend logs above")
        return nil
    }

    /// Send a message via AWS backend
    func sendMessageOnBackend(_ amplifyService: AmplifyService, in conversationID: UUID, text: String) async {
        // Find recipientID from the conversation
        let recipientID: String? = await MainActor.run {
            if let convo = conversations.first(where: { $0.id == conversationID }),
               let userID = amplifyService.currentUserID {
                let recipient = convo.recipientID(currentUserID: userID)
                print("sendMessage: convo=\(conversationID) to=\(recipient)")
                return recipient
            }
            print("sendMessage: WARNING — convo \(conversationID) not found locally!")
            return nil
        }

        // Update locally immediately (optimistic) with a temp ID
        let tempID = UUID()
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
                let message = Message(id: tempID, text: text, timestamp: Date(), isFromCurrentUser: true, isRead: true)
                conversations[index].messages.append(message)
                conversations[index].lastMessageDate = Date()
            }
        }

        // Send to backend (lowercase to match backend format)
        let backendID = await amplifyService.sendMessageToBackend(
            conversationID: conversationID.uuidString.lowercased(),
            text: text,
            recipientID: recipientID
        )

        // Replace temp ID with real backend ID so refreshConversations won't duplicate it
        if let backendIDStr = backendID, let realID = UUID(uuidString: backendIDStr) {
            await MainActor.run {
                if let convoIdx = conversations.firstIndex(where: { $0.id == conversationID }),
                   let msgIdx = conversations[convoIdx].messages.firstIndex(where: { $0.id == tempID }) {
                    conversations[convoIdx].messages[msgIdx].id = realID
                    print("[MSG] replaced temp \(tempID) with backend \(realID)")
                }
                saveConversationsToLocal()
            }
        } else {
            print("[MSG] WARNING: backend returned no message ID, temp message may duplicate on refresh")
        }
        print("[MSG] sendMessage: \(backendID != nil ? "OK" : "FAILED") for convo \(conversationID)")
    }

    // MARK: - Filtered Listings
    var filteredListings: [Listing] {
        // Hide withdrawn listings; hide sold listings only when a category filter is active
        var result = listings.filter { $0.status != .withdrawn }

        if !searchFilter.query.isEmpty {
            let q = searchFilter.query.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.description.lowercased().contains(q) ||
                $0.subcategory.lowercased().contains(q)
            }
        }

        if !searchFilter.categories.isEmpty {
            result = result.filter { listing in
                searchFilter.categories.contains(listing.category) && listing.status != .sold
            }
        }

        if let subcategory = searchFilter.subcategory {
            result = result.filter { $0.subcategory == subcategory }
        }

        if let minPrice = searchFilter.minPrice {
            result = result.filter { ($0.price ?? 0) >= minPrice }
        }

        if let maxPrice = searchFilter.maxPrice {
            result = result.filter { ($0.price ?? 0) <= maxPrice }
        }

        if let condition = searchFilter.condition {
            result = result.filter { $0.condition == condition }
        }

        // Sort
        switch searchFilter.sortBy {
        case .newest:
            result.sort { $0.postedDate > $1.postedDate }
        case .priceLow:
            result.sort { ($0.price ?? 0) < ($1.price ?? 0) }
        case .priceHigh:
            result.sort { ($0.price ?? 0) > ($1.price ?? 0) }
        case .nearest:
            result.sort { $0.postedDate > $1.postedDate } // Placeholder
        }

        return result
    }

    var favoriteListings: [Listing] {
        listings.filter { favoriteIDs.contains($0.id) }
    }

    var myListings: [Listing] {
        listings.filter { myListingIDs.contains($0.id) }
    }

    var unreadMessageCount: Int {
        conversations.reduce(0) { total, convo in
            // If we've already read this conversation, count is 0
            if readConversationIDs.contains(convo.id) { return total }
            return total + convo.unreadCount
        }
    }

    // MARK: - Actions
    func toggleFavorite(_ listing: Listing, amplifyService: AmplifyService? = nil) {
        if favoriteIDs.contains(listing.id) {
            favoriteIDs.remove(listing.id)
        } else {
            favoriteIDs.insert(listing.id)
        }

        // Persist to backend
        if let service = amplifyService, service.isConfigured {
            let ids = favoriteIDs.map { $0.uuidString }
            Task {
                await service.updateFavorites(ids)
            }
        }
    }

    func isFavorited(_ listing: Listing) -> Bool {
        favoriteIDs.contains(listing.id)
    }

    func addListing(_ listing: Listing) {
        var newListing = listing
        newListing.postedDate = Date()
        listings.insert(newListing, at: 0)
        myListingIDs.insert(newListing.id)
    }

    func markAsSold(_ id: UUID, amplifyService: AmplifyService? = nil) {
        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].status = .sold
        }

        if let service = amplifyService, service.isConfigured {
            Task {
                _ = await service.updateListingStatus(id: id.uuidString.lowercased(), status: .sold)
            }
        }
    }

    func withdrawListing(_ id: UUID, amplifyService: AmplifyService? = nil) {
        // Remove from local listings (buyers won't see it)
        listings.removeAll { $0.id == id }
        myListingIDs.remove(id)
        deletedListingIDs.insert(id)
        currentUser.activeListings = myListingIDs.count

        if let service = amplifyService, service.isConfigured {
            Task {
                _ = await service.updateListingStatus(id: id.uuidString.lowercased(), status: .withdrawn)
            }
        }
    }

    func reactivateListing(_ id: UUID, amplifyService: AmplifyService? = nil) {
        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].status = .active
        }

        if let service = amplifyService, service.isConfigured {
            Task {
                _ = await service.updateListingStatus(id: id.uuidString.lowercased(), status: .active)
            }
        }
    }

    func updateListingImages(_ id: UUID, newImages: [UIImage], amplifyService: AmplifyService) {
        // Update local images immediately
        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].localImages = newImages
        }

        // Upload to backend
        Task {
            let imageDataArray = newImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
            let keys = await amplifyService.updateListingImages(
                listingID: id.uuidString.lowercased(),
                images: imageDataArray
            )
            if !keys.isEmpty {
                await MainActor.run {
                    if let index = listings.firstIndex(where: { $0.id == id }) {
                        listings[index].images = keys
                    }
                }
            }
        }
    }

    func deleteListing(_ id: UUID, amplifyService: AmplifyService? = nil) {
        listings.removeAll { $0.id == id }
        myListingIDs.remove(id)
        deletedListingIDs.insert(id)
        currentUser.activeListings = myListingIDs.count

        // Delete from backend
        if let service = amplifyService, service.isConfigured {
            Task {
                let success = await service.deleteListing(id: id.uuidString.lowercased())
                if !success {
                    // Also try uppercase in case backend stores it differently
                    _ = await service.deleteListing(id: id.uuidString)
                }
            }
        }
    }

    func sendMessage(in conversationID: UUID, text: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        let message = Message(
            id: UUID(),
            text: text,
            timestamp: Date(),
            isFromCurrentUser: true,
            isRead: true
        )
        conversations[index].messages.append(message)
        conversations[index].lastMessageDate = Date()
    }

    // MARK: - Delete Message

    func deleteMessage(_ messageID: UUID, in conversationID: UUID, amplifyService: AmplifyService? = nil) {
        guard let convoIndex = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[convoIndex].messages.removeAll { $0.id == messageID }

        // Track locally so it stays deleted across app restarts and backend refreshes
        deletedMessageIDs.insert(messageID)
        saveDeletedIDsToLocal()

        // Delete from backend
        if let service = amplifyService, service.isConfigured {
            Task {
                await service.deleteMessage(id: messageID.uuidString)
            }
        }
    }

    // MARK: - Delete Conversation

    func deleteConversation(_ conversationID: UUID, amplifyService: AmplifyService? = nil) {
        // Remove locally immediately
        conversations.removeAll { $0.id == conversationID }
        deletedConversationIDs.insert(conversationID)
        saveConversationsToLocal()
        print("[DELETE] Removed \(conversationID) locally, \(conversations.count) remaining")

        // Permanently delete from backend (conversation + all its messages)
        if let service = amplifyService, service.isConfigured {
            Task {
                let idStr = conversationID.uuidString.lowercased()
                print("[DELETE] Deleting messages for \(idStr) from backend...")
                await service.deleteMessagesForConversation(id: idStr)
                print("[DELETE] Deleting conversation \(idStr) from backend...")
                await service.deleteConversation(id: idStr)
                print("[DELETE] Backend delete complete for \(idStr)")
            }
        }
    }

    func startConversation(for listing: Listing, initialMessage: String) -> UUID {
        let conversationID = UUID()
        let localUserID = currentUser.id.uuidString
        let conversation = Conversation(
            id: conversationID,
            listingID: listing.id,
            listingTitle: listing.title,
            listingImage: listing.images.first ?? "photo",
            buyerID: localUserID,
            buyerName: currentUser.name,
            sellerID: listing.sellerID,
            sellerName: listing.sellerName,
            otherUserID: listing.sellerID,
            otherUserName: listing.sellerName,
            messages: [
                Message(
                    id: UUID(),
                    text: initialMessage,
                    timestamp: Date(),
                    isFromCurrentUser: true,
                    isRead: true
                )
            ],
            lastMessageDate: Date()
        )
        conversations.insert(conversation, at: 0)
        return conversationID
    }

    private var readConversationIDs: Set<UUID> = []

    func markConversationRead(_ conversationID: UUID, amplifyService: AmplifyService? = nil) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        for i in conversations[index].messages.indices {
            conversations[index].messages[i].isRead = true
        }
        readConversationIDs.insert(conversationID)
        saveReadIDsToLocal()

        // Mark as read on backend too
        if let service = amplifyService, service.isConfigured {
            let unreadMsgIDs = conversations[index].messages
                .filter { !$0.isFromCurrentUser }
                .map { $0.id.uuidString }
            Task {
                await service.markMessagesAsRead(messageIDs: unreadMsgIDs)
            }
        }
    }

    func clearFilters() {
        searchFilter = SearchFilter()
    }

    func listingsForCategory(_ category: ListingCategory) -> [Listing] {
        listings.filter { $0.category == category }.sorted { $0.postedDate > $1.postedDate }
    }

    // MARK: - Refresh Messages for One Conversation (lightweight polling)

    func refreshMessages(_ amplifyService: AmplifyService, conversationID: UUID) async {
        guard amplifyService.isConfigured else { return }
        let backendMessages = await amplifyService.fetchMessages(conversationID: conversationID.uuidString.lowercased())
        guard !backendMessages.isEmpty else { return }

        await MainActor.run {
            guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
            // Filter out locally deleted messages
            let filteredBackend = backendMessages.filter { !deletedMessageIDs.contains($0.id) }
            // Merge: take backend messages as the source of truth, but keep local-only messages
            let backendIDs = Set(filteredBackend.map { $0.id })
            let localOnly = conversations[index].messages.filter { !backendIDs.contains($0.id) && !deletedMessageIDs.contains($0.id) }
            var merged = filteredBackend + localOnly
            merged.sort { $0.timestamp < $1.timestamp }

            // Preserve locally-read status
            if readConversationIDs.contains(conversationID) {
                for j in merged.indices { merged[j].isRead = true }
            }

            conversations[index].messages = merged
            if let last = merged.last {
                conversations[index].lastMessageDate = last.timestamp
            }
        }
    }

    // MARK: - Real-time Subscriptions

    func startMessageSubscription(_ amplifyService: AmplifyService) {
        guard amplifyService.isConfigured else { return }
        print("AppViewModel: starting message subscription")
        amplifyService.subscribeToMessages { [weak self] convoID, senderID, text in
            Task { @MainActor in
                guard let self = self else { return }
                let currentUserID = amplifyService.currentUserID ?? ""

                // Skip messages sent by the current user — already added optimistically
                if senderID == currentUserID {
                    print("AppViewModel: ignoring own message in subscription for convo \(convoID)")
                    return
                }

                print("AppViewModel: received subscription message for convo \(convoID) from \(senderID)")
                // Compare case-insensitively — AppSync returns lowercase UUIDs, Swift uppercases them
                if let index = self.conversations.firstIndex(where: { $0.id.uuidString.lowercased() == convoID.lowercased() }) {
                    // Existing conversation — append the new message
                    let message = Message(
                        id: UUID(),
                        text: text,
                        timestamp: Date(),
                        isFromCurrentUser: false,
                        isRead: false
                    )
                    self.conversations[index].messages.append(message)
                    self.conversations[index].lastMessageDate = Date()
                } else {
                    // Check if this conversation was deleted — don't resurrect it
                    if let convoUUID = UUID(uuidString: convoID), self.deletedConversationIDs.contains(convoUUID) {
                        print("AppViewModel: convo \(convoID) was deleted, ignoring")
                        return
                    }

                    // New conversation — fetch from backend to pick it up
                    print("AppViewModel: convo \(convoID) not found locally, fetching from backend...")
                    let fetchedConvos = await amplifyService.fetchConversations()
                    print("AppViewModel: fetched \(fetchedConvos.count) convos from backend")
                    // Filter out deleted conversations and messages
                    var resolved = fetchedConvos.filter { !self.deletedConversationIDs.contains($0.id) }
                    for i in resolved.indices {
                        resolved[i].messages.removeAll { self.deletedMessageIDs.contains($0.id) }
                    }
                    self.resolveConversationNames(&resolved, amplifyService: amplifyService)
                    let existingIDs = Set(self.conversations.map { $0.id })
                    let newConversations = resolved.filter { !existingIDs.contains($0.id) }
                    self.conversations.insert(contentsOf: newConversations, at: 0)

                    await self.resolveUnknownNames(amplifyService)
                }
            }
        }
    }

    // MARK: - Refresh

    func refreshListings(_ amplifyService: AmplifyService) async {
        guard amplifyService.isConfigured else { return }
        let fetchedListings = await amplifyService.fetchListings()
        let uid = amplifyService.currentUserID
        await MainActor.run {
            // Preserve localImages from existing listings
            let existingLocalImages = Dictionary(uniqueKeysWithValues:
                self.listings.filter { !$0.localImages.isEmpty }.map { ($0.id, $0.localImages) }
            )
            var merged = fetchedListings.filter { !self.deletedListingIDs.contains($0.id) }
            for i in merged.indices {
                if let localImgs = existingLocalImages[merged[i].id] {
                    merged[i].localImages = localImgs
                }
            }
            self.listings = merged
            self.myListingIDs = []
            if let uid = uid {
                for listing in merged {
                    if listing.sellerID == uid {
                        myListingIDs.insert(listing.id)
                    }
                }
                currentUser.activeListings = myListingIDs.count
            }
        }
    }

    func refreshConversations(_ amplifyService: AmplifyService) async {
        guard amplifyService.isConfigured, amplifyService.currentUserID != nil else {
            print("[REFRESH] skipped: configured=\(amplifyService.isConfigured), signedIn=\(amplifyService.isSignedIn), userID=\(amplifyService.currentUserID ?? "nil")")
            return
        }
        print("[REFRESH] Starting fetch... userID=\(amplifyService.currentUserID ?? "nil")")
        let fetched = await amplifyService.fetchConversations()
        print("[REFRESH] fetched \(fetched.count) from backend, have \(await MainActor.run { conversations.count }) local")

        // If backend returned nothing, don't wipe local conversations
        guard !fetched.isEmpty else {
            print("[REFRESH] backend returned 0, keeping local data")
            return
        }

        await MainActor.run {
            // Filter out conversations deleted this session (in-memory guard until backend delete propagates)
            var merged = fetched.filter { !deletedConversationIDs.contains($0.id) }
            for i in merged.indices {
                merged[i].messages.removeAll { deletedMessageIDs.contains($0.id) }
            }

            // Resolve names: replace raw IDs with profile names
            resolveConversationNames(&merged, amplifyService: amplifyService)

            // Build lookup of existing local conversations
            let existingByID = Dictionary(uniqueKeysWithValues: self.conversations.map { ($0.id, $0) })

            for i in merged.indices {
                let convoID = merged[i].id

                // Preserve locally-read status
                if readConversationIDs.contains(convoID) {
                    for j in merged[i].messages.indices {
                        merged[i].messages[j].isRead = true
                    }
                }

                // Merge messages: keep local messages that the backend doesn't have yet
                if let existing = existingByID[convoID] {
                    let fetchedMsgIDs = Set(merged[i].messages.map { $0.id })
                    // Also build a set of (text, ~timestamp) to catch duplicates with mismatched IDs
                    let fetchedMsgKeys = Set(merged[i].messages.map { "\($0.text)|\(Int($0.timestamp.timeIntervalSince1970 / 5))" })
                    let localOnly = existing.messages.filter { msg in
                        guard !fetchedMsgIDs.contains(msg.id) else { return false }
                        // Also skip if same text within ~5 seconds (likely a duplicate with different ID)
                        let key = "\(msg.text)|\(Int(msg.timestamp.timeIntervalSince1970 / 5))"
                        return !fetchedMsgKeys.contains(key)
                    }
                    if !localOnly.isEmpty {
                        merged[i].messages.append(contentsOf: localOnly)
                        merged[i].messages.sort { $0.timestamp < $1.timestamp }
                    }
                    // Preserve the resolved name if backend returned a raw ID
                    if existing.otherUserName != existing.otherUserID {
                        merged[i].otherUserName = existing.otherUserName
                    }
                }
            }

            // Also keep any local-only conversations not yet on backend (but not deleted ones)
            let mergedIDs = Set(merged.map { $0.id })
            let localOnlyConvos = self.conversations.filter {
                !mergedIDs.contains($0.id) && !deletedConversationIDs.contains($0.id)
            }

            self.conversations = merged + localOnlyConvos
            print("[REFRESH] Final conversation count: \(self.conversations.count)")
        }

        // Async: fetch profile names for any buyers we don't know yet
        await resolveUnknownNames(amplifyService)
    }

    /// Cache of userID -> profile name so we don't re-fetch every time
    private var userNameCache: [String: String] = [:]

    /// Replace raw user IDs in conversation otherUserName with readable profile names
    private func resolveConversationNames(_ convos: inout [Conversation], amplifyService: AmplifyService) {
        // Build a lookup from sellerID -> sellerName using listings
        var knownNames: [String: String] = userNameCache
        for listing in listings {
            if !listing.sellerName.isEmpty {
                knownNames[listing.sellerID] = listing.sellerName
            }
        }

        let currentUserID = amplifyService.currentUserID ?? ""
        knownNames[currentUserID] = currentUser.name

        for i in convos.indices {
            let otherID = convos[i].otherUserID
            if let name = knownNames[otherID] {
                convos[i].otherUserName = name
            }
            // If still a raw ID, leave it — async resolve will fix it
        }
    }

    /// Async: fetch profile names for any unresolved user IDs from the backend
    func resolveUnknownNames(_ amplifyService: AmplifyService) async {
        guard amplifyService.isConfigured else { return }

        // Build set of known names
        var knownIDs = Set(userNameCache.keys)
        if let uid = amplifyService.currentUserID { knownIDs.insert(uid) }
        for listing in await MainActor.run(body: { listings }) {
            knownIDs.insert(listing.sellerID)
        }

        // Find conversation otherUserIDs that are still unresolved
        let unresolvedIDs: [String] = await MainActor.run {
            let ids = conversations
                .map { $0.otherUserID }
                .filter { id in
                    // Still unresolved if otherUserName == otherUserID (raw ID)
                    !userNameCache.keys.contains(id) &&
                    conversations.first(where: { $0.otherUserID == id })?.otherUserName == id
                }
            return Array(Set(ids))
        }

        guard !unresolvedIDs.isEmpty else { return }

        // Fetch each unknown user's profile name
        for userID in unresolvedIDs {
            if let name = await amplifyService.fetchUserName(byOwnerID: userID) {
                await MainActor.run {
                    userNameCache[userID] = name
                    // Update all conversations with this user
                    for i in conversations.indices {
                        if conversations[i].otherUserID == userID {
                            conversations[i].otherUserName = name
                        }
                    }
                }
            }
        }
    }

    // MARK: - S3 Image URL

    func getImageURL(_ amplifyService: AmplifyService, path: String) async -> URL? {
        guard amplifyService.isConfigured else { return nil }
        return try? await amplifyService.getImageURL(path: path)
    }

    // MARK: - Save Profile to Backend

    func saveProfileToBackend(_ amplifyService: AmplifyService, name: String, email: String, phone: String, location: String) async {
        guard amplifyService.isConfigured else { return }
        do {
            try await amplifyService.createOrUpdateProfile(
                name: name,
                email: email,
                phone: phone.isEmpty ? nil : phone,
                location: location.isEmpty ? nil : location
            )
            await MainActor.run {
                currentUser.name = name
                currentUser.email = email
                currentUser.phone = phone
                currentUser.location = location
            }
        } catch {
            print("saveProfileToBackend failed: \(error)")
        }
    }
}
