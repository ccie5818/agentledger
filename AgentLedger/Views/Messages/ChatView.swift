import SwiftUI

struct ChatView: View {
    let conversation: Conversation
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var messageText = ""
    @State private var messageToDelete: Message?
    @State private var showDeleteMessageConfirm = false
    @State private var showDeleteConvoConfirm = false
    @State private var isSending = false
    @Environment(\.dismiss) var dismiss
    @FocusState private var isInputFocused: Bool

    var currentConversation: Conversation? {
        viewModel.conversations.first { $0.id == conversation.id }
    }

    var relatedListing: Listing? {
        viewModel.listings.first { $0.id == conversation.listingID }
    }

    private var otherUserRoleLabel: String {
        if let convo = currentConversation, convo.otherUserName != convo.otherUserID {
            return convo.otherUserName
        }
        if conversation.otherUserName != conversation.otherUserID {
            return conversation.otherUserName
        }
        return viewModel.myListingIDs.contains(conversation.listingID) ? "Buyer" : "Seller"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Listing header
            listingBanner

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(currentConversation?.messages ?? []) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = message.text
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    Button(role: .destructive) {
                                        messageToDelete = message
                                        showDeleteMessageConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
                .onChange(of: currentConversation?.messages.count) { _, _ in
                    // Auto-scroll when new messages arrive
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }

            // Input bar
            inputBar
        }
        .navigationTitle(otherUserRoleLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeleteConvoConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .clearDoneToolbar(
            onClear: { messageText = "" },
            onDone: { isInputFocused = false }
        )
        .onAppear {
            viewModel.markConversationRead(conversation.id, amplifyService: amplifyService)
            // Fetch latest messages from backend
            if amplifyService.isConfigured {
                Task {
                    await viewModel.refreshMessages(amplifyService, conversationID: conversation.id)
                }
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            // Poll for new messages while chat is open — skip when keyboard is up to avoid lag
            if amplifyService.isConfigured && !isInputFocused {
                Task {
                    await viewModel.refreshMessages(amplifyService, conversationID: conversation.id)
                }
            }
        }
        .confirmationDialog(
            "Delete Message",
            isPresented: $showDeleteMessageConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let msg = messageToDelete {
                    viewModel.deleteMessage(msg.id, in: conversation.id, amplifyService: amplifyService)
                }
                messageToDelete = nil
            }
            Button("Cancel", role: .cancel) { messageToDelete = nil }
        } message: {
            Text("This message will be deleted.")
        }
        .confirmationDialog(
            "Delete Conversation",
            isPresented: $showDeleteConvoConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteConversation(conversation.id, amplifyService: amplifyService)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This entire conversation will be deleted. This cannot be undone.")
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = currentConversation?.messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }

    // MARK: - Listing Banner
    private var listingBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1))
                if let listing = relatedListing, !listing.localImages.isEmpty {
                    let idx = min(listing.coverImageIndex, listing.localImages.count - 1)
                    Image(uiImage: listing.localImages[max(0, idx)])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let listing = relatedListing, !listing.images.isEmpty,
                          amplifyService.isConfigured {
                    let idx = min(listing.coverImageIndex, listing.images.count - 1)
                    S3ImageView(imageKey: listing.images[max(0, idx)], amplifyService: amplifyService)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.listingTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let listing = relatedListing {
                    Text(listing.formattedPrice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if relatedListing != nil {
                NavigationLink(value: relatedListing!) {
                    Text("View")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    // MARK: - Input Bar
    private var inputBar: some View {
        HStack(spacing: 10) {
            HStack {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                if !messageText.isEmpty {
                    Button { messageText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Button {
                guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let text = messageText
                messageText = ""
                isSending = true
                if amplifyService.isConfigured {
                    Task {
                        await viewModel.sendMessageOnBackend(amplifyService, in: conversation.id, text: text)
                        isSending = false
                    }
                } else {
                    viewModel.sendMessage(in: conversation.id, text: text)
                    isSending = false
                }
            } label: {
                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(messageText.isEmpty ? Color(.systemGray4) : Color.accentColor)
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Message Bubble
struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isFromCurrentUser { Spacer(minLength: 60) }

            VStack(alignment: message.isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(message.isFromCurrentUser ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(message.isFromCurrentUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isFromCurrentUser { Spacer(minLength: 60) }
        }
    }
}
