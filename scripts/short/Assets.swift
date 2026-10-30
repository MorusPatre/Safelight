import AppKit

// Writes the pictures scripts/short/render.py makes the short from, besides the README's screenshots,
// into the folder given: Sonoma's Light and Dark wallpaper (wallpaper-light.png, wallpaper-dark.png),
// the one the screenshots' Wallpaper picker shows, and Safelight's icon (icon.png). All in sRGB, which
// the video is made in. scripts/make-short.sh builds it into an app with Safelight's icon, so the icon
// can be drawn the way macOS draws an app's, at 1024 pixels: the .icns only goes up to 256.

setlinebuf(stdout)

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func fail(_ message: String) -> Never {
    print("error: \(message)")
    exit(1)
}

/// A square picture `size` pixels across, drawn by `draw` in sRGB
func picture(size: Int, _ draw: (CGContext) -> Void) -> CGImage {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("Couldn't make a picture to draw in") }
    context.interpolationQuality = .high
    draw(context)
    guard let image = context.makeImage() else { fail("Couldn't draw a picture") }
    return image
}

func write(_ image: CGImage, as name: String) {
    let url = output.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fail("Couldn't write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Couldn't write \(url.path)") }
}

// Sonoma's pictures, Light first and Dark second, as high as the video
let sonoma = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Sonoma.heic")
guard let source = CGImageSourceCreateWithURL(sonoma as CFURL, nil), CGImageSourceGetCount(source) == 2 else {
    fail("Couldn't find a Light and a Dark picture in \(sonoma.path)")
}
for (index, name) in ["wallpaper-light.png", "wallpaper-dark.png"].enumerated() {
    guard let wallpaper = CGImageSourceCreateImageAtIndex(source, index, nil) else { fail("Couldn't read \(sonoma.path)") }
    write(picture(size: 1920) { $0.draw(wallpaper, in: CGRect(x: 0, y: 0, width: 1920, height: 1920)) }, as: name)
}

// The icon as macOS draws this app's, which is Safelight's. Only an app it can open gets its own icon:
// one it can't is drawn with a no-entry sign over it.
guard Bundle.main.bundlePath.hasSuffix(".app") else { fail("Run from the app scripts/make-short.sh builds, which has Safelight's icon") }
let icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
write(picture(size: 1024) { context in
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    icon.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
}, as: "icon.png")
