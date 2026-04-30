#!/usr/bin/env swift

import AppKit
import Foundation

// Keep design in sync with AppIcon in Sources/notion-tabs-ui/main.swift.

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <output.icns>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: args[1])

func render(px: Int) -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Failed to allocate bitmap for size \(px)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let cornerRadius = CGFloat(px) * (224.0 / 1024.0)
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    NSGradient(colors: [
        NSColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0),
        NSColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1.0),
    ])?.draw(in: rect, angle: -90)

    let cardW = CGFloat(px) * (676.0 / 1024.0)
    let cardH = CGFloat(px) * (594.0 / 1024.0)
    let cardCorner = CGFloat(px) * (72.0 / 1024.0)
    let frontCardY = CGFloat(px) * (154.0 / 1024.0)
    let offsetStep = CGFloat(px) * (46.0 / 1024.0)
    let widthInsetStep = CGFloat(px) * (41.0 / 1024.0)
    let frontCardX = (CGFloat(px) - cardW) / 2

    let card3 = NSRect(
        x: frontCardX + widthInsetStep,
        y: frontCardY + offsetStep * 2,
        width: cardW - widthInsetStep * 2,
        height: cardH
    )
    NSColor(red: 0.58, green: 0.55, blue: 0.49, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: card3, xRadius: cardCorner, yRadius: cardCorner).fill()

    let card2 = NSRect(
        x: frontCardX + widthInsetStep / 2,
        y: frontCardY + offsetStep,
        width: cardW - widthInsetStep,
        height: cardH
    )
    NSColor(red: 0.36, green: 0.34, blue: 0.30, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: card2, xRadius: cardCorner, yRadius: cardCorner).fill()

    let card1 = NSRect(x: frontCardX, y: frontCardY, width: cardW, height: cardH)
    NSColor(red: 0.18, green: 0.17, blue: 0.15, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: card1, xRadius: cardCorner, yRadius: cardCorner).fill()

    let nFontSize = CGFloat(px) * (460.0 / 1024.0)
    let nFont = NSFont(name: "Georgia-Bold", size: nFontSize)
        ?? NSFont(name: "Times-Bold", size: nFontSize)
        ?? NSFont.systemFont(ofSize: nFontSize, weight: .black)
    let nAttrs: [NSAttributedString.Key: Any] = [
        .font: nFont,
        .foregroundColor: NSColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1.0),
    ]
    let nString = NSAttributedString(string: "N", attributes: nAttrs)
    let nSize = nString.size()
    nString.draw(at: NSPoint(
        x: card1.midX - nSize.width / 2,
        y: card1.midY - nSize.height / 2 - CGFloat(px) * (30.0 / 1024.0)
    ))

    context.flushGraphics()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for size \(px)")
    }
    return png
}

let entries: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (name, px) in entries {
    try render(px: px).write(to: iconsetURL.appendingPathComponent(name))
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments = ["-c", "icns", "-o", outputURL.path, iconsetURL.path]
try proc.run()
proc.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetURL)

guard proc.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed status=\(proc.terminationStatus)\n".utf8))
    exit(proc.terminationStatus)
}

print(outputURL.path)
