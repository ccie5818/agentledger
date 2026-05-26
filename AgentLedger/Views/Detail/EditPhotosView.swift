import SwiftUI

struct EditPhotosView: View {
    let listing: Listing
    @EnvironmentObject var viewModel: AppViewModel
    @EnvironmentObject var amplifyService: AmplifyService
    @Environment(\.dismiss) var dismiss

    @State private var selectedImages: [UIImage] = []
    @State private var coverImageIndex: Int = 0
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var loadedExisting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    Spacer()
                    ProgressView("Loading photos...")
                    Spacer()
                } else {
                    Text("Add, remove, or reorder your photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ImagePickerView(selectedImages: $selectedImages, coverImageIndex: $coverImageIndex)

                    Spacer()

                    Button {
                        Task { await savePhotos() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSaving ? "Uploading..." : "Save Photos")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isSaving ? Color.gray : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSaving)
                    .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Edit Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !loadedExisting {
                    loadedExisting = true
                    Task { await loadExistingPhotos() }
                }
            }
        }
    }

    private func loadExistingPhotos() async {
        let live = viewModel.listings.first { $0.id == listing.id } ?? listing

        // If we have local images, use those
        if !live.localImages.isEmpty {
            await MainActor.run {
                selectedImages = live.localImages
                coverImageIndex = live.coverImageIndex
                isLoading = false
            }
            return
        }

        // Otherwise download from S3
        var downloaded: [UIImage] = []
        for key in live.images {
            do {
                let url = try await amplifyService.getImageURL(path: key)
                let (data, _) = try await URLSession.shared.data(from: url)
                if let cleanImage = UIImage.fromDataClean(data) {
                    downloaded.append(cleanImage)
                }
            } catch {
                print("[EDIT-PHOTOS] Failed to download \(key): \(error)")
            }
        }

        await MainActor.run {
            selectedImages = downloaded
            coverImageIndex = live.coverImageIndex
            isLoading = false
        }
    }

    private func savePhotos() async {
        isSaving = true
        viewModel.updateListingImages(listing.id, newImages: selectedImages, amplifyService: amplifyService)
        try? await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            isSaving = false
            dismiss()
        }
    }
}
