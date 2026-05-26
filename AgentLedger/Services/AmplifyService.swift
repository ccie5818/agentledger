import Foundation
import Amplify

// MARK: - Amplify Service (Gen 2)
class AmplifyService: ObservableObject {
    static let shared = AmplifyService()

    @Published var isSignedIn = false
    @Published var currentUserID: String?
    @Published var currentUserName: String?
    @Published var currentUserEmail: String?

    /// Set to true only after Amplify.configure() succeeds
    var isConfigured = false

    // MARK: - Auth
    func checkAuthStatus() async {
        guard isConfigured else {
            print("Amplify not configured — skipping auth check")
            await MainActor.run { self.isSignedIn = false }
            return
        }
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            if session.isSignedIn {
                // Fetch attributes BEFORE setting isSignedIn so observers get real data
                let user = try await Amplify.Auth.getCurrentUser()
                let attributes = try await Amplify.Auth.fetchUserAttributes()
                let email = attributes.first { $0.key == .email }?.value
                let name = attributes.first { $0.key == .name }?.value
                    ?? attributes.first { $0.key == .preferredUsername }?.value

                let displayName: String
                if let name = name, !name.isEmpty {
                    displayName = name
                } else if let email = email, email.contains("@") {
                    displayName = String(email.prefix(while: { $0 != "@" }))
                } else {
                    displayName = user.username
                }

                await MainActor.run {
                    self.currentUserID = user.userId
                    self.currentUserName = displayName
                    self.currentUserEmail = email
                    self.isSignedIn = true
                }
            } else {
                await MainActor.run { self.isSignedIn = false }
            }
        } catch {
            print("Auth check failed: \(error)")
            await MainActor.run { self.isSignedIn = false }
        }
    }

    func signUp(username: String, password: String, email: String) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        let attributes = [AuthUserAttribute(.email, value: email)]
        let options = AuthSignUpRequest.Options(userAttributes: attributes)
        let result = try await Amplify.Auth.signUp(
            username: username,
            password: password,
            options: options
        )
        if case .confirmUser = result.nextStep {
            print("Confirmation code sent to \(email)")
        }
    }

    func confirmSignUp(username: String, code: String) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        _ = try await Amplify.Auth.confirmSignUp(for: username, confirmationCode: code)
    }

    func signIn(username: String, password: String) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        let result = try await Amplify.Auth.signIn(username: username, password: password)
        if result.isSignedIn {
            // Fetch user attributes BEFORE setting isSignedIn so that
            // downstream observers (syncWithAmplify) see the real name/email
            let user = try await Amplify.Auth.getCurrentUser()
            let attributes = try await Amplify.Auth.fetchUserAttributes()
            let email = attributes.first { $0.key == .email }?.value
            let name = attributes.first { $0.key == .name }?.value
                ?? attributes.first { $0.key == .preferredUsername }?.value

            let displayName: String
            if let name = name, !name.isEmpty {
                displayName = name
            } else if let email = email, email.contains("@") {
                displayName = String(email.prefix(while: { $0 != "@" }))
            } else {
                displayName = user.username
            }

            await MainActor.run {
                self.currentUserID = user.userId
                self.currentUserName = displayName
                self.currentUserEmail = email
                self.isSignedIn = true
            }
        } else {
            await MainActor.run { self.isSignedIn = false }
        }
    }

    func signOut() async {
        guard isConfigured else {
            await MainActor.run {
                self.isSignedIn = false
                self.currentUserID = nil
                self.currentUserName = nil
                self.currentUserEmail = nil
            }
            return
        }
        _ = await Amplify.Auth.signOut()
        await MainActor.run {
            self.isSignedIn = false
            self.currentUserID = nil
            self.currentUserName = nil
            self.currentUserEmail = nil
        }
    }

    func resetPassword(for username: String) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        _ = try await Amplify.Auth.resetPassword(for: username)
    }

    func confirmResetPassword(for username: String, newPassword: String, code: String) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        try await Amplify.Auth.confirmResetPassword(for: username, with: newPassword, confirmationCode: code)
    }

    // MARK: - Storage (S3)
    func uploadImage(data: Data, path: String) async throws -> String {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        let key = "listings/\(path).jpg"
        let uploadTask = Amplify.Storage.uploadData(path: .fromString(key), data: data)
        _ = try await uploadTask.value
        return key
    }

    func getImageURL(path: String) async throws -> URL {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        let url = try await Amplify.Storage.getURL(path: .fromString(path))
        return url
    }

    func uploadListingImages(_ images: [Data], listingID: String) async -> [String] {
        guard isConfigured else { return [] }
        var keys: [String] = []
        for (index, imageData) in images.enumerated() {
            let path = "\(listingID)/photo_\(index)"
            do {
                let key = try await uploadImage(data: imageData, path: path)
                keys.append(key)
            } catch {
                print("Upload failed for image \(index): \(error)")
            }
        }
        return keys
    }

    // MARK: - Data (AppSync GraphQL)

    /// Fetch all active listings from the backend
    func fetchListings() async -> [Listing] {
        guard isConfigured else { return [] }
        let document = """
        query ListListings {
            listListings(filter: { isActive: { eq: true } }) {
                items {
                    id
                    title
                    description
                    price
                    category
                    subcategory
                    imageKeys
                    location
                    neighborhood
                    condition
                    listingStatus
                    sellerID
                    sellerName
                    createdAt
                }
            }
        }
        """
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: nil, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                return parseListings(data)
            case .failure(let error):
                print("fetchListings GraphQL error: \(error)")
                return []
            }
        } catch {
            print("fetchListings failed: \(error)")
            return []
        }
    }

    /// Create a new listing on the backend
    func createListing(title: String, description: String, price: Double?, category: ListingCategory, subcategory: String, location: String, neighborhood: String, condition: ItemCondition?, imageKeys: [String]) async -> Listing? {
        guard isConfigured, let userID = currentUserID else { return nil }
        let sellerName = currentUserName ?? "Unknown"
        let categoryStr = mapCategoryToBackend(category)
        let conditionStr = condition.map { mapConditionToBackend($0) }

        var input: [String: Any] = [
            "title": title,
            "description": description,
            "category": categoryStr,
            "subcategory": subcategory,
            "location": location,
            "neighborhood": neighborhood,
            "sellerID": userID,
            "sellerName": sellerName,
            "isActive": true,
            "imageKeys": imageKeys
        ]
        if let price = price { input["price"] = price }
        if let conditionStr = conditionStr { input["condition"] = conditionStr }
        let variables: [String: Any] = ["input": input]

        let document = """
        mutation CreateListing($input: CreateListingInput!) {
            createListing(input: $input) {
                id
                title
                description
                price
                category
                subcategory
                imageKeys
                location
                neighborhood
                condition
                sellerID
                sellerName
                createdAt
            }
        }
        """
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success(let data):
                if let item = data.value(at: "createListing") {
                    return parseSingleListing(item)
                }
                return nil
            case .failure(let error):
                print("createListing GraphQL error: \(error)")
                return nil
            }
        } catch {
            print("createListing failed: \(error)")
            return nil
        }
    }

    /// Fetch conversations for the current user (as buyer OR seller)
    func fetchConversations() async -> [Conversation] {
        guard isConfigured, let userID = currentUserID else { return [] }

        // Fetch conversations where user is the buyer
        async let buyerConvos = fetchConversationsWhere(field: "buyerID", userID: userID)
        // Fetch conversations where user is the seller
        async let sellerConvos = fetchConversationsWhere(field: "sellerID", userID: userID)

        let (asB, asS) = await (buyerConvos, sellerConvos)
        // Merge, deduplicating by ID
        var seen = Set<String>()
        var all: [Conversation] = []
        for c in asB + asS {
            let key = c.id.uuidString.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                all.append(c)
            }
        }
        print("fetchConversations: \(asB.count) as buyer + \(asS.count) as seller = \(all.count) total")
        return all
    }

    private func fetchConversationsWhere(field: String, userID: String) async -> [Conversation] {
        let document = """
        query ListConversations($filter: ModelConversationFilterInput) {
            listConversations(filter: $filter, limit: 100) {
                items {
                    id
                    listingID
                    listingTitle
                    buyerID
                    buyerName
                    sellerID
                    sellerName
                    lastMessage
                    lastMessageAt
                    messages {
                        items {
                            id
                            senderID
                            text
                            isRead
                            createdAt
                        }
                    }
                }
            }
        }
        """
        let variables: [String: Any] = [
            "filter": [field: ["eq": userID]]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                return parseConversations(data, currentUserID: userID)
            case .failure(let error):
                print("fetchConversations(\(field)) GraphQL error: \(error)")
                return []
            }
        } catch {
            print("fetchConversations(\(field)) failed: \(error)")
            return []
        }
    }

    /// Create a new conversation
    func createConversation(listing: Listing, initialMessage: String) async -> Conversation? {
        guard isConfigured, let userID = currentUserID else {
            print("[MSG] createConversation: not configured or no userID (configured=\(isConfigured), userID=\(currentUserID ?? "nil"))")
            return nil
        }
        let buyerName = currentUserName ?? "Unknown"
        print("[MSG] createConversation: buyer=\(userID) (\(buyerName)), seller=\(listing.sellerID), listing=\(listing.id)")
        let document = """
        mutation CreateConversation($input: CreateConversationInput!) {
            createConversation(input: $input) {
                id
                listingID
                listingTitle
                buyerID
                buyerName
                sellerID
                sellerName
                lastMessage
                lastMessageAt
            }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "listingID": listing.id.uuidString.lowercased(),
                "listingTitle": listing.title,
                "buyerID": userID,
                "buyerName": buyerName,
                "sellerID": listing.sellerID,
                "sellerName": listing.sellerName,
                "lastMessage": initialMessage,
                "lastMessageAt": ISO8601DateFormatter().string(from: Date()),
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success(let data):
                print("[MSG] createConversation mutation success, parsing response...")
                if let item = data.value(at: "createConversation"),
                   let convoID = item.value(at: "id")?.stringValue {
                    print("[MSG] Conversation created on backend: \(convoID)")
                    // Also send the first message (recipientID = seller)
                    let backendMsgID = await sendMessageToBackend(conversationID: convoID, text: initialMessage, recipientID: listing.sellerID)
                    print("[MSG] Initial message sent, backendMsgID=\(backendMsgID ?? "nil")")
                    let msgID: UUID
                    if let idStr = backendMsgID, let parsed = UUID(uuidString: idStr) {
                        msgID = parsed
                    } else {
                        msgID = UUID()
                    }

                    return Conversation(
                        id: UUID(uuidString: convoID) ?? UUID(),
                        listingID: listing.id,
                        listingTitle: listing.title,
                        listingImage: listing.images.first ?? "photo",
                        buyerID: userID,
                        buyerName: buyerName,
                        sellerID: listing.sellerID,
                        sellerName: listing.sellerName,
                        otherUserID: listing.sellerID,
                        otherUserName: listing.sellerName,
                        messages: [
                            Message(id: msgID, text: initialMessage, timestamp: Date(), isFromCurrentUser: true, isRead: true)
                        ],
                        lastMessageDate: Date()
                    )
                } else {
                    print("[MSG] ERROR: Could not parse createConversation response: \(data)")
                }
                return nil
            case .failure(let error):
                print("[MSG] createConversation GraphQL error: \(error)")
                return nil
            }
        } catch {
            print("createConversation failed: \(error)")
            return nil
        }
    }

    /// Send a message in a conversation. Returns the backend message ID on success, nil on failure.
    func sendMessageToBackend(conversationID: String, text: String, recipientID: String? = nil) async -> String? {
        guard isConfigured, let userID = currentUserID else { return nil }
        let document = """
        mutation CreateMessage($input: CreateMessageInput!) {
            createMessage(input: $input) {
                id
                conversationID
                senderID
                recipientID
                text
                status
                createdAt
            }
        }
        """
        var input: [String: Any] = [
            "conversationID": conversationID.lowercased(),
            "senderID": userID,
            "text": text,
            "isRead": false,
            "status": "SENT"
        ]
        if let recipientID = recipientID {
            input["recipientID"] = recipientID
        } else {
            input["recipientID"] = "unknown"
        }
        print("sendMessageToBackend: senderID=\(userID), recipientID=\(recipientID ?? "nil"), convoID=\(conversationID)")
        let variables: [String: Any] = ["input": input]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success(let data):
                // Also update conversation's lastMessage
                await updateConversationLastMessage(conversationID: conversationID, message: text)
                let backendID = data.value(at: "createMessage")?.value(at: "id")?.stringValue
                print("sendMessage OK, backendID=\(backendID ?? "nil")")
                return backendID
            case .failure(let error):
                print("sendMessage GraphQL error: \(error)")
                return nil
            }
        } catch {
            print("sendMessage failed: \(error)")
            return nil
        }
    }

    private func updateConversationLastMessage(conversationID: String, message: String) async {
        let document = """
        mutation UpdateConversation($input: UpdateConversationInput!) {
            updateConversation(input: $input) { id }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "id": conversationID.lowercased(),
                "lastMessage": message,
                "lastMessageAt": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            _ = try await Amplify.API.mutate(request: request)
        } catch {
            print("updateConversationLastMessage failed: \(error)")
        }
    }

    // MARK: - Fetch Messages for a Single Conversation

    /// Lightweight fetch: just messages for one conversation (for polling in ChatView)
    func fetchMessages(conversationID: String) async -> [Message] {
        guard isConfigured, let userID = currentUserID else { return [] }
        let document = """
        query ListMessages($filter: ModelMessageFilterInput) {
            listMessages(filter: $filter, limit: 200) {
                items {
                    id
                    senderID
                    text
                    isRead
                    createdAt
                }
            }
        }
        """
        let variables: [String: Any] = [
            "filter": ["conversationID": ["eq": conversationID]]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                guard let items = data.value(at: "listMessages")?.value(at: "items"),
                      case .array(let array) = items else { return [] }
                return array.compactMap { msg -> Message? in
                    guard
                        let text = msg.value(at: "text")?.stringValue,
                        let senderID = msg.value(at: "senderID")?.stringValue
                    else { return nil }

                    var timestamp = Date()
                    if let dateStr = msg.value(at: "createdAt")?.stringValue {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        timestamp = formatter.date(from: dateStr) ?? Date()
                    }
                    let msgID: UUID
                    if let msgIDStr = msg.value(at: "id")?.stringValue {
                        msgID = UUID(uuidString: msgIDStr) ?? UUID()
                    } else {
                        msgID = UUID()
                    }
                    return Message(
                        id: msgID,
                        text: text,
                        timestamp: timestamp,
                        isFromCurrentUser: senderID == userID,
                        isRead: msg.value(at: "isRead")?.booleanValue ?? false
                    )
                }.sorted { $0.timestamp < $1.timestamp }
            case .failure(let error):
                print("fetchMessages error: \(error)")
                return []
            }
        } catch {
            print("fetchMessages failed: \(error)")
            return []
        }
    }

    // MARK: - Delete Message

    func deleteMessage(id: String) async {
        guard isConfigured else { return }
        let document = """
        mutation DeleteMessage($input: DeleteMessageInput!) {
            deleteMessage(input: $input) { id }
        }
        """
        let variables: [String: Any] = ["input": ["id": id]]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            _ = try await Amplify.API.mutate(request: request)
        } catch {
            print("deleteMessage failed: \(error)")
        }
    }

    // MARK: - Delete Conversation

    func deleteConversation(id: String) async {
        guard isConfigured else { return }
        let document = """
        mutation DeleteConversation($input: DeleteConversationInput!) {
            deleteConversation(input: $input) { id }
        }
        """
        let variables: [String: Any] = ["input": ["id": id]]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            _ = try await Amplify.API.mutate(request: request)
            print("[DELETE] Conversation \(id) deleted from backend")
        } catch {
            print("[DELETE] deleteConversation failed: \(error)")
        }
    }

    func deleteMessagesForConversation(id: String) async {
        guard isConfigured else { return }
        // First fetch all message IDs for this conversation
        let query = """
        query ListMessages($filter: ModelMessageFilterInput) {
            listMessages(filter: $filter, limit: 100) {
                items { id }
            }
        }
        """
        let queryVars: [String: Any] = ["filter": ["conversationID": ["eq": id]]]
        do {
            let request = GraphQLRequest<JSONValue>(document: query, variables: queryVars, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                guard let items = data.value(at: "listMessages")?.value(at: "items"),
                      case .array(let arr) = items else { return }
                print("[DELETE] Found \(arr.count) messages to delete for conversation \(id)")
                // Delete each message
                for item in arr {
                    if let msgID = item.value(at: "id")?.stringValue {
                        let deleteMut = """
                        mutation DeleteMessage($input: DeleteMessageInput!) {
                            deleteMessage(input: $input) { id }
                        }
                        """
                        let deleteVars: [String: Any] = ["input": ["id": msgID]]
                        let deleteReq = GraphQLRequest<JSONValue>(document: deleteMut, variables: deleteVars, responseType: JSONValue.self)
                        _ = try await Amplify.API.mutate(request: deleteReq)
                    }
                }
                print("[DELETE] All messages deleted for conversation \(id)")
            case .failure(let error):
                print("[DELETE] Failed to list messages: \(error)")
            }
        } catch {
            print("[DELETE] deleteMessagesForConversation failed: \(error)")
        }
    }

    // MARK: - Fetch Profile Name by User ID

    func fetchUserName(byOwnerID ownerID: String) async -> String? {
        guard isConfigured else { return nil }
        let document = """
        query ListUserProfiles {
            listUserProfiles(filter: { owner: { eq: "\(ownerID)" } }) {
                items { id name }
            }
        }
        """
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: nil, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                if let items = data.value(at: "listUserProfiles")?.value(at: "items"),
                   case .array(let arr) = items,
                   let first = arr.first,
                   let name = first.value(at: "name")?.stringValue,
                   !name.isEmpty {
                    return name
                }
                return nil
            case .failure(let error):
                print("fetchUserName error: \(error)")
                return nil
            }
        } catch {
            print("fetchUserName failed: \(error)")
            return nil
        }
    }

    // MARK: - Mark Messages as Read

    func markMessagesAsRead(messageIDs: [String]) async {
        guard isConfigured else { return }
        let document = """
        mutation UpdateMessage($input: UpdateMessageInput!) {
            updateMessage(input: $input) { id isRead }
        }
        """
        for msgID in messageIDs {
            let variables: [String: Any] = ["input": ["id": msgID, "isRead": true]]
            do {
                let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
                _ = try await Amplify.API.mutate(request: request)
            } catch {
                print("markMessageAsRead failed for \(msgID): \(error)")
            }
        }
    }

    // MARK: - Delete Listing

    func deleteListing(id: String) async -> Bool {
        guard isConfigured else { return false }

        // First soft-delete by setting isActive to false (so other users stop seeing it)
        let updateDoc = """
        mutation UpdateListing($input: UpdateListingInput!) {
            updateListing(input: $input) { id isActive }
        }
        """
        let updateVars: [String: Any] = ["input": ["id": id, "isActive": false]]
        do {
            let updateReq = GraphQLRequest<JSONValue>(document: updateDoc, variables: updateVars, responseType: JSONValue.self)
            let updateResult = try await Amplify.API.mutate(request: updateReq)
            switch updateResult {
            case .success:
                print("Listing deactivated on backend")
            case .failure(let error):
                print("updateListing (deactivate) error: \(error)")
            }
        } catch {
            print("updateListing (deactivate) failed: \(error)")
        }

        // Then hard-delete
        let deleteDoc = """
        mutation DeleteListing($input: DeleteListingInput!) {
            deleteListing(input: $input) { id }
        }
        """
        let deleteVars: [String: Any] = ["input": ["id": id]]
        do {
            let request = GraphQLRequest<JSONValue>(document: deleteDoc, variables: deleteVars, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success:
                print("Listing deleted from backend")
                return true
            case .failure(let error):
                print("deleteListing error: \(error)")
                return false
            }
        } catch {
            print("deleteListing failed: \(error)")
            return false
        }
    }

    // MARK: - Update Listing Status

    func updateListingStatus(id: String, status: ListingStatus) async -> Bool {
        guard isConfigured else { return false }

        let backendStatus: String
        switch status {
        case .active: backendStatus = "ACTIVE"
        case .sold: backendStatus = "SOLD"
        case .withdrawn: backendStatus = "WITHDRAWN"
        }

        // When withdrawing, also set isActive to false so buyers no longer see it
        let isActive = status != .withdrawn

        let document = """
        mutation UpdateListing($input: UpdateListingInput!) {
            updateListing(input: $input) { id listingStatus isActive }
        }
        """
        let vars: [String: Any] = ["input": ["id": id, "listingStatus": backendStatus, "isActive": isActive]]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: vars, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success:
                print("Listing status updated to \(backendStatus)")
                return true
            case .failure(let error):
                print("updateListingStatus error: \(error)")
                return false
            }
        } catch {
            print("updateListingStatus failed: \(error)")
            return false
        }
    }

    /// Upload new images and update the listing's imageKeys in the backend
    func updateListingImages(listingID: String, images: [Data]) async -> [String] {
        guard isConfigured else { return [] }

        // Upload new images to S3
        let keys = await uploadListingImages(images, listingID: listingID)
        guard !keys.isEmpty else { return [] }

        // Update the listing record with new imageKeys
        let document = """
        mutation UpdateListing($input: UpdateListingInput!) {
            updateListing(input: $input) { id imageKeys }
        }
        """
        let vars: [String: Any] = ["input": ["id": listingID, "imageKeys": keys]]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: vars, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success:
                print("Listing images updated: \(keys.count) photos")
                return keys
            case .failure(let error):
                print("updateListingImages error: \(error)")
                return []
            }
        } catch {
            print("updateListingImages failed: \(error)")
            return []
        }
    }

    // MARK: - Real-time Subscriptions

    /// Track whether a subscription is already active
    private var isSubscriptionActive = false

    /// Subscribe to new messages — with allow.authenticated() auth, all events
    /// come through and we filter client-side by recipientID.
    func subscribeToMessages(onNewMessage: @escaping (String, String, String) -> Void) {
        guard isConfigured, let userID = currentUserID else {
            print("subscribeToMessages: skipped — configured=\(isConfigured), userID=\(currentUserID ?? "nil")")
            return
        }

        guard !isSubscriptionActive else {
            print("subscribeToMessages: already active, skipping")
            return
        }
        isSubscriptionActive = true

        let document = """
        subscription OnCreateMessage {
            onCreateMessage {
                id
                conversationID
                senderID
                recipientID
                text
                createdAt
            }
        }
        """
        print("subscribeToMessages: starting for user \(userID)")
        let request = GraphQLRequest<JSONValue>(document: document, variables: nil, responseType: JSONValue.self)
        let subscription = Amplify.API.subscribe(request: request)
        Task {
            do {
                for try await event in subscription {
                    switch event {
                    case .connection(let state):
                        print("Subscription connection: \(state)")
                    case .data(let result):
                        switch result {
                        case .success(let data):
                            if let msg = data.value(at: "onCreateMessage"),
                               let convoID = msg.value(at: "conversationID")?.stringValue,
                               let senderID = msg.value(at: "senderID")?.stringValue,
                               let text = msg.value(at: "text")?.stringValue {
                                let recipient = msg.value(at: "recipientID")?.stringValue
                                print("Sub event: convo=\(convoID) sender=\(senderID) recipient=\(recipient ?? "nil") me=\(userID)")
                                // Deliver if the message is for us and not from us
                                if senderID != userID && (recipient == nil || recipient == userID) {
                                    onNewMessage(convoID, senderID, text)
                                }
                            }
                        case .failure(let error):
                            print("Sub data error: \(error)")
                        }
                    }
                }
                print("Subscription ended")
                isSubscriptionActive = false
            } catch {
                print("Subscription failed: \(error)")
                isSubscriptionActive = false
            }
        }
    }

    // MARK: - Update Cognito Profile Attributes

    func updateCognitoAttributes(name: String?, phone: String?) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        var attributes: [AuthUserAttribute] = []
        if let name = name {
            attributes.append(AuthUserAttribute(.name, value: name))
        }
        if let phone = phone {
            attributes.append(AuthUserAttribute(.phoneNumber, value: phone))
        }
        if !attributes.isEmpty {
            _ = try await Amplify.Auth.update(userAttributes: attributes)
            // Update local state
            if let name = name {
                await MainActor.run { self.currentUserName = name }
            }
        }
    }

    // MARK: - User Profile & Favorites

    /// Profile ID stored after first fetch/create
    var profileRecordID: String?

    func createOrUpdateProfile(name: String, email: String, phone: String?, location: String?) async throws {
        guard isConfigured else { throw AmplifyNotConfiguredError() }
        // Update Cognito attributes
        try await updateCognitoAttributes(name: name, phone: phone)

        // Update the DynamoDB profile
        if profileRecordID == nil {
            _ = await fetchUserProfile()
        }
        if profileRecordID == nil {
            _ = await createUserProfile()
        }
        guard let profileID = profileRecordID else { return }

        let document = """
        mutation UpdateUserProfile($input: UpdateUserProfileInput!) {
            updateUserProfile(input: $input) { id name email phone location }
        }
        """
        var input: [String: Any] = [
            "id": profileID,
            "name": name,
            "email": email
        ]
        if let phone = phone { input["phone"] = phone }
        if let location = location { input["location"] = location }
        let variables: [String: Any] = ["input": input]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            _ = try await Amplify.API.mutate(request: request)
            print("Profile updated on backend")
        } catch {
            print("createOrUpdateProfile failed: \(error)")
        }
    }

    /// Fetch the current user's profile (including favorites and hidden conversations)
    func fetchUserProfile() async -> (profileID: String, favoriteIDs: [String], hiddenConversationIDs: [String])? {
        guard isConfigured, let userID = currentUserID else { return nil }

        // Use owner filter to only fetch profiles belonging to the current user
        let document = """
        query ListUserProfiles {
            listUserProfiles(filter: { owner: { contains: "\(userID)" } }, limit: 50) {
                items {
                    id
                    owner
                    favoriteListingIDs
                    hiddenConversationIDs
                    deviceToken
                }
            }
        }
        """
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: nil, responseType: JSONValue.self)
            let result = try await Amplify.API.query(request: request)
            switch result {
            case .success(let data):
                if let items = data.value(at: "listUserProfiles")?.value(at: "items"),
                   case .array(let arr) = items, !arr.isEmpty {
                    print("[PROFILE] Found \(arr.count) profile(s) for user \(userID.prefix(8))...")

                    // Pick the best profile: prefer one with a device token
                    var bestProfile: JSONValue = arr[0]
                    for item in arr {
                        if item.value(at: "deviceToken")?.stringValue != nil {
                            bestProfile = item
                            break
                        }
                    }

                    if let profileID = bestProfile.value(at: "id")?.stringValue {
                        self.profileRecordID = profileID
                        print("[PROFILE] Using profile: \(profileID)")
                        var favIDs: [String] = []
                        if let favs = bestProfile.value(at: "favoriteListingIDs"),
                           case .array(let favArray) = favs {
                            favIDs = favArray.compactMap { $0.stringValue }
                        }
                        var hiddenIDs: [String] = []
                        if let hidden = bestProfile.value(at: "hiddenConversationIDs"),
                           case .array(let hiddenArray) = hidden {
                            hiddenIDs = hiddenArray.compactMap { $0.stringValue }
                        }
                        return (profileID, favIDs, hiddenIDs)
                    }
                }
                print("[PROFILE] No profile found for current user")
                return nil
            case .failure(let error):
                print("[PROFILE] fetchUserProfile error: \(error)")
                return nil
            }
        } catch {
            print("[PROFILE] fetchUserProfile failed: \(error)")
            return nil
        }
    }

    /// Create a user profile only if one doesn't already exist
    func createUserProfile() async -> String? {
        guard isConfigured else { return nil }
        // Double-check: don't create if we already have one
        if let existing = await fetchUserProfile() {
            print("[PROFILE] Profile already exists (\(existing.profileID)), skipping create")
            return existing.profileID
        }
        let document = """
        mutation CreateUserProfile($input: CreateUserProfileInput!) {
            createUserProfile(input: $input) { id }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "name": currentUserName ?? "User",
                "email": currentUserEmail ?? "",
                "favoriteListingIDs": [] as [String]
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success(let data):
                if let id = data.value(at: "createUserProfile")?.value(at: "id")?.stringValue {
                    self.profileRecordID = id
                    return id
                }
                return nil
            case .failure(let error):
                print("createUserProfile error: \(error)")
                return nil
            }
        } catch {
            print("createUserProfile failed: \(error)")
            return nil
        }
    }

    /// Update hidden conversation IDs on the backend
    func updateHiddenConversations(_ hiddenIDs: [String]) async {
        guard isConfigured else { return }
        if profileRecordID == nil { _ = await fetchUserProfile() }
        if profileRecordID == nil { _ = await createUserProfile() }
        guard let profileID = profileRecordID else { return }

        let document = """
        mutation UpdateUserProfile($input: UpdateUserProfileInput!) {
            updateUserProfile(input: $input) { id hiddenConversationIDs }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "id": profileID,
                "hiddenConversationIDs": hiddenIDs
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success:
                print("[DELETE] Hidden conversations updated on backend: \(hiddenIDs.count) IDs")
            case .failure(let error):
                print("[DELETE] Failed to update hidden conversations: \(error)")
            }
        } catch {
            print("[DELETE] updateHiddenConversations failed: \(error)")
        }
    }

    /// Update favorites list on the backend
    func updateFavorites(_ favoriteIDs: [String]) async {
        guard isConfigured else { return }

        // Ensure we have a profile record
        if profileRecordID == nil {
            _ = await fetchUserProfile()
        }
        if profileRecordID == nil {
            _ = await createUserProfile()
        }
        guard let profileID = profileRecordID else { return }

        let document = """
        mutation UpdateUserProfile($input: UpdateUserProfileInput!) {
            updateUserProfile(input: $input) { id favoriteListingIDs }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "id": profileID,
                "favoriteListingIDs": favoriteIDs
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success:
                print("Favorites updated on backend")
            case .failure(let error):
                print("updateFavorites error: \(error)")
            }
        } catch {
            print("updateFavorites failed: \(error)")
        }
    }

    // MARK: - JSON Parsing Helpers

    private func parseListings(_ data: JSONValue) -> [Listing] {
        guard let items = data.value(at: "listListings")?.value(at: "items") else { return [] }
        guard case .array(let array) = items else { return [] }
        return array.compactMap { parseSingleListing($0) }
    }

    private func parseSingleListing(_ item: JSONValue) -> Listing? {
        guard
            let title = item.value(at: "title")?.stringValue,
            let desc = item.value(at: "description")?.stringValue,
            let subcategory = item.value(at: "subcategory")?.stringValue,
            let location = item.value(at: "location")?.stringValue,
            let neighborhood = item.value(at: "neighborhood")?.stringValue,
            let sellerID = item.value(at: "sellerID")?.stringValue,
            let sellerName = item.value(at: "sellerName")?.stringValue
        else { return nil }

        let id: UUID
        if let idStr = item.value(at: "id")?.stringValue {
            id = UUID(uuidString: idStr) ?? UUID()
        } else {
            id = UUID()
        }

        let price = item.value(at: "price")?.doubleValue
        let categoryStr = item.value(at: "category")?.stringValue ?? "FOR_SALE"
        let conditionStr = item.value(at: "condition")?.stringValue

        var imageKeys: [String] = []
        if let imgVal = item.value(at: "imageKeys"),
           case .array(let imgArr) = imgVal {
            imageKeys = imgArr.compactMap { $0.stringValue }
        }

        var postedDate = Date()
        if let dateStr = item.value(at: "createdAt")?.stringValue {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            postedDate = formatter.date(from: dateStr) ?? Date()
        }

        let statusStr = item.value(at: "listingStatus")?.stringValue
        let listingStatus: ListingStatus = {
            switch statusStr {
            case "SOLD": return .sold
            case "WITHDRAWN": return .withdrawn
            default: return .active
            }
        }()

        return Listing(
            id: id,
            title: title,
            description: desc,
            price: price,
            category: mapCategoryFromBackend(categoryStr),
            subcategory: subcategory,
            images: imageKeys,
            location: location,
            neighborhood: neighborhood,
            postedDate: postedDate,
            sellerID: sellerID,
            sellerName: sellerName,
            condition: conditionStr.flatMap { mapConditionFromBackend($0) },
            status: listingStatus
        )
    }

    private func parseConversations(_ data: JSONValue, currentUserID: String) -> [Conversation] {
        guard let items = data.value(at: "listConversations")?.value(at: "items") else { return [] }
        guard case .array(let array) = items else { return [] }
        return array.compactMap { item -> Conversation? in
            guard
                let idStr = item.value(at: "id")?.stringValue,
                let listingIDStr = item.value(at: "listingID")?.stringValue,
                let listingTitle = item.value(at: "listingTitle")?.stringValue,
                let buyerID = item.value(at: "buyerID")?.stringValue,
                let sellerID = item.value(at: "sellerID")?.stringValue
            else { return nil }

            let buyerName = item.value(at: "buyerName")?.stringValue ?? ""
            let sellerName = item.value(at: "sellerName")?.stringValue ?? ""
            let otherUserID = buyerID == currentUserID ? sellerID : buyerID
            // Use the stored profile name from backend
            let otherUserName = buyerID == currentUserID ? sellerName : buyerName


            var messages: [Message] = []
            if let msgItems = item.value(at: "messages")?.value(at: "items"),
               case .array(let msgArray) = msgItems {
                messages = msgArray.compactMap { msg -> Message? in
                    guard
                        let text = msg.value(at: "text")?.stringValue,
                        let senderID = msg.value(at: "senderID")?.stringValue
                    else { return nil }

                    var timestamp = Date()
                    if let dateStr = msg.value(at: "createdAt")?.stringValue {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        timestamp = formatter.date(from: dateStr) ?? Date()
                    }

                    let msgID: UUID
                    if let msgIDStr = msg.value(at: "id")?.stringValue {
                        msgID = UUID(uuidString: msgIDStr) ?? UUID()
                    } else {
                        msgID = UUID()
                    }

                    return Message(
                        id: msgID,
                        text: text,
                        timestamp: timestamp,
                        isFromCurrentUser: senderID == currentUserID,
                        isRead: msg.value(at: "isRead")?.booleanValue ?? false
                    )
                }.sorted { $0.timestamp < $1.timestamp }
            }

            var lastMessageDate = Date()
            if let dateStr = item.value(at: "lastMessageAt")?.stringValue {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                lastMessageDate = formatter.date(from: dateStr) ?? Date()
            }

            return Conversation(
                id: UUID(uuidString: idStr) ?? UUID(),
                listingID: UUID(uuidString: listingIDStr) ?? UUID(),
                listingTitle: listingTitle,
                listingImage: "photo",
                buyerID: buyerID,
                buyerName: buyerName,
                sellerID: sellerID,
                sellerName: sellerName,
                otherUserID: otherUserID,
                otherUserName: otherUserName.isEmpty ? otherUserID : otherUserName,
                messages: messages,
                lastMessageDate: lastMessageDate
            )
        }
    }

    // MARK: - Enum Mapping

    private func mapCategoryToBackend(_ cat: ListingCategory) -> String {
        switch cat {
        case .forSale: return "FOR_SALE"
        case .housing: return "HOUSING"
        case .jobs: return "JOBS"
        case .services: return "SERVICES"
        case .community: return "COMMUNITY"
        case .gigs: return "GIGS"
        }
    }

    private func mapCategoryFromBackend(_ str: String) -> ListingCategory {
        switch str {
        case "FOR_SALE": return .forSale
        case "HOUSING": return .housing
        case "JOBS": return .jobs
        case "SERVICES": return .services
        case "COMMUNITY": return .community
        case "GIGS": return .gigs
        default: return .forSale
        }
    }

    private func mapConditionToBackend(_ cond: ItemCondition) -> String {
        switch cond {
        case .new: return "NEW"
        case .likeNew: return "LIKE_NEW"
        case .good: return "GOOD"
        case .fair: return "FAIR"
        case .salvage: return "SALVAGE"
        }
    }

    private func mapConditionFromBackend(_ str: String) -> ItemCondition? {
        switch str {
        case "NEW": return .new
        case "LIKE_NEW": return .likeNew
        case "GOOD": return .good
        case "FAIR": return .fair
        case "SALVAGE": return .salvage
        default: return nil
        }
    }

    // MARK: - Device Token for Push Notifications

    func updateDeviceToken(_ token: String, platform: String) async {
        guard isConfigured else {
            print("[PUSH] updateDeviceToken: Amplify not configured")
            return
        }
        print("[PUSH] updateDeviceToken called with token=\(token.prefix(12))... platform=\(platform)")

        // Fetch or create profile
        var profile = await fetchUserProfile()
        print("[PUSH] fetchUserProfile returned: \(profile?.profileID ?? "nil")")

        if profile == nil {
            print("[PUSH] No profile found, creating one...")
            let newID = await createUserProfile()
            if let newID = newID {
                profile = (profileID: newID, favoriteIDs: [], hiddenConversationIDs: [])
                print("[PUSH] Created new profile: \(newID)")
            }
        }
        guard let profileID = profile?.profileID else {
            print("[PUSH] Cannot update device token: no profile ID")
            return
        }

        // Try to update the profile's device token
        let success = await updateProfileDeviceToken(profileID: profileID, token: token, platform: platform)
        if !success {
            print("[PUSH] Update failed for profile \(profileID)")
            // Re-fetch to find the correct profile instead of creating a new one
            self.profileRecordID = nil
            if let refetched = await fetchUserProfile() {
                if refetched.profileID != profileID {
                    print("[PUSH] Found different profile \(refetched.profileID), retrying...")
                    let retrySuccess = await updateProfileDeviceToken(profileID: refetched.profileID, token: token, platform: platform)
                    print("[PUSH] Retry: \(retrySuccess ? "SUCCESS" : "FAILED")")
                }
            } else {
                // Truly no profile exists — create one
                print("[PUSH] No profile exists at all, creating...")
                if let newID = await createUserProfile() {
                    let retrySuccess = await updateProfileDeviceToken(profileID: newID, token: token, platform: platform)
                    print("[PUSH] Created \(newID): \(retrySuccess ? "SUCCESS" : "FAILED")")
                }
            }
        }
    }

    private func updateProfileDeviceToken(profileID: String, token: String, platform: String) async -> Bool {
        let document = """
        mutation UpdateUserProfile($input: UpdateUserProfileInput!) {
            updateUserProfile(input: $input) {
                id
                deviceToken
                platform
            }
        }
        """
        let variables: [String: Any] = [
            "input": [
                "id": profileID,
                "deviceToken": token,
                "platform": platform
            ]
        ]
        do {
            let request = GraphQLRequest<JSONValue>(document: document, variables: variables, responseType: JSONValue.self)
            let result = try await Amplify.API.mutate(request: request)
            switch result {
            case .success(let data):
                let savedToken = data.value(at: "updateUserProfile")?.value(at: "deviceToken")?.stringValue ?? "nil"
                print("[PUSH] Device token saved to profile \(profileID)! token=\(savedToken.prefix(12))...")
                return true
            case .failure(let error):
                print("[PUSH] updateProfile \(profileID) FAILED: \(error)")
                return false
            }
        } catch {
            print("[PUSH] updateProfile \(profileID) exception: \(error)")
            return false
        }
    }
}

// MARK: - Error for unconfigured Amplify
struct AmplifyNotConfiguredError: LocalizedError {
    var errorDescription: String? {
        "Amplify is not configured. Please add amplify_outputs.json to your Xcode project target."
    }
}
