import SwiftUI

struct HomeView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @State private var showFilters = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Title
                    HStack {
                        Text("Marketplace")
                            .font(.largeTitle.weight(.bold))
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    // Search Bar
                    searchBar

                    // Category Pills
                    categoryScroller

                    // Active filter chips
                    if !viewModel.searchFilter.categories.isEmpty || viewModel.searchFilter.condition != nil {
                        activeFilters
                    }

                    // Results count
                    HStack {
                        Text("\(viewModel.filteredListings.count) listings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            ForEach(SortOption.allCases) { option in
                                Button {
                                    viewModel.searchFilter.sortBy = option
                                } label: {
                                    HStack {
                                        Text(option.rawValue)
                                        if viewModel.searchFilter.sortBy == option {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(viewModel.searchFilter.sortBy.rawValue)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Listings Grid
                    LazyVStack(spacing: 1) {
                        ForEach(viewModel.filteredListings) { listing in
                            NavigationLink(value: listing) {
                                ListingRowView(listing: listing)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if viewModel.filteredListings.isEmpty {
                        emptyState
                    }
                }
            }
            .refreshable {
                await viewModel.refreshListings(amplifyService)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .clearDoneToolbar(
                onClear: { viewModel.searchFilter.query = "" },
                onDone: { isSearchFocused = false }
            )
            .navigationDestination(for: Listing.self) { listing in
                ListingDetailView(listing: listing)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
                    .environmentObject(viewModel)
                    .environmentObject(amplifyService)
            }
            .sheet(isPresented: $showFilters) {
                FilterView()
                    .environmentObject(viewModel)
            }
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search marketplace...", text: $viewModel.searchFilter.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !viewModel.searchFilter.query.isEmpty {
                    Button {
                        viewModel.searchFilter.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                showFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Category Scroller
    private var categoryScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" pill
                Button {
                    viewModel.searchFilter.categories.removeAll()
                    viewModel.searchFilter.subcategory = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2.fill")
                        Text("All")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(viewModel.searchFilter.categories.isEmpty ? Color.accentColor : Color(.systemGray5))
                    .foregroundStyle(viewModel.searchFilter.categories.isEmpty ? .white : .primary)
                    .clipShape(Capsule())
                }

                ForEach(ListingCategory.allCases) { category in
                    Button {
                        if viewModel.searchFilter.categories.contains(category) {
                            viewModel.searchFilter.categories.remove(category)
                        } else {
                            viewModel.searchFilter.categories.insert(category)
                        }
                        viewModel.searchFilter.subcategory = nil
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                            Text(category.rawValue)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(viewModel.searchFilter.categories.contains(category) ? category.color : Color(.systemGray5))
                        .foregroundStyle(viewModel.searchFilter.categories.contains(category) ? .white : .primary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Active Filters
    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.searchFilter.categories).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { category in
                    filterChip(label: category.rawValue) {
                        viewModel.searchFilter.categories.remove(category)
                    }
                }
                if let condition = viewModel.searchFilter.condition {
                    filterChip(label: condition.rawValue) {
                        viewModel.searchFilter.condition = nil
                    }
                }
                if viewModel.searchFilter.minPrice != nil || viewModel.searchFilter.maxPrice != nil {
                    let priceLabel = priceFilterLabel()
                    filterChip(label: priceLabel) {
                        viewModel.searchFilter.minPrice = nil
                        viewModel.searchFilter.maxPrice = nil
                    }
                }

                Button {
                    viewModel.clearFilters()
                } label: {
                    Text("Clear all")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 4)
    }

    private func filterChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.accentColor.opacity(0.15))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }

    private func priceFilterLabel() -> String {
        let min = viewModel.searchFilter.minPrice.map { "$\(Int($0))" } ?? ""
        let max = viewModel.searchFilter.maxPrice.map { "$\(Int($0))" } ?? ""
        if !min.isEmpty && !max.isEmpty { return "\(min) - \(max)" }
        if !min.isEmpty { return "\(min)+" }
        return "Up to \(max)"
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No listings found")
                .font(.title3.weight(.medium))
            Text("Try adjusting your filters or search terms")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Clear Filters") {
                viewModel.clearFilters()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - Listing Row View
struct ListingRowView: View {
    let listing: Listing
    @EnvironmentObject var viewModel: AppViewModel
    var amplifyService: AmplifyService? = AmplifyService.shared

    private var imageSize: CGFloat {
        UIScreen.main.bounds.width < 375 ? 80 : 100
    }

    private var isSold: Bool { listing.status == .sold }

    var body: some View {
        HStack(spacing: 12) {
            // Listing image with SOLD overlay
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(listing.category.color.opacity(0.15))
                if !listing.localImages.isEmpty {
                    let idx = min(listing.coverImageIndex, listing.localImages.count - 1)
                    Image(uiImage: listing.localImages[max(0, idx)])
                        .resizable()
                        .scaledToFill()
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if !listing.images.isEmpty,
                          let service = amplifyService, service.isConfigured {
                    let idx = min(listing.coverImageIndex, listing.images.count - 1)
                    S3ImageView(imageKey: listing.images[max(0, idx)], amplifyService: service)
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: listing.category.icon)
                        .font(.title2)
                        .foregroundStyle(listing.category.color)
                }

                // SOLD overlay on image
                if isSold {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.45))
                    Text("SOLD")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .frame(width: imageSize, height: imageSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(listing.formattedPrice)
                        .font(.headline)
                        .foregroundColor(isSold ? .secondary : (listing.price == 0 ? .green : .primary))
                    if isSold {
                        Text("SOLD")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                    Text(listing.neighborhood)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    if let condition = listing.condition {
                        Text(condition.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(listing.timeAgo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isSold ? 0.6 : 1.0)

            // Favorite button
            Button {
                viewModel.toggleFavorite(listing, amplifyService: amplifyService)
            } label: {
                Image(systemName: viewModel.isFavorited(listing) ? "heart.fill" : "heart")
                    .foregroundStyle(viewModel.isFavorited(listing) ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(.systemBackground))
    }
}
