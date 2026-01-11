import Foundation

struct UploadResponse: Decodable {
    let status: String
    let filename: String?
    let message: String?
}

struct AlbumItem: Decodable {
    let name: String
    let enabled: Bool?
}

struct ImageListItem: Decodable {
    let name: String
}

struct UploadOutcome {
    let message: String
    let filename: String
    let verified: Bool
    let overwriteRisk: Bool
}

enum UploadError: LocalizedError {
    case invalidHost
    case processing(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid host."
        case .processing(let message):
            return message
        case .network(let message):
            return message
        case .server(let message):
            return message
        }
    }
}

struct UploadService {
    func fetchAlbums(host: String) async throws -> [AlbumItem] {
        let sanitizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedHost.isEmpty else {
            throw UploadError.invalidHost
        }
        let url = try makeURL(host: sanitizedHost, path: "/api/albums")
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw UploadError.network("Albums request failed: HTTP \(httpResponse.statusCode)")
        }
        let decoder = JSONDecoder()
        return try decoder.decode([AlbumItem].self, from: data)
    }

    func upload(
        host: String,
        album: String,
        processingMode: String,
        imageData: Data,
        thumbData: Data,
        displayNow: Bool
    ) async throws -> UploadOutcome {
        let sanitizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedHost.isEmpty else {
            throw UploadError.invalidHost
        }

        let preUploadList = try? await listImages(host: sanitizedHost, album: album)
        let uploadURL = try makeURL(host: sanitizedHost, path: "/api/upload")
        let boundary = "Boundary-\(UUID().uuidString)"
        let baseName = "upload-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = buildMultipartBody(
            boundary: boundary,
            fields: [("album", album), ("processingMode", processingMode)],
            files: [
                (name: "image", filename: "\(baseName).jpg", mime: "image/jpeg", data: imageData),
                (name: "thumbnail", filename: "\(baseName)_thumb.jpg", mime: "image/jpeg", data: thumbData)
            ]
        )

        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: request)
        let uploadResult = try decodeResponse(uploadData, response: uploadResponse)

        guard uploadResult.status == "success", let filename = uploadResult.filename else {
            throw UploadError.server(uploadResult.message ?? "Upload failed.")
        }

        let postUploadList = try? await listImages(host: sanitizedHost, album: album)
        let verified = postUploadList?.contains(where: { $0.name == filename }) ?? false
        let overwriteRisk = preUploadList?.contains(where: { $0.name == filename }) ?? false

        if displayNow {
            let displayURL = try makeURL(host: sanitizedHost, path: "/api/display")
            var displayRequest = URLRequest(url: displayURL)
            displayRequest.httpMethod = "POST"
            displayRequest.timeoutInterval = 90
            displayRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["filename": "\(album)/\(filename)"]
            displayRequest.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            let (displayData, displayResponse) = try await URLSession.shared.data(for: displayRequest)
            let displayResult = try decodeResponse(displayData, response: displayResponse)
            guard displayResult.status == "success" else {
                throw UploadError.server(displayResult.message ?? "Display failed.")
            }
            return UploadOutcome(message: "Upload complete. Image is being displayed.", filename: filename, verified: verified, overwriteRisk: overwriteRisk)
        }

        return UploadOutcome(message: "Upload complete.", filename: filename, verified: verified, overwriteRisk: overwriteRisk)
    }

    private func makeURL(host: String, path: String) throws -> URL {
        let urlString = "http://\(host)\(path)"
        guard let url = URL(string: urlString) else {
            throw UploadError.invalidHost
        }
        return url
    }

    private func decodeResponse(_ data: Data, response: URLResponse) throws -> UploadResponse {
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw UploadError.network(message)
        }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(UploadResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "Invalid JSON response."
            throw UploadError.server(raw)
        }
    }

    private func listImages(host: String, album: String) async throws -> [ImageListItem] {
        let encoded = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? album
        let url = try makeURL(host: host, path: "/api/images?album=\(encoded)")
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw UploadError.network("List images failed: HTTP \(httpResponse.statusCode)")
        }
        let decoder = JSONDecoder()
        return try decoder.decode([ImageListItem].self, from: data)
    }

    private func buildMultipartBody(
        boundary: String,
        fields: [(String, String)],
        files: [(name: String, filename: String, mime: String, data: Data)]
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        for file in files {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            body.append("Content-Type: \(file.mime)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
