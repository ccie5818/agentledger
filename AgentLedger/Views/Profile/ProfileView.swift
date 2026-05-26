import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var selectedTab: ProfileTab = .listings
    @State private var showEditProfile = false

    enum ProfileTab: String, CaseIterable {
        case listings = "My Listings"
        case favorites = "Favorites"
        case settings = "Settings"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Profile")
                            .font(.largeTitle.weight(.bold))
                        Spacer()
                        Button {
                            Task { await amplifyService.signOut() }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.title3)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color(.systemGroupedBackground))
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))

                    profileHeader
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowInsets(EdgeInsets())

                    statsRow
                        .listRowBackground(Color(.systemGroupedBackground))
                        .listRowInsets(EdgeInsets())

                    Picker("Tab", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color(.systemGroupedBackground))
                }

                // Tab content
                switch selectedTab {
                case .listings:
                    myListingsSection
                case .favorites:
                    favoritesContent
                case .settings:
                    settingsContent
                    Section {
                        Button(role: .destructive) {
                            Task { await amplifyService.signOut() }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                                Spacer()
                            }
                            .font(.body.weight(.medium))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .confirmationDialog(
                "Delete Listing",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let listing = listingToDelete {
                        viewModel.deleteListing(listing.id, amplifyService: amplifyService)
                    }
                    listingToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    listingToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete \"\(listingToDelete?.title ?? "")\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Profile Header
    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(viewModel.currentUser.avatarInitials)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text(viewModel.currentUser.name)
                    .font(.title3.weight(.semibold))
                if !viewModel.currentUser.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                        Text(viewModel.currentUser.location)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if !viewModel.currentUser.email.isEmpty {
                    Text(viewModel.currentUser.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Member since \(memberSinceText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Button {
                showEditProfile = true
            } label: {
                Text("Edit Profile")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }

    private var memberSinceText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: viewModel.currentUser.joinDate)
    }

    // MARK: - Stats
    private var statsRow: some View {
        HStack(spacing: 0) {
            statItem(value: "\(viewModel.myListings.filter { $0.status == .active }.count)", label: "Active")
            statItem(value: "\(viewModel.myListings.filter { $0.status == .sold }.count)", label: "Sold")
            Divider().frame(height: 30)
            statItem(value: "\(viewModel.currentUser.totalSold)", label: "Sold")
            Divider().frame(height: 30)
            statItem(value: "\(viewModel.favoriteListings.count)", label: "Saved")
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - My Listings
    @State private var listingToDelete: Listing?
    @State private var showDeleteConfirm = false
    @State private var listingToWithdraw: Listing?
    @State private var showWithdrawConfirm = false

    @ViewBuilder
    private var myListingsSection: some View {
        if viewModel.myListings.isEmpty {
            Section {
                emptySection(
                    icon: "tag",
                    title: "No listings yet",
                    subtitle: "Tap the + tab to create your first listing"
                )
            }
        } else {
            Section("My Listings") {
                ForEach(viewModel.myListings) { listing in
                    NavigationLink(value: listing) {
                        ListingRowView(listing: listing)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            listingToDelete = listing
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            listingToWithdraw = listing
                            showWithdrawConfirm = true
                        } label: {
                            Label("Withdraw", systemImage: "xmark.circle")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if listing.status == .sold {
                            Button {
                                viewModel.reactivateListing(listing.id, amplifyService: amplifyService)
                            } label: {
                                Label("Relist", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                viewModel.markAsSold(listing.id, amplifyService: amplifyService)
                            } label: {
                                Label("Sold", systemImage: "checkmark.seal.fill")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
            .confirmationDialog(
                "Withdraw Listing",
                isPresented: $showWithdrawConfirm,
                titleVisibility: .visible
            ) {
                Button("Withdraw", role: .destructive) {
                    if let listing = listingToWithdraw {
                        viewModel.withdrawListing(listing.id, amplifyService: amplifyService)
                    }
                    listingToWithdraw = nil
                }
                Button("Cancel", role: .cancel) { listingToWithdraw = nil }
            } message: {
                Text("This listing will be hidden from buyers.")
            }
        }
    }

    // MARK: - Favorites
    @ViewBuilder
    private var favoritesContent: some View {
        if viewModel.favoriteListings.isEmpty {
            Section {
                emptySection(
                    icon: "heart",
                    title: "No favorites yet",
                    subtitle: "Tap the heart icon on listings to save them here"
                )
            }
        } else {
            Section("Favorites") {
                ForEach(viewModel.favoriteListings) { listing in
                    NavigationLink(value: listing) {
                        ListingRowView(listing: listing)
                    }
                }
            }
        }
    }

    // MARK: - Settings
    private var settingsContent: some View {
        Section("Settings") {
            settingsRow(icon: "bell.fill", title: "Notifications", color: .red)
            settingsRow(icon: "lock.fill", title: "Privacy", color: .blue)
            settingsRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .green)
            settingsRow(icon: "doc.text.fill", title: "Terms of Service", color: .gray)
            settingsRow(icon: "info.circle.fill", title: "About", color: .purple)
        }
    }

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func emptySection(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Edit Profile View
struct EditProfileView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var location: String = ""
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    enum Field { case name, email, phone, location }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Avatar
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(initials)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 80, height: 80)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Personal Info") {
                    HStack {
                        Label("Name", systemImage: "person.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        TextField("Your name", text: $name)
                            .focused($focusedField, equals: .name)
                        if !name.isEmpty {
                            Button { name = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Label("Email", systemImage: "envelope.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        TextField("Email address", text: $email)
                            .focused($focusedField, equals: .email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                        if !email.isEmpty {
                            Button { email = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Label("Phone", systemImage: "phone.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        TextField("Phone number", text: $phone)
                            .focused($focusedField, equals: .phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                        if !phone.isEmpty {
                            Button { phone = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Location") {
                    HStack {
                        Label("City", systemImage: "mappin.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        TextField("City, State", text: $location)
                            .focused($focusedField, equals: .location)
                        if !location.isEmpty {
                            Button { location = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveProfile()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .clearDoneToolbar(
                onClear: {
                    switch focusedField {
                    case .name: name = ""
                    case .email: email = ""
                    case .phone: phone = ""
                    case .location: location = ""
                    case .none: break
                    }
                },
                onDone: { focusedField = nil }
            )
            .onAppear {
                name = viewModel.currentUser.name
                email = viewModel.currentUser.email
                phone = viewModel.currentUser.phone
                location = viewModel.currentUser.location
            }
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }

    private func saveProfile() {
        isSaving = true
        Task {
            if amplifyService.isConfigured {
                await viewModel.saveProfileToBackend(amplifyService, name: name, email: email, phone: phone, location: location)
            } else {
                await MainActor.run {
                    viewModel.currentUser.name = name
                    viewModel.currentUser.email = email
                    viewModel.currentUser.phone = phone
                    viewModel.currentUser.location = location
                }
            }
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}
