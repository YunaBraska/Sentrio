#!/usr/bin/env swift

import AppKit
import Foundation

enum ScreenshotError: Error, CustomStringConvertible {
    case invalidArguments
    case missingImage(String)
    case bitmapUnavailable
    case encodingFailed

    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: compose-app-store-screenshots.swift INPUT_DIR OUTPUT_DIR"
        case let .missingImage(path):
            "Missing screenshot: \(path)"
        case .bitmapUnavailable:
            "Unable to create the screenshot bitmap."
        case .encodingFailed:
            "Unable to encode a screenshot as PNG."
        }
    }
}

struct ScreenshotSpec {
    let filename: String
    let title: String
    let subtitle: String
    let detailImage: String
}

let specs = [
    ScreenshotSpec(
        filename: "01-audio-priorities.png",
        title: "Audio devices, in your order",
        subtitle: "Fast switching from the menu bar. Full control in Settings.",
        detailImage: "preferences_output.png"
    ),
    ScreenshotSpec(
        filename: "02-input-routing.png",
        title: "Input routing without surprises",
        subtitle: "Keep microphones prioritized and their levels ready.",
        detailImage: "preferences_input.png"
    ),
    ScreenshotSpec(
        filename: "03-busylight-automation.png",
        title: "BusyLight automation at a glance",
        subtitle: "Turn microphone, camera, screen, and media activity into clear signals.",
        detailImage: "preferences_busy_light.png"
    ),
]

func loadImage(named name: String, from directory: URL) throws -> NSImage {
    let url = directory.appendingPathComponent(name)
    guard let image = NSImage(contentsOf: url) else {
        throw ScreenshotError.missingImage(url.path)
    }
    return image
}

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    text.draw(at: point, withAttributes: attributes)
}

func drawImage(_ image: NSImage, in rect: NSRect, verticalCropFraction: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    let crop = image.size.height * verticalCropFraction
    image.draw(
        in: rect,
        from: NSRect(
            x: 0,
            y: crop,
            width: image.size.width,
            height: image.size.height - (crop * 2)
        ),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    NSGraphicsContext.restoreGraphicsState()
}

func render(spec: ScreenshotSpec, inputDirectory: URL, outputDirectory: URL) throws {
    let menuImage = try loadImage(named: "bar_menu.png", from: inputDirectory)
    let detailImage = try loadImage(named: spec.detailImage, from: inputDirectory)
    guard let drawingContext = CGContext(
        data: nil,
        width: 1280,
        height: 800,
        bitsPerComponent: 8,
        bytesPerRow: 1280 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        throw ScreenshotError.bitmapUnavailable
    }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(cgContext: drawingContext, flipped: false)
    NSGraphicsContext.current = context

    NSGradient(
        starting: NSColor(calibratedRed: 0.91, green: 0.95, blue: 1, alpha: 1),
        ending: NSColor(calibratedRed: 0.98, green: 0.97, blue: 1, alpha: 1)
    )?.draw(in: NSRect(x: 0, y: 0, width: 1280, height: 800), angle: 12)

    drawText(
        spec.title,
        at: NSPoint(x: 72, y: 714),
        font: .systemFont(ofSize: 42, weight: .bold),
        color: NSColor(calibratedWhite: 0.12, alpha: 1)
    )
    drawText(
        spec.subtitle,
        at: NSPoint(x: 74, y: 674),
        font: .systemFont(ofSize: 21, weight: .medium),
        color: NSColor(calibratedWhite: 0.32, alpha: 1)
    )

    let imageHeight: CGFloat = 590
    let menuCropFraction: CGFloat = 0.105
    let visibleMenuHeight = menuImage.size.height * (1 - (menuCropFraction * 2))
    let menuWidth = imageHeight * menuImage.size.width / visibleMenuHeight
    let detailWidth = imageHeight * detailImage.size.width / detailImage.size.height
    let gap: CGFloat = 36
    let totalWidth = menuWidth + gap + detailWidth
    let left = (1280 - totalWidth) / 2
    let bottom: CGFloat = 42

    drawImage(
        menuImage,
        in: NSRect(x: left, y: bottom, width: menuWidth, height: imageHeight),
        verticalCropFraction: menuCropFraction
    )
    drawImage(
        detailImage,
        in: NSRect(x: left + menuWidth + gap, y: bottom, width: detailWidth, height: imageHeight)
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let image = drawingContext.makeImage() else {
        throw ScreenshotError.bitmapUnavailable
    }
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotError.encodingFailed
    }
    try data.write(to: outputDirectory.appendingPathComponent(spec.filename), options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw ScreenshotError.invalidArguments
    }
    let inputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for spec in specs {
        try render(spec: spec, inputDirectory: inputDirectory, outputDirectory: outputDirectory)
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
