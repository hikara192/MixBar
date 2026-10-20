#!/usr/bin/env swift
// MixBar app icon generator.
//
// Headless: draws the icon with Core Graphics (no window server, no AppKit UI)
// and writes an .iconset folder of PNGs. Scripts/make-icon.sh feeds that folder
// to `iconutil` to produce AppResources/AppIcon.icns.
//
// Usage:
//   swift Scripts/make-icon.swift --outdir /tmp/AppIcon.iconset
//   swift Scripts/make-icon.swift --outdir /tmp/x --preview /tmp/preview.png
//
// The artwork is vector-drawn per target size (not one bitmap downscaled), so
// 16x16 gets thicker faders and a tighter margin instead of a grey blur.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

private func rgba(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(colorSpace: srgb, components: [r, g, b, alpha])!
}

private let graphiteTop = rgba(0x424954)
private let graphiteMid = rgba(0x23272D)
private let graphiteBottom = rgba(0x101214)
private let trackFill = rgba(0x080A0D, 0.62)
private let accentLight = rgba(0x9BF8E2)
private let accentMint = rgba(0x4FE6C5)
private let accentTeal = rgba(0x16B79B)
private let accentDeep = rgba(0x0E8E78)

// MARK: - Primitives

/// Continuous-curvature rounded square (superellipse). n = 5 closely matches
/// the silhouette of the macOS Big Sur+ icon mask (824pt shape on 1024 canvas).
private func squirclePath(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        if i == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

private func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)!
}

private func clipFillLinear(
    _ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], _ locations: [CGFloat],
    from: CGPoint, to: CGPoint
) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(colors, locations), start: from, end: to,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

private func clipFillRadial(
    _ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], _ locations: [CGFloat],
    center: CGPoint, radius: CGFloat
) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient(colors, locations), startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// Stroke a path with a horizontal alpha ramp so decorative lines fade out.
private func strokeFadingHorizontally(
    _ ctx: CGContext, _ path: CGPath, width: CGFloat,
    color: CGColor, from: CGPoint, to: CGPoint
) {
    let stroked = path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
    let transparent = color.copy(alpha: 0)!
    ctx.saveGState()
    ctx.addPath(stroked)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([transparent, color, color, transparent], [0, 0.18, 0.82, 1]),
        start: from, end: to,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// MARK: - Artwork

private func renderIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // System icons keep a 100/1024 margin around the 824pt shape. Small slots
    // get a slightly tighter margin so the glyph stays readable at 16pt.
    let tiny = size <= 32
    let marginFraction: CGFloat = size >= 128 ? 100.0 / 1024.0 : (size >= 64 ? 0.055 : 0.030)
    let margin = s * marginFraction
    let shapeRect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let shape = squirclePath(in: shapeRect)
    let sw = shapeRect.width

    // Everything below is expressed relative to the shape, so the composition
    // is identical at every size.
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: shapeRect.minX + x * sw, y: shapeRect.minY + y * sw)
    }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(
            x: shapeRect.minX + x * sw, y: shapeRect.minY + y * sw,
            width: w * sw, height: h * sw)
    }

    // 1. Soft drop shadow (skipped at tiny sizes where it only muddies pixels).
    if size >= 64 {
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -0.012 * s), blur: 0.032 * s,
            color: rgba(0x000000, 0.42))
        ctx.addPath(shape)
        ctx.setFillColor(rgba(0x101214))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 2. Graphite body: vertical gradient + top sheen + accent ambience.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([graphiteTop, graphiteMid, graphiteBottom], [0, 0.52, 1]),
        start: pt(0.5, 1.0), end: pt(0.5, 0.0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    clipFillRadial(
        ctx, shape, [rgba(0xFFFFFF, 0.11), rgba(0xFFFFFF, 0.03), rgba(0xFFFFFF, 0.0)],
        [0, 0.55, 1], center: pt(0.5, 1.02), radius: 0.72 * sw)
    clipFillRadial(
        ctx, shape, [rgba(0x37E3C0, 0.10), rgba(0x37E3C0, 0.035), rgba(0x37E3C0, 0.0)],
        [0, 0.55, 1], center: pt(0.5, 0.44), radius: 0.66 * sw)

    // 3. Sound wave: a quiet signature under the faders.
    if size >= 64 {
        let wave = CGMutablePath()
        let baseY: CGFloat = 0.108
        let amplitude: CGFloat = 0.026
        let periods: CGFloat = 2.5
        let steps = 160
        for i in 0...steps {
            let u = CGFloat(i) / CGFloat(steps)
            let envelope = pow(sin(.pi * u), 0.75)
            let y = baseY + amplitude * envelope * sin(2 * .pi * periods * u)
            let p = pt(0.29 + 0.42 * u, y)
            if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
        }
        strokeFadingHorizontally(
            ctx, wave, width: 0.010 * sw, color: rgba(0x6BEFD2, 0.48),
            from: pt(0.25, 0), to: pt(0.75, 0))
    }

    // 4. Three mixer strips.
    let stripCenters: [CGFloat] = [0.250, 0.5, 0.750]
    let knobHeights: [CGFloat] = [0.675, 0.340, 0.550]
    let stripWidth: CGFloat = tiny ? 0.145 : 0.125
    let stripBottom: CGFloat = 0.210
    let stripHeight: CGFloat = 0.615
    let stripCorner = stripWidth / 2

    for (index, cx) in stripCenters.enumerated() {
        let stripRect = rect(cx - stripWidth / 2, stripBottom, stripWidth, stripHeight)
        let strip = CGPath(
            roundedRect: stripRect, cornerWidth: stripCorner * sw, cornerHeight: stripCorner * sw,
            transform: nil)

        // Recessed channel.
        clipFillLinear(
            ctx, strip, [rgba(0x05070A, 0.66), rgba(0x05070A, 0.48)], [0, 1],
            from: pt(0, stripBottom + stripHeight), to: pt(0, stripBottom))
        ctx.saveGState()
        ctx.addPath(strip)
        ctx.clip()
        ctx.addPath(strip)
        ctx.setStrokeColor(rgba(0xFFFFFF, 0.055))
        ctx.setLineWidth(max(0.75, 0.004 * sw))
        ctx.strokePath()
        ctx.restoreGState()

        // Faint level glow rising to the knob.
        let knobCenter = stripBottom + stripHeight * knobHeights[index]
        let levelHeight = knobCenter - stripBottom
        let levelRect = rect(cx - stripWidth / 2, stripBottom, stripWidth, levelHeight)
        let level = CGPath(
            roundedRect: levelRect,
            cornerWidth: min(stripCorner, stripWidth / 2) * sw,
            cornerHeight: min(stripCorner, stripWidth / 2) * sw, transform: nil)
        clipFillLinear(
            ctx, level, [rgba(0x2BD9B7, 0.05), rgba(0x3FE7C6, 0.24)], [0, 1],
            from: pt(0, stripBottom), to: pt(0, knobCenter))

        // Fader cap.
        let knobWidth: CGFloat = tiny ? 0.215 : 0.188
        let knobHeight: CGFloat = (tiny ? 0.155 : 0.110) * (size <= 16 ? 1.12 : 1.0)
        let knobRect = rect(cx - knobWidth / 2, knobCenter - knobHeight / 2, knobWidth, knobHeight)
        let knobCorner = tiny ? knobHeight / 2 : knobHeight * 0.38
        let knob = CGPath(
            roundedRect: knobRect, cornerWidth: knobCorner * sw,
            cornerHeight: knobCorner * sw, transform: nil)

        // Accent bloom, then a crisp drop shadow, then the cap itself.
        if size >= 64 {
            ctx.saveGState()
            ctx.setShadow(
                offset: .zero, blur: 0.030 * sw, color: rgba(0x4FE6C5, 0.55))
            ctx.addPath(knob)
            ctx.setFillColor(accentTeal)
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        if size >= 64 {
            ctx.setShadow(
                offset: CGSize(width: 0, height: -0.006 * sw), blur: 0.012 * sw,
                color: rgba(0x000000, 0.40))
        }
        ctx.addPath(knob)
        ctx.clip()
        ctx.drawLinearGradient(
            gradient([accentLight, accentMint, accentTeal, accentDeep], [0, 0.42, 0.82, 1]),
            start: pt(0, knobCenter + knobHeight / 2), end: pt(0, knobCenter - knobHeight / 2),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Glossy top edge.
        ctx.drawLinearGradient(
            gradient([rgba(0xFFFFFF, 0.38), rgba(0xFFFFFF, 0.0)], [0, 1]),
            start: pt(0, knobCenter + knobHeight / 2),
            end: pt(0, knobCenter + knobHeight * 0.06),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // Centre groove, only where there are pixels for it.
        if size >= 128 {
            let groove = CGPath(
                roundedRect: rect(
                    cx - knobWidth * 0.26, knobCenter - 0.007, knobWidth * 0.52, 0.014),
                cornerWidth: 0.007 * sw, cornerHeight: 0.007 * sw, transform: nil)
            ctx.addPath(groove)
            ctx.setFillColor(rgba(0x0A6E5D, 0.35))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // 5. Inner rim light keeps the edge from dissolving into dark backgrounds.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setStrokeColor(rgba(0xFFFFFF, 0.14))
    ctx.setLineWidth(max(1, 0.004 * sw))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Output

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        throw NSError(
            domain: "make-icon", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "cannot create PNG at \(url.path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(
            domain: "make-icon", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "cannot write PNG at \(url.path)"])
    }
}

private func writePreview(to url: URL) throws {
    let cell: CGFloat = 256
    let gap: CGFloat = 28
    let sizes = [16, 32, 64, 128, 256]
    let width = CGFloat(sizes.count) * cell + CGFloat(sizes.count + 1) * gap
    let height = 2 * (cell + gap) + gap
    let ctx = CGContext(
        data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
        bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.setFillColor(rgba(0xECECEC))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    ctx.setFillColor(rgba(0x1C1C1E))
    ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))

    for row in 0...1 {
        let rowBottom = CGFloat(row) * (cell + gap) + gap
        for (i, size) in sizes.enumerated() {
            let image = renderIcon(size: size)
            let x = gap + CGFloat(i) * (cell + gap)
            ctx.draw(image, in: CGRect(x: x, y: rowBottom, width: cell, height: cell))
        }
    }
    guard let image = ctx.makeImage() else { return }
    try writePNG(image, to: url)
}

// MARK: - Main

let args = CommandLine.arguments
var outDir: URL?
var preview: URL?
var i = 1
while i < args.count {
    switch args[i] {
    case "--outdir":
        i += 1
        guard i < args.count else { fputs("--outdir needs a path\n", stderr); exit(2) }
        outDir = URL(fileURLWithPath: args[i])
    case "--preview":
        i += 1
        guard i < args.count else { fputs("--preview needs a path\n", stderr); exit(2) }
        preview = URL(fileURLWithPath: args[i])
    default:
        fputs("unknown argument: \(args[i])\n", stderr)
        exit(2)
    }
    i += 1
}
guard let outDir else {
    fputs("usage: make-icon.swift --outdir <AppIcon.iconset> [--preview <png>]\n", stderr)
    exit(2)
}

let fm = FileManager.default
do {
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

    // Distinct pixel sizes, mapped onto iconutil's required iconset names.
    let entries: [(Int, [String])] = [
        (16, ["icon_16x16.png"]),
        (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
        (64, ["icon_32x32@2x.png"]),
        (128, ["icon_128x128.png"]),
        (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
        (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
        (1024, ["icon_512x512@2x.png"]),
    ]
    for (size, names) in entries {
        let image = renderIcon(size: size)
        for name in names {
            try writePNG(image, to: outDir.appendingPathComponent(name))
        }
    }
    if let preview {
        try writePreview(to: preview)
    }
    print("Wrote \(entries.count) icon sizes to \(outDir.path)")
} catch {
    fputs("make-icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
