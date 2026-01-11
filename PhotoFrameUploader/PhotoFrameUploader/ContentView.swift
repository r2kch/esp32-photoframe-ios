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
    @State private var isPortrait: Bool = false
    @State private var albums: [AlbumItem] = []
    @AppStorage("photoframeAlbum") private var selectedAlbum: String = "Default"
    @State private var albumError: String?
    @State private var isLoadingAlbums: Bool = false
    @State private var isAlbumPickerPresented: Bool = false

    private let uploader = UploadService()

    var body: some View {
        NavigationView {
            TabView {
                picturesTab
                    .tabItem {
                        Label("Pictures", systemImage: "camera")
                    }
                settingsTab
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .navigationTitle("PhotoFrame")
        }
    }

    private var picturesTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                photoCard
                displayCard
                albumCard
                actionsCard
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 18) {
                deviceCard
                aboutCard
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        }
        .cardStyle()
    }

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display")
                .font(.headline)
            Toggle("Display immediately", isOn: $displayNow)
        }
        .cardStyle()
        .frame(maxWidth: .infinity)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)
            Text("This app is a companion for `aitjcize/esp32-photoframe` (https://github.com/aitjcize/esp32-photoframe) running on the Waveshare ESP32-S3-PhotoPainter.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("The PhotoFrame firmware must be installed and connected to Wi-Fi as described in the vendor's GitHub instructions. To keep the device online, it should be powered via USB-C.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("Disclaimer")
                .font(.headline)
            Text("This app is provided “as is,” without warranties of any kind. Use at your own risk. Apple, aitjcize, and r2kch are not responsible for any device behavior, data loss, or damages arising from its use.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .cardStyle()
        .frame(maxWidth: .infinity)
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
            .zIndex(1)

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: isPortrait ? 320 : 220)
                    .cornerRadius(16)
                    .allowsHitTesting(false)
                if !previewInfo.isEmpty {
                    Text(previewInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if isPortrait {
                    Text("Warning: This photo is portrait. Please edit it to landscape in your iPhone library before uploading.")
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .cardStyle()
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity)
    }

    private var albumCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Album")
                .font(.headline)
            if isLoadingAlbums {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading albums...")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Button {
                    Task {
                        await loadAlbumsIfNeeded()
                        await MainActor.run {
                            isAlbumPickerPresented = true
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedAlbum.isEmpty ? "Default" : selectedAlbum)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .font(.body)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }

            if let albumError {
                Text(albumError)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
        .cardStyle()
        .confirmationDialog("Select Album", isPresented: $isAlbumPickerPresented, titleVisibility: .visible) {
            ForEach(currentAlbums, id: \.name) { album in
                Button(album.name) {
                    selectedAlbum = album.name
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let normalized = ImageProcessor.normalized(image)
                await MainActor.run {
                    selectedImage = normalized
                    previewInfo = "\(Int(normalized.size.width))x\(Int(normalized.size.height)) px"
                    isPortrait = normalized.size.height > normalized.size.width
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
            let targetAlbum = resolveUploadAlbum()
            let outcome = try await uploader.upload(
                host: host,
                album: targetAlbum,
                processingMode: "enhanced",
                imageData: payload.fullJPEG,
                thumbData: payload.thumbJPEG,
                displayNow: displayNow
            )
            await MainActor.run {
                statusMessage = outcome.message
                isError = false
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

    private func resolveUploadAlbum() -> String {
        let trimmed = selectedAlbum.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Default"
        }
        if albums.isEmpty && trimmed != "Default" {
            return "Default"
        }
        return trimmed
    }

    private func loadAlbumsIfNeeded() async {
        if isLoadingAlbums || !albums.isEmpty {
            return
        }
        await MainActor.run {
            isLoadingAlbums = true
            albumError = nil
        }
        do {
            let fetched = try await uploader.fetchAlbums(host: host)
            await MainActor.run {
                albums = fetched
                if selectedAlbum.isEmpty, let first = fetched.first?.name {
                    selectedAlbum = first
                }
                isLoadingAlbums = false
            }
        } catch {
            await MainActor.run {
                albumError = "Could not load albums. \(error.localizedDescription)"
                isLoadingAlbums = false
            }
        }
    }

    private var currentAlbums: [AlbumItem] {
        if albums.isEmpty {
            return [AlbumItem(name: "Default", enabled: nil)]
        }
        return albums
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
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
