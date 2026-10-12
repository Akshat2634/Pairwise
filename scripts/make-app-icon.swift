#!/usr/bin/env swift
// Draws the PairDesk app icon (the two linked displays from
// assets/pairwise-logo.svg on the Theme purple) at every macOS icon size and
// packs them into macos/Resources/PairDesk.icns.
//
//   swift scripts/make-app-icon.swift [output.icns]
//
// Run it again after changing the artwork below, and commit the .icns.
import AppKit
import Foundation

let arguments = CommandLine.arguments
let scriptDirectory = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
let defaultOutput = scriptDirectory.appendingPathComponent("../macos/Resources/PairDesk.icns").standardizedFileURL
let output = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : defaultOutput

/// Draws on a 1024-point canvas with the origin at the top left.
func draw(in context: CGContext, scale: CGFloat) {
    context.translateBy(x: 0, y: 1024 * scale)
    context.scaleBy(x: scale, y: -scale)

    // Apple's macOS icon grid: an 824-point rounded square centered in 1024.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let plateShape = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.addPath(plateShape)
    context.clip()
    let colors = [CGColor(srgbRed: 0x7E / 255, green: 0x72 / 255, blue: 0xEC / 255, alpha: 1),
                  CGColor(srgbRed: 0x53 / 255, green: 0x46 / 255, blue: 0xC4 / 255, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.minY), end: CGPoint(x: plate.maxX, y: plate.maxY), options: [])
    context.restoreGState()

    // The mark, taken from the logo's 112-point grid and scaled to the plate.
    let s: CGFloat = 5.6
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 56) * s + 512, y: (y - 54.5) * s + 512) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        let origin = point(x, y)
        return CGRect(x: origin.x, y: origin.y, width: w * s, height: h * s)
    }
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(7 * s)
    for display in [rect(11, 18, 62, 48), rect(39, 43, 62, 48)] {
        context.addPath(CGPath(roundedRect: display, cornerWidth: 12 * s, cornerHeight: 12 * s, transform: nil))
        context.strokePath()
    }
    context.setLineWidth(5 * s)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
    context.move(to: point(33, 78)); context.addLine(to: point(42, 78)); context.strokePath()
    context.move(to: point(72, 49)); context.addLine(to: point(81, 49)); context.strokePath()
    for (center, color) in [(point(35, 78), CGColor(srgbRed: 0x45 / 255, green: 0xE0 / 255, blue: 0xC1 / 255, alpha: 1)),
                            (point(86, 49), CGColor(srgbRed: 0xF3 / 255, green: 0x8B / 255, blue: 0xD6 / 255, alpha: 1))] {
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: center.x - 5 * s, y: center.y - 5 * s, width: 10 * s, height: 10 * s))
    }
}

func render(pixels: Int) -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    draw(in: context, scale: CGFloat(pixels) / 1024)
    let image = context.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("PairDesk-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fputs("iconutil failed\n", stderr); exit(1) }
print("Wrote \(output.path)")
