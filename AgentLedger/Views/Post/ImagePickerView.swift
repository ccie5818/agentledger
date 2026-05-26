import SwiftUI
import PhotosUI
import ImageIO
import CoreLocation

struct ImagePickerView: View {
    @Binding var selectedImages: [UIImage]
    @Binding var coverImageIndex: Int
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showSourcePicker = false
    @State private var showPhotoPicker = false
    let maxImages: Int = 12

    var body: some View {
        VStack(spacing: 12) {
            // Selected images grid
            if !selectedImages.isEmpty {
                Text("Tap a photo to set it as cover")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 90, height: 90)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(index == coverImageIndex ? Color.accentColor : Color.clear, lineWidth: 3)
                                    )
                                    .onTapGesture {
                                        coverImageIndex = index
                                    }

                                // Cover badge
                                if index == coverImageIndex {
                                    Text("Cover")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                        .offset(x: -4, y: 70)
                                }

                                Button {
                                    selectedImages.remove(at: index)
                                    // Adjust coverImageIndex if needed
                                    if selectedImages.isEmpty {
                                        coverImageIndex = 0
                                    } else if coverImageIndex >= selectedImages.count {
                                        coverImageIndex = selectedImages.count - 1
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .background(Circle().fill(.black.opacity(0.5)))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }

                        // Add more button
                        if selectedImages.count < maxImages {
                            addButton
                        }
                    }
                }
            } else {
                // Empty state
                HStack(spacing: 12) {
                    addButton
                    addButton
                    addButton
                }
            }

            Text("\(selectedImages.count)/\(maxImages) photos")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: photoItems) {
            Task { await loadImages() }
        }
        .confirmationDialog("Add Photo", isPresented: $showSourcePicker, titleVisibility: .visible) {
            Button("Take Photo") {
                showCamera = true
            }
            Button("Choose from Library") {
                showPhotoPicker = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                if selectedImages.count < maxImages {
                    selectedImages.append(image)
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: maxImages - selectedImages.count,
            matching: .images
        )
    }

    private var addButton: some View {
        Button {
            showSourcePicker = true
        } label: {
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
            .frame(width: 90, height: 90)
        }
    }

    private func loadImages() async {
        for item in photoItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage.fromDataClean(data) {
                await MainActor.run {
                    if selectedImages.count < maxImages {
                        selectedImages.append(image)
                    }
                }
            }
        }
        await MainActor.run {
            photoItems.removeAll()
        }
    }
}

// MARK: - Camera View
struct CameraView: UIViewControllerRepresentable {
    var onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImageCaptured: (UIImage) -> Void
        var dismiss: DismissAction

        init(onImageCaptured: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImageCaptured = onImageCaptured
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Save a copy to the local photo library
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                onImageCaptured(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Strip Location Metadata
extension UIImage {
    /// Re-renders the image with a clean sRGB profile, removing malformed ICC profiles
    func strippingColorProfile() -> UIImage? {
        guard let cgImage = self.cgImage else { return self }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cleanCG = context.makeImage() else { return self }
        return UIImage(cgImage: cleanCG, scale: self.scale, orientation: self.imageOrientation)
    }

    /// Load image from data using CGImageSource to avoid ColorSync ICC profile warnings
    static func fromDataClean(_ data: Data) -> UIImage? {
        // Strip iCCP chunk from PNG data before parsing to prevent ColorSync warnings
        let cleanData = Self.stripICCProfile(from: data)
        guard let source = CGImageSourceCreateWithData(cleanData as CFData, nil) else { return nil }
        // Create CGImage while overriding the color space to sRGB
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Re-render into clean sRGB context
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return UIImage(cgImage: cgImage) }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cleanCG = context.makeImage() else { return UIImage(cgImage: cgImage) }
        return UIImage(cgImage: cleanCG)
    }

    /// Remove ICC profile from PNG (iCCP chunk) or JPEG (APP2 ICC_PROFILE marker) data
    /// to prevent ColorSync "Invalid profile 'c2ci'" warnings
    private static func stripICCProfile(from data: Data) -> Data {
        guard data.count > 4 else { return data }

        // PNG: strip iCCP chunks
        let pngSignature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        if data.count > 8 && Array(data.prefix(8)) == pngSignature {
            var result = Data(pngSignature)
            var pos = 8
            while pos + 8 <= data.count {
                let length = Int(data[pos]) << 24 | Int(data[pos+1]) << 16 | Int(data[pos+2]) << 8 | Int(data[pos+3])
                let chunkType = String(bytes: data[(pos+4)..<(pos+8)], encoding: .ascii) ?? ""
                let chunkTotal = 12 + length
                guard pos + chunkTotal <= data.count else { break }
                if chunkType != "iCCP" {
                    result.append(data[pos..<(pos + chunkTotal)])
                }
                pos += chunkTotal
            }
            return result
        }

        // JPEG: strip APP2 ICC_PROFILE markers (0xFF 0xE2)
        if data[0] == 0xFF && data[1] == 0xD8 {
            let iccTag: [UInt8] = Array("ICC_PROFILE".utf8) + [0x00]
            var result = Data()
            var pos = 0
            while pos < data.count {
                if pos + 1 < data.count && data[pos] == 0xFF {
                    let marker = data[pos + 1]
                    // APP2 marker
                    if marker == 0xE2 && pos + 4 < data.count {
                        let segLen = Int(data[pos+2]) << 8 | Int(data[pos+3])
                        // Check if this APP2 contains ICC_PROFILE
                        if pos + 4 + iccTag.count <= data.count &&
                           Array(data[(pos+4)..<(pos+4+iccTag.count)]) == iccTag {
                            // Skip this segment
                            pos += 2 + segLen
                            continue
                        }
                    }
                }
                result.append(data[pos])
                pos += 1
            }
            return result
        }

        return data
    }

    /// Returns clean JPEG data with GPS metadata and malformed ICC profiles removed
    func jpegDataStrippingLocation(compressionQuality: CGFloat = 0.7) -> Data? {
        // Re-render through CGContext to strip malformed ICC color profiles
        guard let cgImage = self.cgImage else {
            return self.jpegData(compressionQuality: compressionQuality)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self.jpegData(compressionQuality: compressionQuality)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let cleanCGImage = context.makeImage() else {
            return self.jpegData(compressionQuality: compressionQuality)
        }

        let cleanImage = UIImage(cgImage: cleanCGImage, scale: self.scale, orientation: self.imageOrientation)

        // Convert to JPEG data, then strip GPS metadata
        guard let jpegData = cleanImage.jpegData(compressionQuality: compressionQuality),
              let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            return cleanImage.jpegData(compressionQuality: compressionQuality)
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, type, 1, nil) else {
            return cleanImage.jpegData(compressionQuality: compressionQuality)
        }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary)

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return cleanImage.jpegData(compressionQuality: compressionQuality)
        }

        return mutableData as Data
    }
}

// MARK: - Image Upload Helper
extension AmplifyService {
    func uploadListingImages(_ images: [UIImage], listingID: String) async -> [String] {
        var keys: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = image.jpegDataStrippingLocation(compressionQuality: 0.7) else { continue }
            let key = "\(listingID)/photo_\(index)"
            do {
                let uploadedKey = try await uploadImage(data: data, path: key)
                keys.append(uploadedKey)
            } catch {
                print("Failed to upload image \(index): \(error)")
            }
        }
        return keys
    }
}
