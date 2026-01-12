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
    @State private var albumList: [AlbumItem] = []
    @State private var albumListError: String?
    @State private var isAlbumListLoading: Bool = false
    @State private var isCreateAlbumPresented: Bool = false
    @State private var newAlbumName: String = ""
    @State private var isCreatingAlbum: Bool = false
    @State private var albumToDelete: AlbumItem?
    @State private var showDeleteAlbumConfirm: Bool = false
    @State private var rotationIntervalText: String = ""
    @State private var rotationConfig: ConfigResponse?
    @State private var rotationError: String?
    @State private var isRotationLoading: Bool = false
    @State private var isRotationSaving: Bool = false

    private let uploader = UploadService()

    var body: some View {
        TabView {
            NavigationStack {
                picturesTab
                    .navigationTitle("PhotoFrame")
            }
            .tabItem {
                Label("Pictures", systemImage: "camera")
            }

            NavigationStack {
                albumsContent
                    .navigationTitle("PhotoFrame")
            }
            .tabItem {
                Label("Album", systemImage: "rectangle.stack")
            }

            NavigationStack {
                settingsTab
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
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
                rotationCard
                aboutCard
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            Task {
                await loadRotationConfig()
            }
        }
    }

    private var albumsContent: some View {
        Group {
            if isAlbumListLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading albums...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let albumListError {
                VStack(spacing: 12) {
                    Text(albumListError)
                        .foregroundColor(.red)
                    Button("Retry") {
                        Task {
                            await loadAlbumList()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(albumList, id: \.name) { album in
                    NavigationLink(album.name) {
                        AlbumDetailView(album: album.name, host: host, uploader: uploader)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if album.name != "Default" {
                            Button(role: .destructive) {
                                albumToDelete = album
                                showDeleteAlbumConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            newAlbumName = ""
                            isCreateAlbumPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadAlbumList()
            }
        }
        .alert("New Album", isPresented: $isCreateAlbumPresented) {
            TextField("Album name", text: $newAlbumName)
            Button("Create") {
                Task {
                    await createAlbum()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new album.")
        }
        .alert("Delete Album", isPresented: $showDeleteAlbumConfirm) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAlbum()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete this album and all its images? This cannot be undone.")
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

    private var rotationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rotation Interval")
                .font(.headline)
            Text("Automatic image rotation interval in seconds.")
                .font(.footnote)
                .foregroundColor(.secondary)
            TextField("Seconds", text: $rotationIntervalText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .disabled(isRotationLoading)
            Button {
                Task {
                    await updateRotationInterval()
                }
            } label: {
                if isRotationSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("Save Settings")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isRotationLoading || isRotationSaving)
            if let rotationError {
                Text(rotationError)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
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

    private func loadAlbumList() async {
        if isAlbumListLoading {
            return
        }
        await MainActor.run {
            isAlbumListLoading = true
            albumListError = nil
        }
        do {
            let fetched = try await uploader.fetchAlbums(host: host)
            await MainActor.run {
                albumList = fetched
                isAlbumListLoading = false
            }
        } catch {
            await MainActor.run {
                albumListError = "Could not load albums. \(error.localizedDescription)"
                isAlbumListLoading = false
            }
        }
    }

    private func createAlbum() async {
        if isCreatingAlbum {
            return
        }
        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            await MainActor.run {
                albumListError = "Album name cannot be empty."
            }
            return
        }
        await MainActor.run {
            isCreatingAlbum = true
        }
        do {
            try await uploader.createAlbum(host: host, name: name)
            try await uploader.setAlbumEnabled(host: host, name: name, enabled: true)
            await MainActor.run {
                isCreatingAlbum = false
                isCreateAlbumPresented = false
            }
            await loadAlbumList()
        } catch {
            await MainActor.run {
                albumListError = "Could not create album. \(error.localizedDescription)"
                isCreatingAlbum = false
            }
        }
    }

    private func deleteAlbum() async {
        guard let album = albumToDelete else {
            return
        }
        if album.name == "Default" {
            await MainActor.run {
                albumListError = "The Default album cannot be deleted."
            }
            return
        }
        await MainActor.run {
            albumListError = nil
        }
        do {
            try await uploader.deleteAlbum(host: host, name: album.name)
            await MainActor.run {
                albumToDelete = nil
                showDeleteAlbumConfirm = false
            }
            await loadAlbumList()
        } catch {
            await MainActor.run {
                albumListError = "Could not delete album. \(error.localizedDescription)"
            }
        }
    }

    private func loadRotationConfig() async {
        if isRotationLoading {
            return
        }
        await MainActor.run {
            isRotationLoading = true
            rotationError = nil
        }
        do {
            let config = try await uploader.fetchConfig(host: host)
            await MainActor.run {
                rotationConfig = config
                rotationIntervalText = String(config.rotate_interval)
                isRotationLoading = false
            }
        } catch {
            await MainActor.run {
                rotationError = "Could not load rotation interval. \(error.localizedDescription)"
                isRotationLoading = false
            }
        }
    }

    private func updateRotationInterval() async {
        guard let currentConfig = rotationConfig else {
            return
        }
        let trimmed = rotationIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let interval = Int(trimmed) else {
            rotationError = "Rotation interval must be a number."
            return
        }
        let payload = DeviceConfig(
            rotate_interval: interval,
            auto_rotate: currentConfig.auto_rotate,
            deep_sleep_enabled: currentConfig.deep_sleep_enabled,
            brightness_fstop: currentConfig.brightness_fstop,
            contrast: currentConfig.contrast
        )
        do {
            await MainActor.run {
                isRotationSaving = true
            }
            try await uploader.updateConfig(host: host, config: payload)
            await MainActor.run {
                rotationError = nil
                rotationConfig = ConfigResponse(
                    rotate_interval: interval,
                    auto_rotate: currentConfig.auto_rotate,
                    deep_sleep_enabled: currentConfig.deep_sleep_enabled,
                    brightness_fstop: currentConfig.brightness_fstop,
                    contrast: currentConfig.contrast
                )
                isRotationSaving = false
            }
        } catch {
            await MainActor.run {
                rotationError = "Could not update rotation interval. \(error.localizedDescription)"
                isRotationSaving = false
            }
        }
    }
}

private struct AlbumDetailView: View {
    let album: String
    let host: String
    let uploader: UploadService

    @State private var images: [ImageListItem] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading images...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundColor(.red)
                    Button("Retry") {
                        Task {
                            await loadImages()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(images, id: \.name) { image in
                            AlbumImageRow(
                                album: album,
                                filename: image.name,
                                host: host,
                                uploader: uploader,
                                onDelete: {
                                    images.removeAll { $0.name == image.name }
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await loadImages()
            }
        }
    }

    private func loadImages() async {
        if isLoading {
            return
        }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let fetched = try await uploader.fetchImages(host: host, album: album)
            await MainActor.run {
                images = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not load images. \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

private struct AlbumImageRow: View {
    let album: String
    let filename: String
    let host: String
    let uploader: UploadService
    let onDelete: () -> Void

    @State private var isWorking: Bool = false
    @State private var showError: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: thumbnailURL) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(12)
            .layoutPriority(2)

            Button {
                Task {
                    await display()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera")
                    Image(systemName: "bolt.fill")
                    Text("Display")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.52, green: 0.33, blue: 0.88))
            .cornerRadius(16)
            .frame(maxWidth: .infinity)
            .layoutPriority(3)
            .disabled(isWorking)

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .background(Color.red)
            .clipShape(Circle())
            .layoutPriority(0)
            .disabled(isWorking)
            .confirmationDialog("Delete this image?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await delete()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity)
        .alert("Action failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var thumbnailURL: URL? {
        let path = "/api/image?name=\(album)/\(filename)"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        return URL(string: "http://\(host)\(encoded)")
    }

    private var placeholder: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .foregroundColor(.secondary)
        }
    }

    private func display() async {
        if isWorking { return }
        await MainActor.run { isWorking = true }
        do {
            try await uploader.displayImage(host: host, album: album, filename: filename)
            await MainActor.run { isWorking = false }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
        }
    }

    private func delete() async {
        if isWorking { return }
        await MainActor.run { isWorking = true }
        do {
            try await uploader.deleteImage(host: host, album: album, filename: filename)
            await MainActor.run {
                isWorking = false
                onDelete()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isWorking = false
            }
        }
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
