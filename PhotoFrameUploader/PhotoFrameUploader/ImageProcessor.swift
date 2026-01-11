import UIKit

struct ImagePayload {
    let fullJPEG: Data
    let thumbJPEG: Data
}

enum ImageProcessor {
    static func normalized(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    static func buildPayload(from image: UIImage) throws -> ImagePayload {
        let isPortrait = image.size.height > image.size.width
        let fullSize = isPortrait ? CGSize(width: 480, height: 800) : CGSize(width: 800, height: 480)
        let thumbSize = isPortrait ? CGSize(width: 120, height: 200) : CGSize(width: 200, height: 120)

        guard let full = renderCover(image, targetSize: fullSize, quality: 0.9) else {
            throw UploadError.processing("Failed to prepare full-size image.")
        }
        guard let thumb = renderCover(image, targetSize: thumbSize, quality: 0.85) else {
            throw UploadError.processing("Failed to prepare thumbnail image.")
        }
        return ImagePayload(fullJPEG: full, thumbJPEG: thumb)
    }

    private static func renderCover(_ image: UIImage, targetSize: CGSize, quality: CGFloat) -> Data? {
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
