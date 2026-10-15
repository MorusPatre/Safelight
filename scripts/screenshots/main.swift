import Cocoa
import SwiftUI

// Draws the README's screenshots from Safelight's own views: the popover and the Schedule window, in
// the `-appearance` given (dark or light), each written to `-output` as a PNG. scripts/screenshots.sh
// builds this together with a copy of Safelight.swift, NoSystemChanges.swift and FixedTime.swift, and
// runs it once for each appearance: switched while it runs, the popover keeps parts of the one it had.
//
// Run with `-compare old.png new.png`, it says instead whether two screenshots look the same.

setlinebuf(stdout)

/// A picture drawn into a bitmap in Display P3, whose bytes can be read and changed
func bitmap(of image: CGImage) -> CGContext? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.displayP3),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context
}

/// Whether two PNGs are the same size with no pixel more than two levels apart: a window's glass picks
/// up a little of what's behind it, so a screenshot of the same thing can come out a level off here
/// and there.
func looksTheSame(_ path: String, _ otherPath: String) -> Bool {
    func pixels(_ path: String) -> CGContext? {
        CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            .flatMap(bitmap)
    }
    guard let one = pixels(path), let other = pixels(otherPath), one.width == other.width, one.height == other.height,
          let oneBytes = one.data?.assumingMemoryBound(to: UInt8.self),
          let otherBytes = other.data?.assumingMemoryBound(to: UInt8.self) else { return false }
    for row in 0..<one.height {
        for byte in 0..<one.width * 4 where abs(Int(oneBytes[row * one.bytesPerRow + byte]) - Int(otherBytes[row * other.bytesPerRow + byte])) > 2 {
            return false
        }
    }
    return true
}

final class Screenshots: NSObject, NSApplicationDelegate {
    private let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "output") ?? ".")
    private let appearance = UserDefaults.standard.string(forKey: "appearance") ?? "dark"
    private let appDelegate = AppDelegate()
    /// The Retina display the windows are put on, so they're drawn at twice their size
    private let screen = NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? NSScreen.screens[0]
    /// An invisible window under the middle of the menu bar for the popover to point at
    private var anchor: NSWindow!
    /// A window behind the popover, which is see-through, so it's over the appearance's window
    /// background colour rather than whatever is on screen there
    private var backdrop: NSWindow!
    private var activity: NSObjectProtocol?
    /// When the app last became active or stopped being active, by `systemUptime`
    private var lastActivationChange: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nothing would stop it changing the Mac if the stand-ins weren't the ones called
        guard ColorFilterManager.shared.read() == nil, AppearanceManager.shared.isDark() == nil,
              GammaManager.shared.getNativeBrightness(of: CGMainDisplayID()) == nil else {
            fail("Safelight's copy reaches the system's settings; NoSystemChanges.swift isn't standing in for them")
        }
        guard screen.backingScaleFactor >= 2 else { fail("There's no Retina display to draw the screenshots at twice their size on") }

        // Timers aren't put off while it runs in the background, and its settings start out as the defaults
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Drawing screenshots")
        removeSettings()
        after(60) { self.fail("Timed out") }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.lastActivationChange = ProcessInfo.processInfo.systemUptime
            }
        }

        // Set before any window is made, as the system's would be
        let isDark = appearance == "dark"
        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // The app's own popover; its menu bar icon is taken out again at once
        appDelegate.applicationDidFinishLaunching(notification)
        if let statusItem = appDelegate.statusItem { NSStatusBar.system.removeStatusItem(statusItem) }

        anchor = NSWindow(contentRect: NSRect(x: screen.frame.midX - 10, y: screen.visibleFrame.maxY - 1, width: 20, height: 1),
                          styleMask: .borderless, backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.ignoresMouseEvents = true
        anchor.orderFrontRegardless()

        backdrop = NSWindow(contentRect: NSRect(x: screen.frame.midX - 300, y: screen.visibleFrame.maxY - 700, width: 600, height: 700),
                            styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.backgroundColor = .windowBackgroundColor
        backdrop.ignoresMouseEvents = true
        backdrop.orderFrontRegardless()

        // The evening on the default schedule, with the Schedule off so every control is drawn at its brightest
        let controller = ColorController.shared
        controller.tint = 0
        controller.intensity = 0.78
        controller.isColorFilterOn = true
        controller.brightness = 0.68
        controller.chooseAppearance(isDark: isDark) // which only the Appearance picker shows
        draw()
    }

    private func draw() {
        let popover = appDelegate.popover
        capture("popover-\(appearance)", overBackdrop: true, show: {
            popover.show(relativeTo: self.anchor.contentView!.bounds, of: self.anchor.contentView!, preferredEdge: .minY)
            return popover.contentViewController?.view.window
        }, then: {
            popover.close()
            self.backdrop.orderOut(nil)
            self.capture("schedule-\(self.appearance)", show: {
                ScheduleWindow.shared.show()
                let window = NSApp.windows.first { $0.title == SystemStrings.schedule }
                if let window {
                    window.setFrameOrigin(NSPoint(x: self.screen.frame.midX - window.frame.width / 2,
                                                  y: self.screen.visibleFrame.midY - window.frame.height / 2))
                    window.makeFirstResponder(nil) // no time field focused
                }
                return window
            }, then: {
                self.finish()
            })
        })
    }

    /// Shows a window, and takes its picture once the app has been active for a moment, again if it
    /// stopped being active meanwhile. Only an active app's controls are drawn in the accent colour,
    /// and not straight away. macOS can take the activation back from an app that had nothing on screen
    /// as it opened, which closes the popover, and another app can take it, so it's shown again then.
    private func capture(_ name: String, overBackdrop: Bool = false, tries: Int = 10,
                         show: @escaping () -> NSWindow?, then next: @escaping () -> Void) {
        let window = show()
        NSApp.activate(ignoringOtherApps: true)
        after(1) {
            let lastChange = self.lastActivationChange
            if NSApp.isActive, ProcessInfo.processInfo.systemUptime - lastChange > 0.75, let window, window.isVisible {
                self.snapshot(window, as: name, overBackdrop: overBackdrop)
                if NSApp.isActive, self.lastActivationChange == lastChange { return next() }
            }
            guard tries > 1 else { self.fail("Safelight Screenshots couldn't stay the active app to draw \(name); run it again without clicking elsewhere") }
            self.capture(name, overBackdrop: overBackdrop, tries: tries - 1, show: show, then: next)
        }
    }

    /// Writes a window as it is on screen, with its shadow, in Display P3. A picture of a window by
    /// itself has its see-through parts over black, so with `overBackdrop` they're over the windows
    /// behind it (the backdrop) instead.
    private func snapshot(_ window: NSWindow, as name: String, overBackdrop: Bool) {
        // Taken with room for the shadow all round, and trimmed to it afterwards
        let margin: CGFloat = 100
        let frame = window.frame
        guard let image = Self.windowImage(window, in: frame.insetBy(dx: -margin, dy: -margin)),
              let pixels = bitmap(of: image), let bytes = pixels.data?.assumingMemoryBound(to: UInt8.self) else {
            fail("Couldn't take a picture of \(name)")
        }
        guard image.width == Int(frame.width + 2 * margin) * 2 else { fail("\(name) wasn't drawn at twice its size; is it on a Retina display?") }

        if overBackdrop {
            // The window's shape, in the colours it has over the backdrop
            guard let shape = Self.windowImage(window).flatMap(bitmap), let shapeBytes = shape.data?.assumingMemoryBound(to: UInt8.self),
                  let colors = Self.windowImage(window, in: frame, withWindowsBelow: true).flatMap(bitmap),
                  let colorBytes = colors.data?.assumingMemoryBound(to: UInt8.self),
                  shape.width == colors.width, shape.height == colors.height else { fail("Couldn't take a picture of \(name) over the backdrop") }
            let offset = Int(margin) * 2
            for row in 0..<shape.height {
                for column in 0..<shape.width {
                    let alpha = UInt32(shapeBytes[row * shape.bytesPerRow + column * 4 + 3])
                    let color = row * colors.bytesPerRow + column * 4
                    let pixel = (row + offset) * pixels.bytesPerRow + (column + offset) * 4
                    for channel in 0..<4 {
                        let over = channel == 3 ? 255 : UInt32(colorBytes[color + channel])
                        bytes[pixel + channel] = UInt8((over * alpha + UInt32(bytes[pixel + channel]) * (255 - alpha)) / 255)
                    }
                }
            }
        }

        // Down to the shadow's edges
        var (top, left, bottom, right) = (pixels.height, pixels.width, -1, -1)
        for row in 0..<pixels.height {
            for column in 0..<pixels.width where bytes[row * pixels.bytesPerRow + column * 4 + 3] > 0 {
                (top, left, bottom, right) = (min(top, row), min(left, column), max(bottom, row), max(right, column))
            }
        }
        let url = output.appendingPathComponent("\(name).png")
        guard bottom >= 0, let trimmed = pixels.makeImage()?.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { fail("Couldn't write \(name)") }
        CGImageDestinationAddImage(destination, trimmed, nil)
        guard CGImageDestinationFinalize(destination) else { fail("Couldn't write \(url.path)") }
        print("Wrote \(url.path)")
    }

    /// `CGWindowListCreateImage`, which the SDK no longer offers to Swift. Unlike ScreenCaptureKit, it
    /// needs no Screen Recording permission for the app's own windows. With no `rect`, it's the window
    /// alone, without its shadow; with one, it's that part of the screen with the window and its
    /// shadow, and with `withWindowsBelow`, with the windows behind it as well.
    private static func windowImage(_ window: NSWindow, in rect: CGRect? = nil, withWindowsBelow: Bool = false) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil } // RTLD_DEFAULT
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        let onScreenBelowWindow: UInt32 = 1 << 2, includingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        guard let rect else {
            return createImage(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFraming | bestResolution)?.takeRetainedValue()
        }
        // In the screen coordinates of Core Graphics, which go down from the top of the main display
        let bounds = CGRect(x: rect.minX, y: NSScreen.screens[0].frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let windows = withWindowsBelow ? onScreenBelowWindow | includingWindow : includingWindow
        return createImage(bounds, windows, UInt32(window.windowNumber), bestResolution)?.takeRetainedValue()
    }

    private func after(_ seconds: Double, _ body: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    private func removeSettings() {
        if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
    }

    private func finish() {
        removeSettings()
        exit(0)
    }

    private func fail(_ message: String) -> Never {
        print("error: \(message)")
        removeSettings()
        exit(1)
    }
}

let arguments = CommandLine.arguments
if let compare = arguments.firstIndex(of: "-compare"), arguments.count > compare + 2 {
    exit(looksTheSame(arguments[compare + 1], arguments[compare + 2]) ? 0 : 1)
}

let screenshots = Screenshots()
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.delegate = screenshots
NSApplication.shared.run()
