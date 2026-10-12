// Renders the 1024×1024 app icon: a window snapped to the left two-thirds of a grid.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Squircle-ish background with the standard macOS icon inset and a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(rounded(tile, 185))
ctx.setFillColor(color(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(rounded(tile, 185))
ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [color(0x7B5CFF), color(0x3C6DF0), color(0x19B5C8)] as CFArray,
                    locations: [0, 0.5, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 120, y: 924), end: CGPoint(x: 904, y: 100), options: [])
// Gentle top highlight.
let gloss = CGGradient(colorsSpace: cs, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
ctx.restoreGState()

// 3×2 grid; the window occupies the left two columns.
let grid = CGRect(x: 210, y: 268, width: 604, height: 488)
let gap: CGFloat = 26
let cellW = (grid.width - 2 * gap) / 3
let cellH = (grid.height - gap) / 2

ctx.setFillColor(color(0xFFFFFF, 0.26))
for row in 0..<2 {
    let cell = CGRect(x: grid.minX + 2 * (cellW + gap), y: grid.minY + CGFloat(row) * (cellH + gap),
                      width: cellW, height: cellH)
    ctx.addPath(rounded(cell, 34))
    ctx.fillPath()
}

let window = CGRect(x: grid.minX, y: grid.minY, width: 2 * cellW + gap, height: grid.height)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x0B1A4A, 0.45))
ctx.addPath(rounded(window, 40))
ctx.setFillColor(color(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

// Title bar separator and traffic lights.
ctx.setFillColor(color(0x3C6DF0, 0.12))
ctx.fill(CGRect(x: window.minX, y: window.maxY - 78, width: window.width, height: 3))
for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
    let c = CGPoint(x: window.minX + 46 + CGFloat(i) * 40, y: window.maxY - 39)
    ctx.setFillColor(color(UInt32(hex)))
    ctx.fillEllipse(in: CGRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26))
}

// Arrow hinting the window being moved into place.
let arrow = CGMutablePath()
let ax = window.midX, ay = window.midY - 40
arrow.move(to: CGPoint(x: ax + 70, y: ay))
arrow.addLine(to: CGPoint(x: ax - 60, y: ay))
arrow.move(to: CGPoint(x: ax - 10, y: ay + 52))
arrow.addLine(to: CGPoint(x: ax - 62, y: ay))
arrow.addLine(to: CGPoint(x: ax - 10, y: ay - 52))
ctx.addPath(arrow)
ctx.setStrokeColor(color(0x3C6DF0))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
