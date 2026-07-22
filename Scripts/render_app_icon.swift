#!/usr/bin/env swift

import AppKit
import Foundation

let canvasSize = 1024
let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIconPreview.png"

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("无法创建透明图标画布")
}

bitmap.size = NSSize(width: canvasSize, height: canvasSize)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.shouldAntialias = true
context.imageInterpolation = .high
context.cgContext.clear(CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize))

let outerRect = NSRect(x: 76, y: 76, width: 872, height: 872)
let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 214, yRadius: 214)
NSColor.white.setFill()
outerPath.fill()
NSColor(calibratedWhite: 0.90, alpha: 1).setStroke()
outerPath.lineWidth = 8
outerPath.stroke()

let center = NSPoint(x: 512, y: 512)
let ringRect = NSRect(x: 252, y: 252, width: 520, height: 520)
let ringBackground = NSBezierPath(ovalIn: ringRect)
NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.95, alpha: 1).setStroke()
ringBackground.lineWidth = 82
ringBackground.stroke()

let progress = NSBezierPath()
progress.appendArc(
    withCenter: center,
    radius: 260,
    startAngle: 90,
    endAngle: -180,
    clockwise: true
)
progress.lineWidth = 82
progress.lineCapStyle = .round
NSColor(calibratedRed: 0.18, green: 0.84, blue: 0.38, alpha: 1).setStroke()
progress.stroke()

let innerPath = NSBezierPath(ovalIn: NSRect(x: 358, y: 358, width: 308, height: 308))
NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
innerPath.fill()

let needle = NSBezierPath()
needle.move(to: center)
needle.line(to: NSPoint(x: 650, y: 632))
needle.lineWidth = 42
needle.lineCapStyle = .round
NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.20, alpha: 1).setStroke()
needle.stroke()

let hub = NSBezierPath(ovalIn: NSRect(x: 470, y: 470, width: 84, height: 84))
NSColor(calibratedRed: 0.15, green: 0.17, blue: 0.20, alpha: 1).setFill()
hub.fill()

let hubCenter = NSBezierPath(ovalIn: NSRect(x: 494, y: 494, width: 36, height: 36))
NSColor.white.setFill()
hubCenter.fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("无法编码 PNG 图标")
}
try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
