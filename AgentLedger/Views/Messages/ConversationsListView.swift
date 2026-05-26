import SwiftUI

struct ConversationsListView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @Binding var pendingConversationID: UUID?
    @State private var navigationPath = NavigationPath()
    @State private var isEditing = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteSelectedConfirm = false
    @State private var showDeleteAllConfirm = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("Messages")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                    if !viewModel.conversations.isEmpty {
                        Button(isEditing ? "Done" : "Edit") {
                            withAnimation {
                                isEditing.toggle()
                                if !isEditing { selectedIDs.removeAll() }
                            }
                        }
                        .font(.body)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Edit toolbar
                if isEditing && !viewModel.conversations.isEmpty {
                    editToolbar
                }

                if viewModel.conversations.isEmpty {
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                } else if isEditing {
                    List {
                        ForEach(sortedConversations) { conversation in
                            editableRow(conversation)
                        }
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        ForEach(sortedConversations) { conversation in
                            Button {
                                navigationPath.append(conversation)
                            } label: {
                                ConversationRowView(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteConversation(conversation.id, amplifyService: amplifyService)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await viewModel.refreshConversations(amplifyService)
                    }
                }
            }
            .onAppear {
                // Refresh every time the Messages tab appears
                if amplifyService.isConfigured {
                    Task {
                        await viewModel.refreshConversations(amplifyService)
                    }
                }
                // Check if we need to auto-navigate to a conversation from notification
                navigateToPendingIfNeeded()
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                // Auto-refresh conversations list every 10 seconds
                if amplifyService.isConfigured {
                    Task {
                        await viewModel.refreshConversations(amplifyService)
                    }
                }
            }
            .onChange(of: viewModel.conversations) { _, _ in
                // When conversations update, check if we have a pending navigation
                navigateToPendingIfNeeded()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .confirmationDialog(
                "Delete Selected",
                isPresented: $showDeleteSelectedConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete \(selectedIDs.count) Conversation\(selectedIDs.count == 1 ? "" : "s")", role: .destructive) {
                    for id in selectedIDs {
                        viewModel.deleteConversation(id, amplifyService: amplifyService)
                    }
                    selectedIDs.removeAll()
                    if viewModel.conversations.isEmpty { isEditing = false }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This cannot be undone.")
            }
            .confirmationDialog(
                "Delete All Messages",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    let allIDs = viewModel.conversations.map { $0.id }
                    for id in allIDs {
                        viewModel.deleteConversation(id, amplifyService: amplifyService)
                    }
                    selectedIDs.removeAll()
                    isEditing = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("All conversations will be permanently deleted.")
            }
        }
    }

    // MARK: - Edit Toolbar

    private var editToolbar: some View {
        HStack(spacing: 12) {
            Button {
                if selectedIDs.count == sortedConversations.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(sortedConversations.map { $0.id })
                }
            } label: {
                Text(selectedIDs.count == sortedConversations.count ? "Deselect All" : "Select All")
                    .font(.subheadline)
            }

            Spacer()

            Button(role: .destructive) {
                showDeleteSelectedConfirm = true
            } label: {
                Text("Delete")
                    .font(.subheadline.weight(.medium))
            }
            .disabled(selectedIDs.isEmpty)

            Button(role: .destructive) {
                showDeleteAllConfirm = true
            } label: {
                Text("Delete All")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Editable Row

    private func editableRow(_ conversation: Conversation) -> some View {
        Button {
            if selectedIDs.contains(conversation.id) {
                selectedIDs.remove(conversation.id)
            } else {
                selectedIDs.insert(conversation.id)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedIDs.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(conversation.id) ? Color.accentColor : .secondary)

                ConversationRowView(conversation: conversation)
            }
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func navigateToPendingIfNeeded() {
        guard let targetID = pendingConversationID else { return }
        // Find the matching conversation
        if let conversation = viewModel.conversations.first(where: { $0.id == targetID }) {
            print("[PUSH-NAV] Auto-navigating to conversation \(targetID)")
            pendingConversationID = nil
            // Push onto navigation stack after a brief delay to let the view settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                navigationPath.append(conversation)
            }
        }
    }

    private var sortedConversations: [Conversation] {
        viewModel.conversations.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.title3.weight(.medium))
            Text("When you contact a seller or receive inquiries, your conversations will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Conversation Row
struct ConversationRowView: View {
    let conversation: Conversation
    @EnvironmentObject var viewModel: AppViewModel
    var amplifyService: AmplifyService? = AmplifyService.shared

    /// Always read the live conversation from the viewModel so read-status updates are reflected
    private var liveConversation: Conversation {
        viewModel.conversations.first { $0.id == conversation.id } ?? conversation
    }

    private var relatedListing: Listing? {
        viewModel.listings.first { $0.id == conversation.listingID }
    }

    private var otherUserRoleLabel: String {
        // Use the resolved profile name (ViewModel resolves IDs to names)
        if conversation.otherUserName != conversation.otherUserID {
            return conversation.otherUserName
        }
        // Fallback: show role label while name is being resolved
        return viewModel.myListingIDs.contains(conversation.listingID) ? "Buyer" : "Seller"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Listing thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.1))
                if let listing = relatedListing, !listing.localImages.isEmpty {
                    let idx = min(listing.coverImageIndex, listing.localImages.count - 1)
                    Image(uiImage: listing.localImages[max(0, idx)])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let listing = relatedListing, !listing.images.isEmpty,
                          let service = amplifyService, service.isConfigured {
                    let idx = min(listing.coverImageIndex, listing.images.count - 1)
                    S3ImageView(imageKey: listing.images[max(0, idx)], amplifyService: service)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherUserRoleLabel)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(formatDate(liveConversation.lastMessageDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(conversation.listingTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(liveConversation.lastMessagePreview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if liveConversation.unreadCount > 0 {
                        Text("\(liveConversation.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}
