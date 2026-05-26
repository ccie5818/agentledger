import SwiftUI

struct FilterView: View {
    @EnvironmentObject var viewModel: AppViewModel
    @Environment(\.dismiss) var dismiss

    @State private var selectedCategory: ListingCategory?
    @State private var selectedSubcategory: String?
    @State private var selectedCondition: ItemCondition?
    @State private var minPriceText: String = ""
    @State private var maxPriceText: String = ""
    @FocusState private var focusedField: PriceField?
    enum PriceField { case min, max }
    @State private var selectedSort: SortOption = .newest
    @State private var searchRadius: Double = 25

    var body: some View {
        NavigationStack {
            Form {
                // Category
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as ListingCategory?)
                        ForEach(ListingCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat as ListingCategory?)
                        }
                    }

                    if let category = selectedCategory {
                        Picker("Subcategory", selection: $selectedSubcategory) {
                            Text("All").tag(nil as String?)
                            ForEach(category.subcategories, id: \.self) { sub in
                                Text(sub).tag(sub as String?)
                            }
                        }
                    }
                }

                // Price
                Section("Price Range") {
                    HStack {
                        HStack {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("Min", text: $minPriceText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .min)
                            if !minPriceText.isEmpty {
                                Button { minPriceText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("to")
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("$")
                                .foregroundStyle(.secondary)
                            TextField("Max", text: $maxPriceText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .max)
                            if !maxPriceText.isEmpty {
                                Button { maxPriceText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Condition
                Section("Condition") {
                    Picker("Condition", selection: $selectedCondition) {
                        Text("Any").tag(nil as ItemCondition?)
                        ForEach(ItemCondition.allCases) { cond in
                            Text(cond.rawValue).tag(cond as ItemCondition?)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Location
                Section("Distance") {
                    VStack(alignment: .leading) {
                        Text("Within \(Int(searchRadius)) miles")
                            .font(.subheadline)
                        Slider(value: $searchRadius, in: 5...100, step: 5)
                    }
                }

                // Sort
                Section("Sort By") {
                    Picker("Sort", selection: $selectedSort) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .clearDoneToolbar(
                onClear: {
                    switch focusedField {
                    case .min: minPriceText = ""
                    case .max: maxPriceText = ""
                    case .none: break
                    }
                },
                onDone: { focusedField = nil }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        resetFilters()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        applyFilters()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentFilters()
            }
        }
    }

    private func loadCurrentFilters() {
        selectedCategory = viewModel.searchFilter.categories.first
        selectedSubcategory = viewModel.searchFilter.subcategory
        selectedCondition = viewModel.searchFilter.condition
        selectedSort = viewModel.searchFilter.sortBy
        searchRadius = viewModel.searchFilter.searchRadius
        if let min = viewModel.searchFilter.minPrice { minPriceText = "\(Int(min))" }
        if let max = viewModel.searchFilter.maxPrice { maxPriceText = "\(Int(max))" }
    }

    private func applyFilters() {
        if let cat = selectedCategory {
            viewModel.searchFilter.categories = [cat]
        } else {
            viewModel.searchFilter.categories.removeAll()
        }
        viewModel.searchFilter.subcategory = selectedSubcategory
        viewModel.searchFilter.condition = selectedCondition
        viewModel.searchFilter.sortBy = selectedSort
        viewModel.searchFilter.searchRadius = searchRadius
        viewModel.searchFilter.minPrice = Double(minPriceText)
        viewModel.searchFilter.maxPrice = Double(maxPriceText)
    }

    private func resetFilters() {
        selectedCategory = nil
        selectedSubcategory = nil
        selectedCondition = nil
        minPriceText = ""
        maxPriceText = ""
        selectedSort = .newest
        searchRadius = 25
    }
}
