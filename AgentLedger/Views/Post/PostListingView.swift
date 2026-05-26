import SwiftUI
import MapKit

struct PostListingView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priceText = ""
    @State private var isFree = false
    @State private var selectedCategory: ListingCategory = .forSale
    @State private var selectedSubcategory: String = ListingCategory.forSale.subcategories.first ?? ""
    @State private var selectedCondition: ItemCondition = .good
    @State private var neighborhood = ""
    @State private var showSuccessAlert = false
    @State private var currentStep = 0
    @State private var selectedImages: [UIImage] = []
    @State private var coverImageIndex = 0
    @State private var isPosting = false
    @State private var visibilityRadius = 25
    @FocusState private var isKeyboardActive: Bool

    private let radiusOptions = [5, 10, 15, 25, 50, 100]

    private let steps = ["Details", "Category", "Location", "Review"]
    private let stepIcons = ["pencil", "folder", "mappin", "checkmark.circle"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress steps
                stepIndicator

                TabView(selection: $currentStep) {
                    detailsStep.tag(0)
                    categoryStep.tag(1)
                    locationStep.tag(2)
                    reviewStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)

                // Bottom navigation
                bottomNav
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Create Listing")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .clearDoneToolbar(
                onClear: {
                    if currentStep == 0 {
                        title = ""
                        priceText = ""
                        description = ""
                    } else if currentStep == 2 {
                        neighborhood = ""
                    }
                },
                onDone: { isKeyboardActive = false }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Listing Posted!", isPresented: $showSuccessAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your listing is now live on the marketplace.")
            }
        }
    }

    // MARK: - Step Indicator
    private var stepIndicator: some View {
        let isSmall = UIScreen.main.bounds.width < 375
        return HStack(spacing: 0) {
            ForEach(0..<steps.count, id: \.self) { i in
                HStack(spacing: isSmall ? 2 : 4) {
                    ZStack {
                        Circle()
                            .fill(i <= currentStep ? Color.accentColor : Color(.systemGray4))
                            .frame(width: isSmall ? 20 : 24, height: isSmall ? 20 : 24)
                        if i < currentStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: isSmall ? 9 : 11, weight: .bold))
                                .foregroundStyle(i <= currentStep ? .white : .secondary)
                        }
                    }
                    if !isSmall || i == currentStep {
                        Text(steps[i])
                            .font(.system(size: isSmall ? 11 : 13, weight: i == currentStep ? .semibold : .regular))
                            .foregroundStyle(i <= currentStep ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                if i < steps.count - 1 {
                    Spacer(minLength: 2)
                    Rectangle()
                        .fill(i < currentStep ? Color.accentColor : Color(.systemGray4))
                        .frame(width: isSmall ? 6 : 8, height: 1.5)
                    Spacer(minLength: 2)
                }
            }
        }
        .padding(.horizontal, isSmall ? 8 : 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - Step 1: Details
    private var detailsStep: some View {
        Form {
            Section("Title") {
                HStack {
                    TextField("What are you selling?", text: $title)
                        .focused($isKeyboardActive)
                    if !title.isEmpty {
                        Button { title = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                Text("\(title.count)/80 characters")
                    .font(.caption)
                    .foregroundStyle(title.count > 80 ? .red : .secondary)
            }

            Section("Price") {
                Toggle("Free", isOn: $isFree)
                    .onChange(of: isFree) { _, newValue in
                        if newValue { priceText = "" }
                    }
                if !isFree {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .focused($isKeyboardActive)
                        if !priceText.isEmpty {
                            Button { priceText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Description") {
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $description)
                        .focused($isKeyboardActive)
                        .frame(minHeight: 120)
                    if !description.isEmpty {
                        Button { description = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
                Text("Include details like brand, size, condition, and why you're selling.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Photos") {
                ImagePickerView(selectedImages: $selectedImages, coverImageIndex: $coverImageIndex)
            }
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(Color(.systemGray4))
            VStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                Text("Add")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .frame(height: 100)
    }

    // MARK: - Step 2: Category
    private var categoryStep: some View {
        Form {
            Section("Category") {
                ForEach(ListingCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                        selectedSubcategory = category.subcategories.first ?? ""
                    } label: {
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.color)
                                .frame(width: 30)
                            Text(category.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategory == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            Section("Subcategory") {
                Picker("Subcategory", selection: $selectedSubcategory) {
                    ForEach(selectedCategory.subcategories, id: \.self) { sub in
                        Text(sub).tag(sub)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
            }

            if selectedCategory == .forSale {
                Section("Condition") {
                    Picker("Condition", selection: $selectedCondition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Text(condition.rawValue).tag(condition)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Step 3: Location
    private var locationStep: some View {
        Form {
            Section("Your Location") {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("San Mateo, CA")
                }

                Picker("Neighborhood", selection: $neighborhood) {
                    Text("Select neighborhood").tag("")
                    ForEach(SampleData.neighborhoods, id: \.self) { n in
                        Text(n).tag(n)
                    }
                }
            }

            Section {
                let coord = SampleData.neighborhoodCoordinates[neighborhood] ?? SampleData.defaultCoordinate
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))), interactionModes: []) {
                    Marker(neighborhood.isEmpty ? "San Mateo" : neighborhood, coordinate: coord)
                }
                .frame(height: UIScreen.main.bounds.height < 700 ? 140 : 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
            }

            Section("Visibility") {
                Picker(selection: $visibilityRadius) {
                    ForEach(radiusOptions, id: \.self) { miles in
                        Text("\(miles) miles").tag(miles)
                    }
                } label: {
                    Label("Visible to buyers within", systemImage: "eye.fill")
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Buyers within \(visibilityRadius) miles will see your listing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Step 4: Review
    private var reviewStep: some View {
        Form {
            Section("Preview") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedCategory.color.opacity(0.15))
                        if !selectedImages.isEmpty {
                            let idx = min(coverImageIndex, selectedImages.count - 1)
                            Image(uiImage: selectedImages[idx])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Image(systemName: selectedCategory.icon)
                                .font(.title2)
                                .foregroundStyle(selectedCategory.color)
                        }
                    }
                    .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title.isEmpty ? "No title" : title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(isFree ? "Free" : (priceText.isEmpty ? "No price" : "$\(priceText)"))
                            .font(.headline)
                        Text(neighborhood.isEmpty ? "No location" : neighborhood)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Details") {
                LabeledContent("Category", value: selectedCategory.rawValue)
                LabeledContent("Subcategory", value: selectedSubcategory)
                if selectedCategory == .forSale {
                    LabeledContent("Condition", value: selectedCondition.rawValue)
                }
                LabeledContent("Location", value: "San Mateo, CA")
                LabeledContent("Visibility", value: "\(visibilityRadius) miles")
            }

            Section("Description") {
                Text(description.isEmpty ? "No description provided" : description)
                    .font(.subheadline)
                    .foregroundStyle(description.isEmpty ? .secondary : .primary)
            }

            if !isFormValid {
                Section("Missing Fields") {
                    if title.isEmpty {
                        Label("Title is required", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if description.isEmpty {
                        Label("Description is required", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if !isFree && priceText.isEmpty {
                        Label("Price is required", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if selectedSubcategory.isEmpty {
                        Label("Subcategory is required", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                    if neighborhood.isEmpty {
                        Label("Neighborhood is required", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Nav
    private var bottomNav: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
            }

            Spacer()

            if currentStep < steps.count - 1 {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                }
            } else {
                Button {
                    postListing()
                } label: {
                    HStack {
                        if isPosting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isPosting ? "Posting..." : "Post Listing")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(isFormValid && !isPosting ? Color.accentColor : Color.gray)
                    .clipShape(Capsule())
                }
                .disabled(!isFormValid || isPosting)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var isFormValid: Bool {
        let hasTitle = !title.isEmpty
        let hasDescription = !description.isEmpty
        let hasSubcategory = !selectedSubcategory.isEmpty
        let hasNeighborhood = !neighborhood.isEmpty
        let hasPrice = isFree || !priceText.isEmpty
        return hasTitle && hasDescription && hasSubcategory && hasNeighborhood && hasPrice
    }

    private func postListing() {
        isPosting = true
        let price = isFree ? 0.0 : Double(priceText)
        let condition = selectedCategory == .forSale ? selectedCondition : nil

        Task {
            if amplifyService.isConfigured {
                // Upload images to S3 first
                let listingID = UUID().uuidString
                var uploadedKeys: [String] = []
                if !selectedImages.isEmpty {
                    uploadedKeys = await amplifyService.uploadListingImages(selectedImages, listingID: listingID)
                }

                let success = await viewModel.postListingToBackend(
                    amplifyService,
                    title: title,
                    description: description,
                    price: price,
                    category: selectedCategory,
                    subcategory: selectedSubcategory,
                    location: amplifyService.currentUserEmail ?? "Unknown",
                    neighborhood: neighborhood,
                    condition: condition,
                    imageKeys: uploadedKeys,
                    localImages: selectedImages,
                    coverImageIndex: coverImageIndex
                )
                await MainActor.run {
                    isPosting = false
                    if success {
                        showSuccessAlert = true
                    }
                }
            } else {
                // Fallback: save locally
                let listing = Listing(
                    id: UUID(),
                    title: title,
                    description: description,
                    price: price,
                    category: selectedCategory,
                    subcategory: selectedSubcategory,
                    images: [],
                    localImages: selectedImages,
                    coverImageIndex: coverImageIndex,
                    location: "Local",
                    neighborhood: neighborhood,
                    postedDate: Date(),
                    sellerID: amplifyService.currentUserID ?? "local",
                    sellerName: viewModel.currentUser.name,
                    condition: condition
                )
                await MainActor.run {
                    viewModel.addListing(listing)
                    isPosting = false
                    showSuccessAlert = true
                }
            }
        }
    }
}
