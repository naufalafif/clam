#!/usr/bin/env swift
// Generates AppIcon.icns using SF Symbol "fossil.shell.fill"
// Run from project root: swift scripts/generate-icon.swift

import AppKit

func drawAppIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.22

    // Rounded rect background
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Purple gradient
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.55, green: 0.33, blue: 0.98, alpha: 1.0),
        CGColor(red: 0.25, green: 0.12, blue: 0.68, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    }

    // Draw SF Symbol centered
    if let symbolImage = NSImage(systemSymbolName: "fossil.shell.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .medium)
        let configured = symbolImage.withSymbolConfiguration(config) ?? symbolImage

        // Get symbol size
        let symbolSize = configured.size
        let x = (size - symbolSize.width) / 2
        let y = (size - symbolSize.height) / 2

        // Draw white symbol
        NSGraphicsContext.current?.cgContext.saveGState()
        let symbolRect = NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height)

        // Tint white
        let tinted = NSImage(size: symbolSize)
        tinted.lockFocus()
        NSColor.white.withAlphaComponent(0.95).set()
        configured.draw(in: NSRect(origin: .zero, size: symbolSize))
        NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        tinted.draw(in: symbolRect)
        NSGraphicsContext.current?.cgContext.restoreGState()
    }

    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:])
    else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

// Generate iconset
let iconsetPath = "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(CGFloat, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    savePNG(drawAppIcon(size: size), to: "\(iconsetPath)/\(name)")
}
print("Generated iconset")

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetPath, "-o", "AppIcon.icns"]
try proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconsetPath)

if proc.terminationStatus == 0 {
    print("AppIcon.icns generated")
} else {
    print("iconutil failed")
}
