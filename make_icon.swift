import AppKit
import Foundation
import ImageIO

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let sourceURL = root.appendingPathComponent("Assets/icon-source.jpg")
let pngURL = root.appendingPathComponent("Assets/AppIcon-1024.png")
let iconset = root.appendingPathComponent("Assets/AppIcon.iconset")
let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let cgSource = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("无法读取图标源文件\n", stderr)
    exit(1)
}

let width = cgSource.width
let height = cgSource.height
let srcRep = NSBitmapImageRep(cgImage: cgSource)

func isWhite(_ x: Int, _ y: Int) -> Bool {
    guard let c = srcRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return true }
    return c.redComponent > 0.93 && c.greenComponent > 0.93 && c.blueComponent > 0.93
}

var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        if !isWhite(x, y) {
            if x < minX { minX = x }
            if y < minY { minY = y }
            if x > maxX { maxX = x }
            if y > maxY { maxY = y }
        }
    }
}

if maxX <= minX || maxY <= minY {
    minX = 0; minY = 0; maxX = width - 1; maxY = height - 1
}

print("content box (\(minX),\(minY))–(\(maxX),\(maxY))")

// 原图是带白边的圆角方标。内缩裁掉圆角，铺满 1024 画布，避免 Dock 里出现白角。
let boxW = maxX - minX + 1
let boxH = maxY - minY + 1
let inset = max(8, Int(Double(min(boxW, boxH)) * 0.10))
minX = min(minX + inset, maxX - 8)
minY = min(minY + inset, maxY - 8)
maxX = max(maxX - inset, minX + 8)
maxY = max(maxY - inset, minY + 8)
print("crop box (\(minX),\(minY))–(\(maxX),\(maxY)) inset=\(inset)")

let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = cgSource.cropping(to: cropRect) else {
    fputs("裁切失败\n", stderr)
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()

func renderPNG(_ image: CGImage, pixelSize: Int, to url: URL) throws {
    guard let out = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "icon", code: 1)
    }
    out.interpolationQuality = .high
    out.setFillColor(gray: 0, alpha: 0)
    out.fill(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    out.draw(image, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    guard let result = out.makeImage() else { throw NSError(domain: "icon", code: 2) }
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, result, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "icon", code: 3)
    }
}

try renderPNG(cropped, pixelSize: 1024, to: pngURL)

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]
for (name, px) in sizes {
    try renderPNG(cropped, pixelSize: px, to: iconset.appendingPathComponent("\(name).png"))
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", "-o", icnsURL.path, iconset.path]
try proc.run()
proc.waitUntilExit()
if proc.terminationStatus != 0 {
    fputs("iconutil 失败\n", stderr)
    exit(1)
}
print("已生成 \(icnsURL.path)")
