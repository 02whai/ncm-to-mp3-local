import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for pointSize in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = pointSize * scale
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204).fill()
        NSColor(red: 0.75, green: 0.65, blue: 1, alpha: 1).setFill()
        for (index, barHeight) in [150, 270, 410, 550, 410, 270, 150].enumerated() {
            let height = CGFloat(barHeight)
            NSBezierPath(roundedRect: NSRect(x: CGFloat(218 + index * 86), y: (1024 - height) / 2, width: 58, height: height),
                         xRadius: 29, yRadius: 29).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(pointSize)x\(pointSize)\(scale == 2 ? "@2x" : "").png"
        try image.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
    }
}
