import AppKit

let output = CommandLine.arguments[1]
guard let artwork = NSImage(contentsOfFile: "Resources/AppIcon.png") else {
    fatalError("Missing Resources/AppIcon.png")
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("arcbox-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: temporary.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        if pixels == 1024, CommandLine.arguments.count > 2 {
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", temporary.path, "-o", output]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(1) }
