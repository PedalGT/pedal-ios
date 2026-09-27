import UIKit
import Vision

/// End-of-ride photo check, fully on device (Apple Vision, no model to download,
/// no network). Deliberately basic for the proof of concept:
/// - bike: Vision's built-in image classifier, looking for bicycle/scooter labels
/// - color: dominant color of the most "object-like" region of the photo
/// - condition: a rough call from detection confidence and exposure
struct BikePhotoResult: Equatable {
    let bikeDetected: Bool
    let confidence: Double
    let detectedColor: String?
    let expectedColor: String?
    let condition: String

    /// nil when the bike has no color on file or the photo's color is unclear.
    var colorMatches: Bool? {
        guard let expectedColor, let detectedColor else { return nil }
        return BikeColors.matches(expected: expectedColor, detected: detectedColor)
    }

    var passed: Bool { bikeDetected && colorMatches != false }

    /// Sent with /api/rides/end.
    var serverPayload: [String: Any] {
        [
            "bikeDetected": bikeDetected,
            "confidence": confidence,
            "detectedColor": detectedColor ?? NSNull(),
            "colorMatches": colorMatches.map { $0 as Any } ?? NSNull(),
            "condition": condition
        ]
    }
}

enum BikeColors {
    /// Same list as BIKE_COLORS on the server.
    static let all = ["black", "white", "silver", "red", "orange", "yellow", "green", "blue", "purple", "pink"]

    /// Colors a camera easily confuses count as the same.
    private static let families: [Set<String>] = [["white", "silver"], ["red", "pink"], ["orange", "yellow"], ["blue", "purple"]]

    static func matches(expected: String, detected: String) -> Bool {
        let e = expected.lowercased(), d = detected.lowercased()
        return e == d || families.contains { $0.contains(e) && $0.contains(d) }
    }
}

enum BikePhotoChecker {
    private static let bikeWords = ["bicycle", "bike", "cycling", "scooter", "tricycle"]
    private static let detectionThreshold = 0.2

    static func check(_ photo: UIImage, expectedColor: String?) async throws -> BikePhotoResult {
        try await Task.detached(priority: .userInitiated) {
            // Redraw upright and small: Vision and the pixel sampling then agree on
            // coordinates, and it's fast.
            guard let image = upright(photo, maxSide: 1024)?.cgImage else {
                throw CheckError.unreadable
            }

            let classify = VNClassifyImageRequest()
            let saliency = VNGenerateObjectnessBasedSaliencyImageRequest()
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([classify, saliency])

            let labels = classify.results ?? []
            let bikeConfidence = labels
                .filter { label in bikeWords.contains { label.identifier.lowercased().contains($0) } }
                .map { Double($0.confidence) }
                .max() ?? 0
            let detected = bikeConfidence >= detectionThreshold

            let box = (saliency.results?.first?.salientObjects?.first?.boundingBox)
                ?? CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
            let sample = sampleColors(image, normalizedBox: box)

            let condition: String
            if !detected {
                condition = "Unknown"
            } else if sample.brightness < 0.15 {
                condition = "Too dark to tell"
            } else if bikeConfidence >= 0.5 {
                condition = "Good"
            } else {
                condition = "Fair"
            }

            return BikePhotoResult(
                bikeDetected: detected,
                confidence: bikeConfidence,
                detectedColor: sample.colorName,
                expectedColor: expectedColor,
                condition: condition
            )
        }.value
    }

    enum CheckError: LocalizedError {
        case unreadable
        var errorDescription: String? { "Couldn't read that photo. Try taking it again." }
    }

    // MARK: - Image helpers

    private static func upright(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Dominant color inside `normalizedBox` (Vision coordinates, origin bottom-left).
    private static func sampleColors(_ image: CGImage, normalizedBox box: CGRect) -> (colorName: String?, brightness: Double) {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let crop = CGRect(x: box.minX * w, y: (1 - box.maxY) * h, width: box.width * w, height: box.height * h).integral
        guard let region = image.cropping(to: crop) else { return (nil, 0) }

        // Draw into a tiny RGBA buffer and read the pixels back.
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (nil, 0) }
        ctx.draw(region, in: CGRect(x: 0, y: 0, width: side, height: side))

        var hueBins = [Double](repeating: 0, count: 12)
        var colored = 0, total = 0
        var brightnessSum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let v = maxC, s = maxC == 0 ? 0 : (maxC - minC) / maxC
            brightnessSum += v
            total += 1
            guard s > 0.35, v > 0.2 else { continue }
            colored += 1
            var hue: Double
            let d = maxC - minC
            if maxC == r { hue = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { hue = 60 * ((b - r) / d + 2) }
            else { hue = 60 * ((r - g) / d + 4) }
            if hue < 0 { hue += 360 }
            hueBins[min(11, Int(hue / 30))] += s * v
        }
        let brightness = total > 0 ? brightnessSum / Double(total) : 0

        // Mostly gray pixels: call it by brightness.
        if Double(colored) / Double(max(total, 1)) < 0.12 {
            return (brightness < 0.3 ? "black" : brightness > 0.75 ? "white" : "silver", brightness)
        }
        let bin = hueBins.indices.max { hueBins[$0] < hueBins[$1] } ?? 0
        let hue = Double(bin) * 30 + 15
        let name: String
        switch hue {
        case ..<20, 340...: name = "red"
        case ..<45: name = "orange"
        case ..<70: name = "yellow"
        case ..<165: name = "green"
        case ..<255: name = "blue"
        case ..<290: name = "purple"
        default: name = "pink"
        }
        return (name, brightness)
    }
}
