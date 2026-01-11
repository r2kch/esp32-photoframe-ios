import Photos
import PhotosUI
import SwiftUI

struct ContentView: View {
    @AppStorage("photoframeHost") private var host: String = "photoframe.local"
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var previewInfo: String = ""
    @State private var statusMessage: String = ""
    @State private var isError: Bool = false
    @State private var isUploading: Bool = false
    @State private var displayNow: Bool = false

    private let uploader = UploadService()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    deviceCard
                    photoCard
                    actionsCard
                }
                .padding(18)
            }
            .navigationTitle("PhotoFrame")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your photo, instantly on the frame.")
                .font(.title2.weight(.semibold))
            Text("Pick a photo, upload it, and optionally display it right away.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device")
                .font(.headline)
            TextField("photoframe.local", text: $host)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
            Toggle("Display immediately", isOn: $displayNow)
        }
        .cardStyle()
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Photo")
                .font(.headline)
            PhotosPicker(selection: $selectedItem, matching: .images) {
                HStack {
                    Image(systemName: "photo")
                    Text(selectedImage == nil ? "Select a photo" : "Change photo")
                }
            }
            .buttonStyle(.bordered)
            .tint(.orange)

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 220)
                    .clipped()
                    .cornerRadius(16)
                if !previewInfo.isEmpty {
                    Text(previewInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .cardStyle()
        .onChange(of: selectedItem) { newValue in
            guard let newValue else { return }
            Task {
                await loadImage(from: newValue)
            }
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upload")
                .font(.headline)
            Button {
                Task {
                    await upload()
                }
            } label: {
                if isUploading {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("Start upload")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isUploading || selectedImage == nil)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(isError ? .red : .secondary)
            }
        }
        .cardStyle()
    }

    private func loadImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let normalized = ImageProcessor.normalized(image)
                await MainActor.run {
                    selectedImage = normalized
                    previewInfo = "\(Int(normalized.size.width))x\(Int(normalized.size.height)) px"
                    statusMessage = "Ready to upload."
                    isError = false
                }
            } else {
                await MainActor.run {
                    statusMessage = "Could not read the selected image."
                    isError = true
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = "Failed to load photo: \(error.localizedDescription)"
                isError = true
            }
        }
    }

    private func upload() async {
        guard let image = selectedImage else {
            statusMessage = "Please select a photo first."
            isError = true
            return
        }

        await MainActor.run {
            isUploading = true
            statusMessage = "Preparing image..."
            isError = false
        }

        do {
            let payload = try ImageProcessor.buildPayload(from: image)
            await MainActor.run {
                statusMessage = "Uploading..."
            }
            let outcome = try await uploader.upload(
                host: host,
                album: "Default",
                processingMode: "enhanced",
                imageData: payload.fullJPEG,
                thumbData: payload.thumbJPEG,
                displayNow: displayNow
            )
            do {
                try await saveToLibrary(image)
                await MainActor.run {
                    statusMessage = "\(outcome.message) Saved to Photos."
                    isError = false
                }
            } catch {
                await MainActor.run {
                    statusMessage = "\(outcome.message) Photo save failed: \(error.localizedDescription)"
                    isError = true
                }
            }
        } catch {
            await MainActor.run {
                statusMessage = error.localizedDescription
                isError = true
            }
        }

        await MainActor.run {
            isUploading = false
        }
    }

    private func saveToLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw UploadError.processing("Photos permission denied.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: UploadError.processing("Could not save photo."))
                }
            }
        }
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

#Preview {
    ContentView()
}
