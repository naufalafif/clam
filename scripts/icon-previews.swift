#!/usr/bin/env swift
// Generates multiple icon design previews at 128x128 for review
// Run: swift scripts/icon-previews.swift
// Output: icon-preview-*.png in project root

import AppKit
import CoreText

let size: CGFloat = 128

func save(_ image: NSImage, name: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:])
    else { return }
    try? data.write(to: URL(fileURLWithPath: "icon-preview-\(name).png"))
    print("  \(name)")
}

func makeImage(_ draw: (CGContext, CGFloat) -> Void) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        // White background for preview
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        draw(ctx, size)
    }
    img.unlockFocus()
    return img
}

// ─── Option A: Terminal prompt ">_" clean ───

save(makeImage { ctx, s in
    let lw: CGFloat = 2.5
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(lw)

    let cx = s / 2, cy = s / 2
    let ps: CGFloat = s * 0.22

    // ">"
    ctx.move(to: CGPoint(x: cx - ps, y: cy + ps * 0.8))
    ctx.addLine(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: cx - ps, y: cy - ps * 0.8))
    ctx.strokePath()

    // "_"
    ctx.move(to: CGPoint(x: cx + ps * 0.15, y: cy - ps * 0.8))
    ctx.addLine(to: CGPoint(x: cx + ps, y: cy - ps * 0.8))
    ctx.strokePath()
}, name: "A-terminal-prompt")

// ─── Option B: Rounded rect with ">_" ───

save(makeImage { ctx, s in
    let pad: CGFloat = s * 0.2
    let rect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.1, cornerHeight: s * 0.1, transform: nil)
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2.5)
    ctx.addPath(path)
    ctx.strokePath()

    // ">_" inside
    let cx = s / 2, cy = s / 2
    let ps: CGFloat = s * 0.15
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(2.5)

    ctx.move(to: CGPoint(x: cx - ps * 1.2, y: cy + ps * 0.8))
    ctx.addLine(to: CGPoint(x: cx - ps * 0.2, y: cy))
    ctx.addLine(to: CGPoint(x: cx - ps * 1.2, y: cy - ps * 0.8))
    ctx.strokePath()

    ctx.move(to: CGPoint(x: cx + ps * 0.1, y: cy - ps * 0.8))
    ctx.addLine(to: CGPoint(x: cx + ps * 1.2, y: cy - ps * 0.8))
    ctx.strokePath()
}, name: "B-rounded-terminal")

// ─── Option C: Stacked windows (sessions) ───

save(makeImage { ctx, s in
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2.0)
    ctx.setLineCap(.round)

    // Back window
    let r1 = CGRect(x: s * 0.28, y: s * 0.32, width: s * 0.52, height: s * 0.42)
    ctx.addPath(CGPath(roundedRect: r1, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.strokePath()

    // Front window
    let r2 = CGRect(x: s * 0.2, y: s * 0.22, width: s * 0.52, height: s * 0.42)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(CGPath(roundedRect: r2, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: r2, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.strokePath()

    // ">" in front window
    let cx = r2.midX, cy = r2.midY
    let ps: CGFloat = s * 0.08
    ctx.setLineWidth(2.2)
    ctx.move(to: CGPoint(x: cx - ps, y: cy + ps * 0.8))
    ctx.addLine(to: CGPoint(x: cx + ps * 0.3, y: cy))
    ctx.addLine(to: CGPoint(x: cx - ps, y: cy - ps * 0.8))
    ctx.strokePath()
}, name: "C-stacked-windows")

// ─── Option D: Letter "C" with terminal cursor ───

save(makeImage { ctx, s in
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(3.0)
    ctx.setLineCap(.round)

    let cx = s / 2, cy = s / 2
    let r = s * 0.28

    // "C" arc (open on the right)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r,
               startAngle: -0.8, endAngle: 0.8, clockwise: true)
    ctx.strokePath()

    // Cursor line inside the C opening
    ctx.setLineWidth(2.5)
    ctx.move(to: CGPoint(x: cx + r * 0.5, y: cy + r * 0.4))
    ctx.addLine(to: CGPoint(x: cx + r * 0.5, y: cy - r * 0.4))
    ctx.strokePath()
}, name: "D-letter-C-cursor")

// ─── Option E: Bracket pair "[ ]" with dot ───

save(makeImage { ctx, s in
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)

    let cx = s / 2, cy = s / 2
    let bw: CGFloat = s * 0.12
    let bh: CGFloat = s * 0.25

    // Left bracket "["
    ctx.move(to: CGPoint(x: cx - bw, y: cy + bh))
    ctx.addLine(to: CGPoint(x: cx - bw * 2, y: cy + bh))
    ctx.addLine(to: CGPoint(x: cx - bw * 2, y: cy - bh))
    ctx.addLine(to: CGPoint(x: cx - bw, y: cy - bh))
    ctx.strokePath()

    // Right bracket "]"
    ctx.move(to: CGPoint(x: cx + bw, y: cy + bh))
    ctx.addLine(to: CGPoint(x: cx + bw * 2, y: cy + bh))
    ctx.addLine(to: CGPoint(x: cx + bw * 2, y: cy - bh))
    ctx.addLine(to: CGPoint(x: cx + bw, y: cy - bh))
    ctx.strokePath()

    // Blinking cursor dot in center
    ctx.setFillColor(NSColor.black.cgColor)
    let dotR: CGFloat = s * 0.035
    ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
}, name: "E-brackets-dot")

// ─── Option F: Circle with ">" (minimal) ───

save(makeImage { ctx, s in
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(2.2)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let cx = s / 2, cy = s / 2
    let r = s * 0.3

    // Circle
    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))

    // ">" centered
    let ps: CGFloat = s * 0.1
    ctx.setLineWidth(2.5)
    ctx.move(to: CGPoint(x: cx - ps * 0.6, y: cy + ps))
    ctx.addLine(to: CGPoint(x: cx + ps * 0.6, y: cy))
    ctx.addLine(to: CGPoint(x: cx - ps * 0.6, y: cy - ps))
    ctx.strokePath()
}, name: "F-circle-chevron")

// ─── Option G: Three horizontal lines + ">" (session list) ───

save(makeImage { ctx, s in
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(2.2)

    let cx = s / 2, cy = s / 2
    let lineW: CGFloat = s * 0.22
    let gap: CGFloat = s * 0.09

    // Three lines (like a list)
    for i in -1...1 {
        let y = cy + CGFloat(i) * gap
        ctx.move(to: CGPoint(x: cx - lineW * 0.3, y: y))
        ctx.addLine(to: CGPoint(x: cx + lineW, y: y))
        ctx.strokePath()
    }

    // ">" on the left
    let ps: CGFloat = s * 0.07
    let px = cx - lineW * 0.6
    ctx.setLineWidth(2.5)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: px - ps, y: cy + ps * 1.2))
    ctx.addLine(to: CGPoint(x: px + ps * 0.5, y: cy))
    ctx.addLine(to: CGPoint(x: px - ps, y: cy - ps * 1.2))
    ctx.strokePath()
}, name: "G-list-chevron")

print("Done! Review icon-preview-*.png files")
