// Renders the app icon (shared DockIcon shape) into a proper .icns bundle.
// Invoked by Scripts/build.sh — not run by hand. Uses the exact same
// `DockIcon` shape source the app renders at runtime, so the on-disk bundle
// icon can never drift from `applicationIconImage`.

import AppKit
import Foundation
import SwiftUI

struct IconSpec {
    let filename: String
    let pixels: Int
}

let iconSpecs: [IconSpec] = [
    IconSpec(filename: "icon_16x16.png", pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixels: 32),
    IconSpec(filename: "icon_32x32.png", pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixels: 64),
    IconSpec(filename: "icon_128x128.png", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixels: 256),
    IconSpec(filename: "icon_256x256.png", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixels: 512),
    IconSpec(filename: "icon_512x512.png", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixels: 1024)
]

@main
struct RenderAppIcon {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: render_icon <output.icns>\n".utf8))
            exit(2)
        }
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

        let iconsetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mouse-sentinel-iconset-\(UUID().uuidString).iconset")

        try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

        for spec in iconSpecs {
            guard let image = DockIcon.image(canvas: 1024, scale: CGFloat(spec.pixels) / 1024.0),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw IconRenderError.renderFailed(spec.filename)
            }

            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                throw IconRenderError.pngEncodingFailed(spec.filename)
            }

            try pngData.write(to: iconsetDir.appendingPathComponent(spec.filename))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputURL.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw IconRenderError.iconutilFailed(process.terminationStatus)
        }

        try FileManager.default.removeItem(at: iconsetDir)
    }
}

enum IconRenderError: Error, CustomStringConvertible {
    case renderFailed(String)
    case pngEncodingFailed(String)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case .renderFailed(let name):
            return "Failed to render \(name)"
        case .pngEncodingFailed(let name):
            return "Failed to encode \(name) as PNG"
        case .iconutilFailed(let status):
            return "iconutil exited with status \(status)"
        }
    }
}