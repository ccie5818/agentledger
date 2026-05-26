import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .browse
    @State private var showPostListing = false
    @State private var pendingConversationID: UUID?

    enum AppTab: Hashable {
        case browse, messages, post, saved, profile
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Browse", systemImage: "magnifyingglass")
                }
                .tag(AppTab.browse)

            ConversationsListView(pendingConversationID: $pendingConversationID)
                .tabItem {
                    Label("Messages", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(AppTab.messages)
                .badge(viewModel.unreadMessageCount)

            // Post button (opens sheet)
            Text("")
                .tabItem {
                    Label("Sell", systemImage: "plus.circle.fill")
                }
                .tag(AppTab.post)

            SavedView()
                .tabItem {
                    Label("Saved", systemImage: "heart")
                }
                .tag(AppTab.saved)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
                .tag(AppTab.profile)
        }
        .tint(.accentColor)
        .environmentObject(viewModel)
        .environmentObject(amplifyService)
        .onChange(of: selectedTab) {
            if selectedTab == .post {
                showPostListing = true
                selectedTab = .browse
            }
        }
        .sheet(isPresented: $showPostListing) {
            PostListingView()
                .environmentObject(viewModel)
                .environmentObject(amplifyService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversation)) { notification in
            if let conversationID = notification.userInfo?["conversationID"] as? String,
               let uuid = UUID(uuidString: conversationID) {
                print("[PUSH-NAV] Received .openConversation for \(conversationID)")
                selectedTab = .messages
                pendingConversationID = uuid
                Task {
                    await viewModel.refreshConversations(amplifyService)
                }
            }
        }
        .onAppear {
            PushNotificationManager.shared.clearBadge()
            // Check for pending notification from cold launch
            checkPendingNotification()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App came to foreground — refresh messages from backend
                PushNotificationManager.shared.clearBadge()
                if amplifyService.isConfigured {
                    Task {
                        await viewModel.refreshConversations(amplifyService)
                    }
                }
                // Check if we were opened from a notification
                checkPendingNotification()
            }
        }
    }

    private func checkPendingNotification() {
        let pushManager = PushNotificationManager.shared
        if let conversationID = pushManager.pendingConversationID,
           let uuid = UUID(uuidString: conversationID) {
            print("[PUSH-NAV] Processing pending notification for conversation: \(conversationID)")
            pushManager.pendingConversationID = nil
            selectedTab = .messages
            pendingConversationID = uuid
            // Wait for backend to load, then refresh and navigate
            Task {
                // First wait for initial backend load to complete
                for attempt in 1...15 {
                    if viewModel.isBackendLoaded {
                        print("[PUSH-NAV] Backend loaded, checking for conversation (attempt \(attempt))")
                        break
                    }
                    print("[PUSH-NAV] Waiting for backend load... attempt \(attempt)")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                // Now refresh conversations to get the latest (message might have arrived after initial load)
                for attempt in 1...5 {
                    if amplifyService.isConfigured && amplifyService.currentUserID != nil {
                        await viewModel.refreshConversations(amplifyService)
                        let found = viewModel.conversations.contains { $0.id == uuid }
                        print("[PUSH-NAV] After refresh attempt \(attempt): \(viewModel.conversations.count) convos, target found=\(found)")
                        if found { break }
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                // Re-set pendingConversationID to trigger navigation in ConversationsListView
                await MainActor.run {
                    pendingConversationID = uuid
                }
            }
        }
    }
}

// MARK: - Saved View (wrapper for favorites)
struct SavedView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var selectedFilter: SavedFilter = .all

    enum SavedFilter: String, CaseIterable {
        case all = "All"
        case forSale = "For Sale"
        case housing = "Housing"
        case jobs = "Jobs"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Saved")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SavedFilter.allCases, id: \.self) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(selectedFilter == filter ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(selectedFilter == filter ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                if filteredFavorites.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "heart")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No saved listings")
                            .font(.title3.weight(.medium))
                        Text("Tap the heart icon on any listing to save it for later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredFavorites) { listing in
                                NavigationLink(value: listing) {
                                    ListingRowView(listing: listing)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
        }
    }

    private var filteredFavorites: [Listing] {
        let favorites = viewModel.favoriteListings
        switch selectedFilter {
        case .all: return favorites
        case .forSale: return favorites.filter { $0.category == .forSale }
        case .housing: return favorites.filter { $0.category == .housing }
        case .jobs: return favorites.filter { $0.category == .jobs }
        }
    }
}
