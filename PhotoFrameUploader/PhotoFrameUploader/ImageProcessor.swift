import CoreGraphics
import UIKit

struct ImagePayload {
    let fullJPEG: Data
    let thumbJPEG: Data
}

struct ImageOptimizeParams: Equatable {
    enum ProcessingMode: String, CaseIterable {
        case stock
        case enhanced

        var title: String {
            switch self {
            case .stock: return "Stock"
            case .enhanced: return "Enhanced"
            }
        }
    }

    enum ToneMode: String, CaseIterable {
        case scurve
        case contrast

        var title: String {
            switch self {
            case .scurve: return "S-Curve"
            case .contrast: return "Contrast"
            }
        }
    }

    enum ColorMethod: String, CaseIterable {
        case rgb
        case lab

        var title: String {
            switch self {
            case .rgb: return "RGB"
            case .lab: return "LAB"
            }
        }
    }

    var processingMode: ProcessingMode = .enhanced
    var toneMode: ToneMode = .scurve
    var exposure: Double = 1.0
    var saturation: Double = 1.3
    var contrast: Double = 1.0
    var strength: Double = 0.9
    var shadowBoost: Double = 0.0
    var highlightCompress: Double = 1.5
    var midpoint: Double = 0.5
    var colorMethod: ColorMethod = .rgb
    var renderMeasured: Bool = true

    static let defaults = ImageOptimizeParams()
}

enum ImageOptimizer {
    private struct RGB {
        let r: Int
        let g: Int
        let b: Int
    }

    private static let paletteMeasured: [RGB] = [
        RGB(r: 2, g: 2, b: 2),
        RGB(r: 190, g: 190, b: 190),
        RGB(r: 205, g: 202, b: 0),
        RGB(r: 135, g: 19, b: 0),
        RGB(r: 0, g: 0, b: 0),
        RGB(r: 5, g: 64, b: 158),
        RGB(r: 39, g: 102, b: 60)
    ]

    private static let paletteTheoretical: [RGB] = [
        RGB(r: 0, g: 0, b: 0),
        RGB(r: 255, g: 255, b: 255),
        RGB(r: 255, g: 255, b: 0),
        RGB(r: 255, g: 0, b: 0),
        RGB(r: 0, g: 0, b: 0),
        RGB(r: 0, g: 0, b: 255),
        RGB(r: 0, g: 255, b: 0)
    ]

    private static let paletteLAB: [(Double, Double, Double)] = {
        paletteMeasured.map { rgbToLab(r: $0.r, g: $0.g, b: $0.b) }
    }()

    static func process(image: UIImage, targetSize: CGSize, params: ImageOptimizeParams) -> UIImage? {
        guard let rendered = renderCover(image, targetSize: targetSize),
              let cgImage = rendered.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { ptr in
            if let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        applyProcessing(&data, width: width, height: height, params: params)

        guard let output = makeImage(from: data, width: width, height: height, bytesPerRow: bytesPerRow) else {
            return nil
        }
        return output
    }

    private static func applyProcessing(_ data: inout [UInt8], width: Int, height: Int, params: ImageOptimizeParams) {
        if params.processingMode == .enhanced {
            if params.exposure != 1.0 {
                applyExposure(&data, exposure: params.exposure)
            }
            if params.saturation != 1.0 {
                applySaturation(&data, saturation: params.saturation)
            }
            if params.toneMode == .contrast {
                if params.contrast != 1.0 {
                    applyContrast(&data, contrast: params.contrast)
                }
            } else {
                applyScurveTonemap(
                    &data,
                    strength: params.strength,
                    shadowBoost: params.shadowBoost,
                    highlightCompress: params.highlightCompress,
                    midpoint: params.midpoint
                )
            }
        }

        let outputPalette = params.renderMeasured ? paletteMeasured : paletteTheoretical
        if params.processingMode == .stock {
            applyFloydSteinbergDither(
                &data,
                width: width,
                height: height,
                method: .rgb,
                outputPalette: outputPalette,
                ditherPalette: paletteTheoretical
            )
        } else {
            applyFloydSteinbergDither(
                &data,
                width: width,
                height: height,
                method: params.colorMethod,
                outputPalette: outputPalette,
                ditherPalette: paletteMeasured
            )
        }
    }

    private static func applyExposure(_ data: inout [UInt8], exposure: Double) {
        let factor = exposure
        for idx in stride(from: 0, to: data.count, by: 4) {
            data[idx] = clampByte(Double(data[idx]) * factor)
            data[idx + 1] = clampByte(Double(data[idx + 1]) * factor)
            data[idx + 2] = clampByte(Double(data[idx + 2]) * factor)
        }
    }

    private static func applyContrast(_ data: inout [UInt8], contrast: Double) {
        let factor = contrast
        for idx in stride(from: 0, to: data.count, by: 4) {
            data[idx] = clampByte((Double(data[idx]) - 128.0) * factor + 128.0)
            data[idx + 1] = clampByte((Double(data[idx + 1]) - 128.0) * factor + 128.0)
            data[idx + 2] = clampByte((Double(data[idx + 2]) - 128.0) * factor + 128.0)
        }
    }

    private static func applySaturation(_ data: inout [UInt8], saturation: Double) {
        for idx in stride(from: 0, to: data.count, by: 4) {
            let r = Double(data[idx])
            let g = Double(data[idx + 1])
            let b = Double(data[idx + 2])

            let maxVal = max(r, g, b) / 255.0
            let minVal = min(r, g, b) / 255.0
            let l = (maxVal + minVal) / 2.0

            if maxVal == minVal {
                continue
            }

            let d = maxVal - minVal
            let s = l > 0.5 ? d / (2.0 - maxVal - minVal) : d / (maxVal + minVal)

            var h: Double
            if maxVal == r / 255.0 {
                h = ((g / 255.0 - b / 255.0) / d + (g < b ? 6.0 : 0.0)) / 6.0
            } else if maxVal == g / 255.0 {
                h = ((b / 255.0 - r / 255.0) / d + 2.0) / 6.0
            } else {
                h = ((r / 255.0 - g / 255.0) / d + 4.0) / 6.0
            }

            let newS = max(0.0, min(1.0, s * saturation))
            let c = (1.0 - abs(2.0 * l - 1.0)) * newS
            let x = c * (1.0 - abs((h * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
            let m = l - c / 2.0

            let hSector = Int(floor(h * 6.0))
            let (rPrime, gPrime, bPrime): (Double, Double, Double)
            switch hSector {
            case 0: (rPrime, gPrime, bPrime) = (c, x, 0)
            case 1: (rPrime, gPrime, bPrime) = (x, c, 0)
            case 2: (rPrime, gPrime, bPrime) = (0, c, x)
            case 3: (rPrime, gPrime, bPrime) = (0, x, c)
            case 4: (rPrime, gPrime, bPrime) = (x, 0, c)
            default: (rPrime, gPrime, bPrime) = (c, 0, x)
            }

            data[idx] = clampByte((rPrime + m) * 255.0)
            data[idx + 1] = clampByte((gPrime + m) * 255.0)
            data[idx + 2] = clampByte((bPrime + m) * 255.0)
        }
    }

    private static func applyScurveTonemap(
        _ data: inout [UInt8],
        strength: Double,
        shadowBoost: Double,
        highlightCompress: Double,
        midpoint: Double
    ) {
        if strength == 0 {
            return
        }
        for idx in stride(from: 0, to: data.count, by: 4) {
            for channel in 0..<3 {
                let normalized = Double(data[idx + channel]) / 255.0
                let result: Double
                if normalized <= midpoint {
                    let shadowVal = normalized / midpoint
                    result = pow(shadowVal, 1.0 - strength * shadowBoost) * midpoint
                } else {
                    let highlightVal = (normalized - midpoint) / (1.0 - midpoint)
                    result = midpoint + pow(highlightVal, 1.0 + strength * highlightCompress) * (1.0 - midpoint)
                }
                data[idx + channel] = clampByte(result * 255.0)
            }
        }
    }

    private static func applyFloydSteinbergDither(
        _ data: inout [UInt8],
        width: Int,
        height: Int,
        method: ImageOptimizeParams.ColorMethod,
        outputPalette: [RGB],
        ditherPalette: [RGB]
    ) {
        var currErrors = [Int](repeating: 0, count: width * 3)
        var nextErrors = [Int](repeating: 0, count: width * 3)

        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let errIdx = x * 3

                var oldR = Int(data[idx]) + currErrors[errIdx]
                var oldG = Int(data[idx + 1]) + currErrors[errIdx + 1]
                var oldB = Int(data[idx + 2]) + currErrors[errIdx + 2]

                oldR = max(0, min(255, oldR))
                oldG = max(0, min(255, oldG))
                oldB = max(0, min(255, oldB))

                let colorIdx = findClosestColor(r: oldR, g: oldG, b: oldB, method: method, palette: ditherPalette)
                let outColor = outputPalette[colorIdx]
                data[idx] = UInt8(outColor.r)
                data[idx + 1] = UInt8(outColor.g)
                data[idx + 2] = UInt8(outColor.b)

                let diffColor = ditherPalette[colorIdx]
                let errR = oldR - diffColor.r
                let errG = oldG - diffColor.g
                let errB = oldB - diffColor.b

                if x + 1 < width {
                    currErrors[(x + 1) * 3] += errR * 7 / 16
                    currErrors[(x + 1) * 3 + 1] += errG * 7 / 16
                    currErrors[(x + 1) * 3 + 2] += errB * 7 / 16
                }
                if y + 1 < height {
                    if x > 0 {
                        nextErrors[(x - 1) * 3] += errR * 3 / 16
                        nextErrors[(x - 1) * 3 + 1] += errG * 3 / 16
                        nextErrors[(x - 1) * 3 + 2] += errB * 3 / 16
                    }
                    nextErrors[x * 3] += errR * 5 / 16
                    nextErrors[x * 3 + 1] += errG * 5 / 16
                    nextErrors[x * 3 + 2] += errB * 5 / 16
                    if x + 1 < width {
                        nextErrors[(x + 1) * 3] += errR * 1 / 16
                        nextErrors[(x + 1) * 3 + 1] += errG * 1 / 16
                        nextErrors[(x + 1) * 3 + 2] += errB * 1 / 16
                    }
                }
            }
            let temp = currErrors
            currErrors = nextErrors
            nextErrors = temp
            nextErrors = [Int](repeating: 0, count: width * 3)
        }
    }

    private static func findClosestColor(
        r: Int,
        g: Int,
        b: Int,
        method: ImageOptimizeParams.ColorMethod,
        palette: [RGB]
    ) -> Int {
        var minDist = Double.greatestFiniteMagnitude
        var closest = 1
        if method == .lab {
            let inputLab = rgbToLab(r: r, g: g, b: b)
            for i in 0..<palette.count where i != 4 {
                let lab = paletteLAB[i]
                let dist = deltaE(inputLab, lab)
                if dist < minDist {
                    minDist = dist
                    closest = i
                }
            }
            return closest
        }

        for i in 0..<palette.count where i != 4 {
            let color = palette[i]
            let dr = Double(r - color.r)
            let dg = Double(g - color.g)
            let db = Double(b - color.b)
            let dist = dr * dr + dg * dg + db * db
            if dist < minDist {
                minDist = dist
                closest = i
            }
        }
        return closest
    }

    private static func renderCover(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let scale = max(targetSize.width / image.size.width, targetSize.height / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (targetSize.width - scaledSize.width) / 2, y: (targetSize.height - scaledSize.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    private static func makeImage(from data: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            return nil
        }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func clampByte(_ value: Double) -> UInt8 {
        return UInt8(max(0, min(255, Int(value.rounded()))))
    }

    private static func rgbToLab(r: Int, g: Int, b: Int) -> (Double, Double, Double) {
        let (x, y, z) = rgbToXyz(r: Double(r), g: Double(g), b: Double(b))
        return xyzToLab(x: x, y: y, z: z)
    }

    private static func rgbToXyz(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        var r = r / 255.0
        var g = g / 255.0
        var b = b / 255.0

        r = r > 0.04045 ? pow((r + 0.055) / 1.055, 2.4) : r / 12.92
        g = g > 0.04045 ? pow((g + 0.055) / 1.055, 2.4) : g / 12.92
        b = b > 0.04045 ? pow((b + 0.055) / 1.055, 2.4) : b / 12.92

        let x = r * 0.4124564 + g * 0.3575761 + b * 0.1804375
        let y = r * 0.2126729 + g * 0.7151522 + b * 0.072175
        let z = r * 0.0193339 + g * 0.119192 + b * 0.9503041
        return (x * 100.0, y * 100.0, z * 100.0)
    }

    private static func xyzToLab(x: Double, y: Double, z: Double) -> (Double, Double, Double) {
        var x = x / 95.047
        var y = y / 100.0
        var z = z / 108.883

        x = x > 0.008856 ? pow(x, 1.0 / 3.0) : 7.787 * x + 16.0 / 116.0
        y = y > 0.008856 ? pow(y, 1.0 / 3.0) : 7.787 * y + 16.0 / 116.0
        z = z > 0.008856 ? pow(z, 1.0 / 3.0) : 7.787 * z + 16.0 / 116.0

        let L = 116.0 * y - 16.0
        let a = 500.0 * (x - y)
        let b = 200.0 * (y - z)
        return (L, a, b)
    }

    private static func deltaE(_ lab1: (Double, Double, Double), _ lab2: (Double, Double, Double)) -> Double {
        let dL = lab1.0 - lab2.0
        let da = lab1.1 - lab2.1
        let db = lab1.2 - lab2.2
        return sqrt(dL * dL + da * da + db * db)
    }
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
