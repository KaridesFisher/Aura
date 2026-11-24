import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("Aura.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func icon(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let shape = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(red: 0.10, green: 0.18, blue: 0.19, alpha: 1), ending: NSColor(red: 0.035, green: 0.065, blue: 0.08, alpha: 1))!.draw(in: shape, angle: -75)
    NSColor(red: 0.67, green: 0.94, blue: 0.82, alpha: 1).setStroke()
    let a = NSBezierPath(); a.lineWidth = 34; a.lineCapStyle = .round; a.lineJoinStyle = .round
    a.move(to: NSPoint(x: 310, y: 340)); a.line(to: NSPoint(x: 470, y: 688)); a.curve(to: NSPoint(x: 553, y: 688), controlPoint1: NSPoint(x: 492, y: 735), controlPoint2: NSPoint(x: 531, y: 735)); a.line(to: NSPoint(x: 713, y: 340)); a.stroke()
    let wave = NSBezierPath(); wave.lineWidth = 29; wave.lineCapStyle = .round
    wave.move(to: NSPoint(x: 407, y: 426)); wave.curve(to: NSPoint(x: 616, y: 462), controlPoint1: NSPoint(x: 483, y: 387), controlPoint2: NSPoint(x: 530, y: 505)); wave.stroke()
    NSGraphicsContext.restoreGraphicsState(); return rep
}
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 2 ? "@2x" : ""
        let rep = icon(points * factor)
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try icon(1024).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("Aura.png"))
