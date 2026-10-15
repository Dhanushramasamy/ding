import AppKit
import CoreImage
import ImageIO
import Vision

/// One of the menu's choices for who delivers a reminder.
struct Character: Identifiable, Hashable {
    enum Kind: Hashable {
        /// A Lottie animation bundled in Characters/.
        case lottie
        /// The user's own picture, in Application Support.
        case image
    }

    let name: String
    let kind: Kind
    let url: URL?
    var id: String { name }
    var isCustom: Bool { kind == .image }

    /// Bundled animations (alphabetically), then the user's images.
    static var all: [Character] {
        var list: [Character] = []
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Characters"),
           let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            list += files
                .filter { $0.pathExtension.lowercased() == "json" }
                .map { Character(name: $0.deletingPathExtension().lastPathComponent, kind: .lottie, url: $0) }
                .sorted { $0.name < $1.name }
        }
        list += CustomCharacters.all
        return list
    }
}

/// The user's own images: imported, optionally cut out, and kept as PNGs in
/// ~/Library/Application Support/Ding/My Characters.
enum CustomCharacters {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Ding/My Characters", isDirectory: true)
    }

    static var all: [Character] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        return files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { creation($0) < creation($1) }
            .map { Character(name: $0.deletingPathExtension().lastPathComponent, kind: .image, url: $0) }
    }

    /// Reads any image macOS understands, upright and at a sensible size.
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect photo orientation
            kCGImageSourceThumbnailMaxPixelSize: 1600
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Lifts the main subject (person, pet, object) off its background with Apple's
    /// Vision framework, on this Mac. Returns nil when no clear subject is found.
    static func extractSubject(from image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
            let buffer = try result.generateMaskedImage(
                ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
            let masked = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(masked, from: masked.extent)
        } catch {
            return nil
        }
    }

    /// Saves the image as a new character and returns it.
    static func save(_ image: CGImage, named wanted: String) throws -> Character {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = uniqueName(wanted)
        let url = folder.appendingPathComponent(name).appendingPathExtension("png")
        let prepared = trimmed(scaledDown(image))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, prepared, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return Character(name: name, kind: .image, url: url)
    }

    static func remove(_ character: Character) {
        guard character.isCustom, let url = character.url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Helpers

    private static func creation(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func uniqueName(_ wanted: String) -> String {
        var base = wanted
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "My Character" }
        let taken = Set(Character.all.map(\.name))
        var name = base
        var n = 2
        while taken.contains(name) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    /// At most 640 px on the long side: plenty for a 190 pt character, light to load.
    private static func scaledDown(_ image: CGImage) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > 640 else { return image }
        let scale = 640 / CGFloat(longest)
        let w = Int(CGFloat(image.width) * scale), h = Int(CGFloat(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Crops away fully transparent edges, so the character's feet are the image's bottom.
    private static func trimmed(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) ?? image
    }
}
