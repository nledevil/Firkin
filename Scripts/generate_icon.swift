#!/usr/bin/env swift
// Renders the Firkin app icon (an ale cask on a slate squircle) with AppKit,
// writes an .iconset at every macOS size, and assembles Icon.icns at the repo
// root. Pure code so the icon is reproducible without design tools or Xcode:
//
//   swift Scripts/generate_icon.swift
//
// All geometry is in a 1024pt canvas and scaled per size. Fine details are
// dropped below 64px so the small sizes stay legible.

import AppKit

// MARK: Palette

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let backgroundTop = srgb(0x4A5A72)
let backgroundBottom = srgb(0x26303F)
let amberTop = srgb(0xF2B34F)
let amberBottom = srgb(0xAD6A1C)
let staveBrown = srgb(0x7A4A16, alpha: 0.45)
let hoopTop = srgb(0x5E3B15)
let hoopBottom = srgb(0x38220A)
let bungFill = srgb(0x6E4114)
let bungRing = srgb(0x452809)
let foamCream = srgb(0xF7E9C8)

// MARK: Barrel geometry (1024pt canvas)

let canvas: CGFloat = 1024
let barrelCenterX: CGFloat = 512
let barrelTopY: CGFloat = 780
let barrelBottomY: CGFloat = 240
let barrelEndHalfWidth: CGFloat = 170 // at top and bottom
let barrelMidHalfWidth: CGFloat = 225 // at the bulge

/// Half-width of the barrel at height y: quadratic bulge that hits
/// `barrelEndHalfWidth` at both ends and `barrelMidHalfWidth` in the middle.
func barrelHalfWidth(at y: CGFloat) -> CGFloat {
    let t = (y - barrelBottomY) / (barrelTopY - barrelBottomY)
    let pinch = (2 * t - 1) * (2 * t - 1)
    return barrelMidHalfWidth - (barrelMidHalfWidth - barrelEndHalfWidth) * pinch
}

func barrelPath() -> NSBezierPath {
    let path = NSBezierPath()
    let left = barrelCenterX - barrelEndHalfWidth
    let right = barrelCenterX + barrelEndHalfWidth
    // Side bulges are cubic curves whose control points push out past the
    // mid half-width so the rendered curve lands close to it.
    let sideControl = barrelMidHalfWidth + 35
    path.move(to: NSPoint(x: left, y: barrelTopY))
    // Top end, gently domed.
    path.curve(
        to: NSPoint(x: right, y: barrelTopY),
        controlPoint1: NSPoint(x: barrelCenterX - 60, y: barrelTopY + 26),
        controlPoint2: NSPoint(x: barrelCenterX + 60, y: barrelTopY + 26)
    )
    // Right side.
    path.curve(
        to: NSPoint(x: right, y: barrelBottomY),
        controlPoint1: NSPoint(x: barrelCenterX + sideControl, y: barrelTopY - 170),
        controlPoint2: NSPoint(x: barrelCenterX + sideControl, y: barrelBottomY + 170)
    )
    // Bottom end.
    path.curve(
        to: NSPoint(x: left, y: barrelBottomY),
        controlPoint1: NSPoint(x: barrelCenterX + 60, y: barrelBottomY - 26),
        controlPoint2: NSPoint(x: barrelCenterX - 60, y: barrelBottomY - 26)
    )
    // Left side.
    path.curve(
        to: NSPoint(x: left, y: barrelTopY),
        controlPoint1: NSPoint(x: barrelCenterX - sideControl, y: barrelBottomY + 170),
        controlPoint2: NSPoint(x: barrelCenterX - sideControl, y: barrelTopY - 170)
    )
    path.close()
    return path
}

/// A vertical stave seam at a fraction of the barrel width, following the bulge.
func stavePath(fraction: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 24
    for i in 0...steps {
        let y = barrelBottomY + (barrelTopY - barrelBottomY) * CGFloat(i) / CGFloat(steps)
        let point = NSPoint(x: barrelCenterX + barrelHalfWidth(at: y) * fraction, y: y)
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    return path
}

// MARK: Drawing

func drawIcon(size: Int) {
    let scale = CGFloat(size) / canvas
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let detailed = size >= 64

    // Big Sur-style layout: 824pt squircle centered on a 1024pt canvas.
    let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)

    NSGradient(starting: backgroundTop, ending: backgroundBottom)?
        .draw(in: squircle, angle: -90)

    // Barrel body with a grounding shadow.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.shadowBlurRadius = 34
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
    shadow.set()
    amberTop.setFill()
    let barrel = barrelPath()
    barrel.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(starting: amberTop, ending: amberBottom)?.draw(in: barrel, angle: -90)

    // Cylindrical shading: darker flanks, faint highlight down the middle.
    NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0.26), 0.0),
        (NSColor.black.withAlphaComponent(0), 0.24),
        (NSColor.white.withAlphaComponent(0.10), 0.5),
        (NSColor.black.withAlphaComponent(0), 0.76),
        (NSColor.black.withAlphaComponent(0.26), 1.0)
    )?.draw(in: barrel, angle: 0)

    if detailed {
        // Stave seams.
        NSGraphicsContext.current?.saveGraphicsState()
        barrel.addClip()
        staveBrown.setStroke()
        for fraction in [-0.62, -0.24, 0.24, 0.62] {
            let stave = stavePath(fraction: CGFloat(fraction))
            stave.lineWidth = 7
            stave.stroke()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // Hoops.
    for hoopCenterY in [655.0, 365.0] {
        let y = CGFloat(hoopCenterY)
        let halfWidth = barrelHalfWidth(at: y) + 12
        let band = NSRect(x: barrelCenterX - halfWidth, y: y - 22, width: halfWidth * 2, height: 44)
        let bandPath = NSBezierPath(roundedRect: band, xRadius: 14, yRadius: 14)
        NSGradient(starting: hoopTop, ending: hoopBottom)?.draw(in: bandPath, angle: -90)
        if detailed {
            NSColor.white.withAlphaComponent(0.18).setFill()
            NSRect(x: band.minX + 22, y: band.maxY - 7, width: band.width - 44, height: 5).fill()
        }
    }

    if detailed {
        // Bung.
        let bung = NSBezierPath(ovalIn: NSRect(x: barrelCenterX - 30, y: 480, width: 60, height: 60))
        bungFill.setFill()
        bung.fill()
        bungRing.setStroke()
        bung.lineWidth = 6
        bung.stroke()

        // Bubbles rising past the barrel's shoulder — the BubbleUp heritage.
        for (x, y, radius, alpha) in [(668.0, 812.0, 19.0, 0.95), (718.0, 856.0, 12.0, 0.85), (640.0, 866.0, 8.0, 0.75)] {
            foamCream.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
        }
    }
}

// MARK: Rendering + iconset assembly

func render(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap for size \(size)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: size)
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG for size \(size)")
    }
    return png
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let root = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconsetURL = root.appendingPathComponent(".build/Firkin.iconset")
let icnsURL = root.appendingPathComponent("Icon.icns")

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

// (points, scale) pairs required by iconutil.
let entries = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in entries {
    let suffix = scale == 2 ? "@2x" : ""
    let url = iconsetURL.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    try render(size: points * scale).write(to: url)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", "--output", icnsURL.path, iconsetURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(iconutil.terminationStatus)")
}
print("Wrote \(icnsURL.path)")
