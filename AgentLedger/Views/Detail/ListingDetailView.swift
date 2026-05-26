import SwiftUI
import MapKit

struct ListingDetailView: View {
    let listing: Listing
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var showContactSheet = false
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var showSoldConfirm = false
    @State private var showWithdrawConfirm = false
    @State private var showEditPhotos = false
    @Environment(\.dismiss) var dismiss
    @State private var messageText = "Hi! Is this still available?"
    @State private var messageSent = false
    @State private var isSending = false
    @State private var navigateToConversation: Conversation?
    @FocusState private var isMessageFocused: Bool

    /// Find existing conversation for this listing where current user is the buyer
    private var existingConversation: Conversation? {
        guard let userID = amplifyService.currentUserID else { return nil }
        return viewModel.conversations.first(where: {
            $0.listingID == listing.id && $0.buyerID == userID
        })
    }

    private var heroHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight < 700 ? 200 : (screenHeight < 850 ? 250 : 300)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Listing image
                ZStack {
                    Rectangle()
                        .fill(listing.category.color.opacity(0.12))
                    if !liveListing.localImages.isEmpty {
                        let idx = min(liveListing.coverImageIndex, liveListing.localImages.count - 1)
                        Image(uiImage: liveListing.localImages[max(0, idx)])
                            .resizable()
                            .scaledToFill()
                            .frame(height: heroHeight)
                            .clipped()
                    } else if !liveListing.images.isEmpty,
                              amplifyService.isConfigured {
                        let idx = min(liveListing.coverImageIndex, liveListing.images.count - 1)
                        S3ImageView(imageKey: liveListing.images[max(0, idx)], amplifyService: amplifyService)
                            .frame(height: heroHeight)
                            .clipped()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: listing.category.icon)
                                .font(.system(size: 60))
                                .foregroundStyle(listing.category.color)
                            Text("Photo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // SOLD overlay on hero image
                    if liveListing.status == .sold {
                        Rectangle()
                            .fill(Color.black.opacity(0.4))
                        Text("SOLD")
                            .font(.largeTitle.weight(.black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }

                    // Edit photos button for seller
                    if isOwnListing && liveListing.status != .sold {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Button {
                                    showEditPhotos = true
                                } label: {
                                    Label("Edit Photos", systemImage: "camera.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                }
                                .padding(12)
                            }
                        }
                    }
                }
                .frame(height: heroHeight)

                VStack(alignment: .leading, spacing: 16) {
                    // Title & Price
                    VStack(alignment: .leading, spacing: 6) {
                        Text(listing.formattedPrice)
                            .font(.title.weight(.bold))
                            .foregroundStyle(listing.price == 0 ? .green : .primary)

                        Text(listing.title)
                            .font(.title3.weight(.semibold))

                        HStack(spacing: 12) {
                            Label(listing.neighborhood, systemImage: "mappin")
                            Label(listing.timeAgo, systemImage: "clock")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Condition & Category tags
                    HStack(spacing: 8) {
                        if let condition = listing.condition {
                            tagView(label: condition.rawValue, color: .blue)
                        }
                        tagView(label: listing.category.rawValue, color: listing.category.color)
                        tagView(label: listing.subcategory, color: .gray)
                    }

                    Divider()

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(listing.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }

                    Divider()

                    // Seller info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Seller")
                            .font(.headline)

                        HStack(spacing: 12) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.2))
                                Text(String(listing.sellerName.prefix(1)))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(listing.sellerName)
                                    .font(.body.weight(.medium))
                                Text(listing.location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if !isOwnListing {
                                Button {
                                    showContactSheet = true
                                } label: {
                                    Text("Message")
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.accentColor)
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Divider()

                    // Location map
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Location")
                            .font(.headline)

                        let coord = SampleData.neighborhoodCoordinates[listing.neighborhood] ?? SampleData.defaultCoordinate
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                        ))), interactionModes: [.zoom, .pan]) {
                            Marker(listing.neighborhood, coordinate: coord)
                        }
                        .frame(height: UIScreen.main.bounds.height < 700 ? 130 : 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text(listing.neighborhood + ", San Mateo, CA")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Safety tips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Safety Tips")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            safetyTip(icon: "person.2.fill", text: "Meet in a public place")
                            safetyTip(icon: "eye.fill", text: "Check the item before paying")
                            safetyTip(icon: "banknote.fill", text: "Pay only after inspecting")
                            safetyTip(icon: "exclamationmark.shield.fill", text: "Report suspicious listings")
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    viewModel.toggleFavorite(listing, amplifyService: amplifyService)
                } label: {
                    Image(systemName: viewModel.isFavorited(listing) ? "heart.fill" : "heart")
                        .foregroundStyle(viewModel.isFavorited(listing) ? .red : .primary)
                }

                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showContactSheet) {
            contactSheet
                .environmentObject(viewModel)
                .environmentObject(amplifyService)
        }
        .sheet(isPresented: $showEditPhotos) {
            EditPhotosView(listing: listing)
                .environmentObject(viewModel)
                .environmentObject(amplifyService)
        }
    }

    /// Live listing from the viewModel so status updates are reflected immediately
    private var liveListing: Listing {
        viewModel.listings.first { $0.id == listing.id } ?? listing
    }

    private var isOwnListing: Bool {
        viewModel.myListingIDs.contains(listing.id)
    }

    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(listing.formattedPrice)
                        .font(.subheadline.weight(.bold))
                    if liveListing.status == .sold {
                        Text("SOLD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                Text(listing.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(0)

            Spacer(minLength: 8)

            if !isOwnListing {
                if liveListing.status == .sold {
                    Text("SOLD")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .clipShape(Capsule())
                } else if let existing = existingConversation {
                    NavigationLink(value: existing) {
                        Text("View Conversation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                    .layoutPriority(1)
                } else {
                    Button {
                        showContactSheet = true
                    } label: {
                        Text("Contact Seller")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .layoutPriority(1)
                }
            } else {
                // Seller actions
                if liveListing.status == .sold {
                    Button {
                        viewModel.reactivateListing(listing.id, amplifyService: amplifyService)
                    } label: {
                        Label("Relist", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        showSoldConfirm = true
                    } label: {
                        Label("Sold", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    showWithdrawConfirm = true
                } label: {
                    Label("Withdraw", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }

                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "Mark as Sold",
            isPresented: $showSoldConfirm,
            titleVisibility: .visible
        ) {
            Button("Mark as Sold") {
                viewModel.markAsSold(listing.id, amplifyService: amplifyService)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This listing will be shown as sold to buyers.")
        }
        .confirmationDialog(
            "Withdraw Listing",
            isPresented: $showWithdrawConfirm,
            titleVisibility: .visible
        ) {
            Button("Withdraw", role: .destructive) {
                viewModel.withdrawListing(listing.id, amplifyService: amplifyService)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This listing will be hidden from buyers. You can relist it later from your profile.")
        }
        .confirmationDialog(
            "Delete Listing",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.deleteListing(listing.id, amplifyService: amplifyService)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to permanently delete \"\(listing.title)\"? This cannot be undone.")
        }
    }

    // MARK: - Contact Sheet
    private var contactSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Listing preview
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(listing.category.color.opacity(0.15))
                            Image(systemName: listing.category.icon)
                                .foregroundStyle(listing.category.color)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading) {
                            Text(listing.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(listing.formattedPrice)
                                .font(.headline)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Quick replies
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick replies")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickReplies, id: \.self) { reply in
                                    Button {
                                        messageText = reply
                                    } label: {
                                        Text(reply)
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(messageText == reply ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
                                            .foregroundStyle(messageText == reply ? Color.accentColor : .primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Message input
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topTrailing) {
                            TextEditor(text: $messageText)
                                .focused($isMessageFocused)
                                .frame(minHeight: 60, maxHeight: 100)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            if !messageText.isEmpty {
                                Button { messageText = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .padding(12)
                            }
                        }
                    }

                    if messageSent {
                        Label("Message sent!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body.weight(.medium))
                    }

                    Button {
                        isSending = true
                        Task {
                            if amplifyService.isConfigured {
                                _ = await viewModel.startConversationOnBackend(amplifyService, for: listing, initialMessage: messageText)
                            } else {
                                _ = viewModel.startConversation(for: listing, initialMessage: messageText)
                            }
                            await MainActor.run {
                                isSending = false
                                messageSent = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showContactSheet = false
                                    messageSent = false
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if isSending {
                                ProgressView().tint(.white)
                            }
                            Text(isSending ? "Sending..." : "Send Message")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(messageText.isEmpty || isSending ? Color.gray : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(messageText.isEmpty || isSending)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Contact \(listing.sellerName)")
            .navigationBarTitleDisplayMode(.inline)
            .clearDoneToolbar(
                onClear: { messageText = "" },
                onDone: { isMessageFocused = false }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContactSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var quickReplies: [String] {
        [
            "Hi! Is this still available?",
            "What's your lowest price?",
            "Can I see it today?",
            "Is the price negotiable?"
        ]
    }

    private func tagView(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func safetyTip(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
