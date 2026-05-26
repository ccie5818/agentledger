import SwiftUI

/// Displays an image from S3 using the Amplify Storage URL
/// Re-renders through sRGB to fix malformed ICC color profiles
struct S3ImageView: View {
    let imageKey: String
    let amplifyService: AmplifyService
    @State private var loadedImage: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                placeholderView
            }
        }
        .task {
            do {
                let url = try await amplifyService.getImageURL(path: imageKey)
                let (data, _) = try await URLSession.shared.data(from: url)
                if !Task.isCancelled {
                    loadedImage = UIImage.fromDataClean(data)
                }
            } catch is CancellationError {
                // View disappeared — normal, ignore
            } catch let error as NSError where error.code == NSURLErrorCancelled {
                // URL request cancelled — normal, ignore
            } catch {
                print("Failed to load S3 image: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    private var placeholderView: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}
