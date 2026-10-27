#!/usr/bin/env swift
// Run from the repository root: swift scripts/generate-icons.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("assets")
let iconset = assets.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// A socket and its cable, shared by the full-color icon and the menu bar template.
func socket(color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 10.5, y: 3, width: 3, height: 6),
                 xRadius: 1.5, yRadius: 1.5).fill()
    let shell = NSBezierPath(roundedRect: NSRect(x: 3, y: 8, width: 18, height: 12),
                            xRadius: 2.5, yRadius: 2.5)
    shell.append(NSBezierPath(roundedRect: NSRect(x: 5, y: 10, width: 14, height: 8),
                              xRadius: 1, yRadius: 1))
    shell.windingRule = .evenOdd
    shell.fill()
    for x in [7.0, 11.0, 15.0] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 14, width: 2, height: 4.5),
                     xRadius: 0.6, yRadius: 0.6).fill()
    }
}

func appIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                           xRadius: 184, yRadius: 184)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor(calibratedRed: 0.02, green: 0.24, blue: 0.28, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.64, blue: 0.64, alpha: 1),
               ending: NSColor(calibratedRed: 0.02, green: 0.27, blue: 0.34, alpha: 1))!
        .draw(in: tile, angle: -70)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: 176, byY: 176)
    (transform as NSAffineTransform).concat()
    let scale = AffineTransform(scale: 28)
    (scale as NSAffineTransform).concat()
    socket(color: NSColor(calibratedRed: 0.93, green: 0.99, blue: 0.97, alpha: 1))
    // Warm contacts give the larger icon a little character.
    NSColor(calibratedRed: 1, green: 0.78, blue: 0.40, alpha: 1).setFill()
    for x in [7.0, 11.0, 15.0] {
        NSBezierPath(roundedRect: NSRect(x: x, y: 14, width: 2, height: 3.5),
                     xRadius: 0.6, yRadius: 0.6).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

func png(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                  bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = AffineTransform(scale: CGFloat(size) / 1024)
    (scale as NSAffineTransform).concat()
    appIcon()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 2 ? "@2x" : ""
        try png(size: points * factor,
                to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(size: 1024, to: assets.appendingPathComponent("AppIcon.png"))

final class MenuBarIcon: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let scale = AffineTransform(scale: 0.75)
        (scale as NSAffineTransform).concat()
        socket(color: .black)
    }
}
let view = MenuBarIcon(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
try view.dataWithPDF(inside: view.bounds)
    .write(to: root.appendingPathComponent("Sources/Portly/Resources/MenuBarIcon.pdf"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Generated app icon and menu bar template.")
