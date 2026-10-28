import AppKit

// Original vector artwork, rendered into the macOS app icon sizes.
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
        NSColor(srgbRed: 0.035, green: 0.05, blue: 0.035, alpha: 1).setFill(); background.fill()
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 512, y: 810))
        shield.curve(to: NSPoint(x: 756, y: 724), controlPoint1: NSPoint(x: 594, y: 775), controlPoint2: NSPoint(x: 674, y: 741))
        shield.line(to: NSPoint(x: 756, y: 502))
        shield.curve(to: NSPoint(x: 512, y: 216), controlPoint1: NSPoint(x: 754, y: 367), controlPoint2: NSPoint(x: 644, y: 263))
        shield.curve(to: NSPoint(x: 268, y: 502), controlPoint1: NSPoint(x: 380, y: 263), controlPoint2: NSPoint(x: 270, y: 367))
        shield.line(to: NSPoint(x: 268, y: 724))
        shield.curve(to: NSPoint(x: 512, y: 810), controlPoint1: NSPoint(x: 350, y: 741), controlPoint2: NSPoint(x: 430, y: 775))
        shield.close()
        NSColor(srgbRed: 0.09, green: 0.22, blue: 0.09, alpha: 1).setFill(); shield.fill()
        NSGraphicsContext.saveGraphicsState()
        shield.addClip()
        NSColor(srgbRed: 0.37, green: 0.91, blue: 0.28, alpha: 1).setFill()
        NSRect(x: 200, y: 180, width: 312, height: 670).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.55, green: 0.97, blue: 0.43, alpha: 1).setStroke()
        shield.lineWidth = 22; shield.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)@\(scale)x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("Contents.json"))
