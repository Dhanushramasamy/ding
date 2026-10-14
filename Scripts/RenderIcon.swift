import AppKit
import SwiftUI

// Renders AppIconArtwork to a 1024×1024 PNG at the path given as the first argument.
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: AppIconArtwork().frame(width: 1024, height: 1024))
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        fatalError("Could not render the icon")
    }
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
