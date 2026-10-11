import AppKit

// Draw from vector geometry at every resolution to keep small system icons crisp.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(size: Int, mac: Bool, to url: URL) throws {
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                       bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: (mac ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    cg.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    if mac {
        let shadow = NSShadow()
        shadow.shadowColor = color(0, 0.05, 0.04, 0.25)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: -9)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        color(0.04, 0.10, 0.09).setFill()
        NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832),
                     xRadius: 186, yRadius: 186).fill()
        NSGraphicsContext.restoreGraphicsState()
        cg.translateBy(x: 96, y: 96)
        cg.scaleBy(x: 832 / 1024, y: 832 / 1024)
    }

    let tile = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024),
                           xRadius: mac ? 228 : 0, yRadius: mac ? 228 : 0)
    NSGradient(starting: color(0.045, 0.12, 0.11), ending: color(0.12, 0.25, 0.22))!
        .draw(in: tile, angle: 65)
    if mac {
        color(0.70, 0.92, 0.79, 0.18).setStroke()
        tile.lineWidth = 3
        tile.stroke()
    }

    let trackpad = NSBezierPath(roundedRect: NSRect(x: 185, y: 316, width: 624, height: 450),
                               xRadius: 76, yRadius: 76)
    NSGraphicsContext.saveGraphicsState()
    let padShadow = NSShadow()
    padShadow.shadowColor = color(0, 0.025, 0.02, 0.4)
    padShadow.shadowBlurRadius = 28
    padShadow.shadowOffset = NSSize(width: 0, height: -18)
    padShadow.set()
    color(0.65, 0.88, 0.65).setFill()
    trackpad.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.47, 0.75, 0.54), ending: color(0.80, 0.96, 0.74))!
        .draw(in: trackpad, angle: 90)
    color(0.87, 1, 0.84, 0.75).setStroke()
    trackpad.lineWidth = 5
    trackpad.stroke()

    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 224, y: 405))
    divider.line(to: NSPoint(x: 770, y: 405))
    divider.lineWidth = 6
    divider.lineCapStyle = .round
    color(0.15, 0.38, 0.25, 0.25).setStroke()
    divider.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 511, y: 625))
    cursor.line(to: NSPoint(x: 546, y: 282))
    cursor.line(to: NSPoint(x: 627, y: 365))
    cursor.line(to: NSPoint(x: 698, y: 224))
    cursor.line(to: NSPoint(x: 776, y: 263))
    cursor.line(to: NSPoint(x: 705, y: 404))
    cursor.line(to: NSPoint(x: 823, y: 418))
    cursor.close()
    cursor.lineJoinStyle = .round
    cursor.lineWidth = 26
    color(0.055, 0.15, 0.12).setStroke()
    cursor.stroke()
    NSGradient(starting: color(0.87, 0.94, 0.89), ending: .white)!
        .draw(in: cursor, angle: 90)

    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

func writeCatalog(_ path: String, mac: Bool) throws {
    let catalog = root.appendingPathComponent(path)
    let set = catalog.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    if mac {
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let filename = "icon_\(points)x\(points)@\(scale)x.png"
                try drawIcon(size: points * scale, mac: true, to: set.appendingPathComponent(filename))
                images.append(["filename": filename, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x"])
            }
        }
    } else {
        try drawIcon(size: 1024, mac: false, to: set.appendingPathComponent("icon-1024.png"))
        images.append(["filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])
    }
    let info: [String: Any] = ["author": "xcode", "version": 1]
    try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
        .write(to: set.appendingPathComponent("Contents.json"))
    try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
        .write(to: catalog.appendingPathComponent("Contents.json"))
}

try writeCatalog("MacRemote/Assets.xcassets", mac: true)
try writeCatalog("PhoneRemote/Assets.xcassets", mac: false)
print("Generated Mac and iPhone app icons.")
