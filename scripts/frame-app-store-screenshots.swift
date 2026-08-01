#!/usr/bin/env swift

import AppKit
import Foundation

struct ScreenshotSpec {
    let language: String
    let sourceName: String
    let caption: String
}

let specs = [
    ScreenshotSpec(language: "en", sourceName: "01-dashboard", caption: "Separate accounts.\nOne clear balance."),
    ScreenshotSpec(language: "en", sourceName: "02-editor", caption: "Add an expense\nin seconds."),
    ScreenshotSpec(language: "en", sourceName: "03-voice", caption: "Just say it. Review it.\nSave it."),
    ScreenshotSpec(language: "en", sourceName: "04-settings", caption: "Your data stays\non your iPhone."),
    ScreenshotSpec(language: "en", sourceName: "05-widgets", caption: "Capture it before\nyou forget."),
    ScreenshotSpec(language: "de", sourceName: "01-dashboard", caption: "Getrennte Konten.\nKlare Bilanz."),
    ScreenshotSpec(language: "de", sourceName: "02-editor", caption: "In Sekunden eine\nAusgabe erfassen."),
    ScreenshotSpec(language: "de", sourceName: "03-voice", caption: "Sagen. Prüfen.\nSpeichern."),
    ScreenshotSpec(language: "de", sourceName: "04-settings", caption: "Eure Daten bleiben\nauf dem iPhone."),
    ScreenshotSpec(language: "de", sourceName: "05-widgets", caption: "Erfassen, bevor\nes vergessen ist.")
]

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let screenshotRoot = root.appendingPathComponent("AppStore/screenshots")
let iconURL = root.appendingPathComponent("Maeuse/Assets.xcassets/CoinMouseMark.imageset/CoinMouseMark@3x.png")

guard let brandIcon = NSImage(contentsOf: iconURL) else {
    fputs("Could not load brand icon at \(iconURL.path)\n", stderr)
    exit(1)
}

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

let canvasSize = NSSize(width: 1320, height: 2868)
let screenshotRect = NSRect(x: 132, y: 92, width: 1056, height: 2294.4)
let frameRect = screenshotRect.insetBy(dx: -12, dy: -12)

for spec in specs {
    let sourceURL = screenshotRoot
        .appendingPathComponent("raw")
        .appendingPathComponent(spec.language)
        .appendingPathComponent("\(spec.sourceName).png")
    let outputDirectory = screenshotRoot
        .appendingPathComponent("framed")
        .appendingPathComponent(spec.language)
    let outputURL = outputDirectory.appendingPathComponent("\(spec.sourceName).png")

    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    guard let source = NSImage(contentsOf: sourceURL) else {
        fputs("Could not load \(sourceURL.path)\n", stderr)
        exit(1)
    }

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fputs("Could not create bitmap context\n", stderr)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    color(0xFFF6DE).setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    color(0x241C05).setFill()
    NSBezierPath(roundedRect: frameRect, xRadius: 58, yRadius: 58).fill()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenshotRect, xRadius: 48, yRadius: 48).addClip()
    source.draw(in: screenshotRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    let baseFont = NSFont.systemFont(ofSize: 88, weight: .heavy)
    let roundedDescriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
    let captionFont = NSFont(descriptor: roundedDescriptor, size: 88) ?? baseFont
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineSpacing = -4

    let captionAttributes: [NSAttributedString.Key: Any] = [
        .font: captionFont,
        .foregroundColor: color(0x241C05),
        .paragraphStyle: paragraph
    ]
    let captionRect = NSRect(x: 150, y: 2460, width: 890, height: 300)
    NSString(string: spec.caption).draw(with: captionRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: captionAttributes)

    brandIcon.draw(in: NSRect(x: 1090, y: 2600, width: 110, height: 110), from: .zero, operation: .sourceOver, fraction: 1)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Could not encode \(outputURL.path)\n", stderr)
        exit(1)
    }
    try png.write(to: outputURL, options: .atomic)
    print(outputURL.path)
}
