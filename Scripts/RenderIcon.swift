import AppKit

// Deliberately simple, reproducible raster artwork. No generated image dependency.
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
let outline = NSBezierPath(roundedRect: NSRect(x: 326, y: 220, width: 372, height: 584), xRadius: 186, yRadius: 186)
outline.lineWidth = 40
outline.stroke()
let wheel = NSBezierPath()
wheel.move(to: NSPoint(x: 512, y: 666))
wheel.line(to: NSPoint(x: 512, y: 590))
wheel.lineWidth = 40
wheel.lineCapStyle = .round
wheel.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
