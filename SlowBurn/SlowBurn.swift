import SwiftUI
import Cocoa
import ApplicationServices
import Foundation // Required for dynamic library loading

// MARK: - 1. App Entry Point
@main
struct SlowBurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - 2. App Delegate (Menu Bar Logic)
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Display Filters")
            button.action = #selector(togglePopover(_:))
        }
        
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView())
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure color filters are cleared when the app is force-quit
        GammaManager.shared.reset()
    }
}

// MARK: - 3. UI (Menu View)
struct MenuView: View {
    @ObservedObject var controller = ColorController.shared
    
    var body: some View {
        VStack(spacing: 20) {
            
            // --- HEADER & AUTO TOGGLE ---
            HStack {
                Text("Display Controls")
                    .font(.headline)
                Spacer()
                Toggle("Auto Schedule", isOn: $controller.isAutoMode)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            Divider()
            
            // --- COLOR FILTER SECTION ---
            VStack(spacing: 16) {
                // 1. INTENSITY
                HStack(alignment: .top) {
                    Text("Intensity")
                        .fontWeight(.medium)
                        .frame(width: 75, alignment: .leading)
                        .padding(.top, 4)
                    
                    VStack(spacing: 2) {
                        Slider(value: $controller.intensity, in: 0.0...1.0)
                            .tint(Color(hue: Double(controller.tint), saturation: 1.0, brightness: 1.0))
                            .disabled(controller.isAutoMode)
                        
                        HStack {
                            Text("Low").font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text("High").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                
                // 2. TINT
                HStack {
                    Text("Tint")
                        .fontWeight(.medium)
                        .frame(width: 75, alignment: .leading)
                    
                    TintSlider(value: $controller.tint)
                        .disabled(controller.isAutoMode)
                        .opacity(controller.isAutoMode ? 0.6 : 1.0)
                }
            }
            
            Divider()
            
            // --- BRIGHTNESS SECTION ---
            HStack(alignment: .top) {
                Text("Brightness")
                    .fontWeight(.medium)
                    .frame(width: 75, alignment: .leading)
                    .padding(.top, 4)
                
                VStack(spacing: 2) {
                    Slider(
                        value: $controller.brightness,
                        in: 0.0...1.0,
                        onEditingChanged: { isEditing in
                            controller.isUserDraggingSlider = isEditing
                        }
                    )
                    .tint(.white)
                    .disabled(controller.isAutoMode)
                    
                    HStack {
                        Text("Dim").font(.system(size: 10)).foregroundColor(.secondary)
                        Spacer()
                        Text("Max").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            // --- ACTION BUTTONS ---
            HStack {
                Button("Reset") {
                    controller.reset()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Quit") {
                    controller.reset()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 320)
        .animation(.easeInOut, value: controller.isAutoMode)
    }
}

// MARK: - Custom Tint Slider (Rainbow Track)
struct TintSlider: View {
    @Binding var value: Float
    
    var body: some View {
        GeometryReader { geometry in
            let thumbWidth: CGFloat = 8
            let thumbHeight: CGFloat = 20
            let trackHeight: CGFloat = 12
            let trackWidth = geometry.size.width - thumbWidth
            
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors:[
                        Color(hue: 0.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 1.0/6.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 2.0/6.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 3.0/6.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 4.0/6.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 5.0/6.0, saturation: 1.0, brightness: 1.0),
                        Color(hue: 1.0, saturation: 1.0, brightness: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: trackHeight)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(white: 0.3), lineWidth: 1))
                .overlay(
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 3)
                        .offset(y: -2.5),
                    alignment: .top
                )
                
                Capsule()
                    .fill(Color(white: 0.6))
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .frame(width: thumbWidth, height: thumbHeight)
                    .offset(x: CGFloat(value) * trackWidth)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let dragX = gesture.location.x - (thumbWidth / 2)
                        let rawValue = dragX / trackWidth
                        var newValue = min(max(rawValue, 0), 1)
                        
                        let centerValue: CGFloat = 0.5
                        let snapThreshold: CGFloat = 0.0225
                        
                        if abs(newValue - centerValue) < snapThreshold {
                            if value != Float(centerValue) {
                                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            }
                            newValue = centerValue
                        }
                        
                        value = Float(newValue)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - 4. Logic Controller
class ColorController: ObservableObject {
    static let shared = ColorController()
    
    @Published var intensity: Float = 0.0 { didSet { updateDisplay() } }
    @Published var tint: Float = 0.0      { didSet { updateDisplay() } }
    @Published var brightness: Float = 1.0 { didSet { updateDisplay() } }
    
    @Published var isAutoMode: Bool = false {
        didSet { if isAutoMode { applyAutoSettings() } }
    }
    
    var isUserDraggingSlider: Bool = false
    private var isSyncingWithSystem: Bool = false
    
    private var targetSystemBrightness: Float? = nil
    private var lastSystemBrightness: Float = -1.0
    private var lastNativeUpdateTime: TimeInterval = 0
    
    private var timer: Timer?
    private var syncTimer: Timer?
    
    private let schedule: [ColorKeyframe] = [
        ColorKeyframe(hour: 0.0,  tint: 0.00, intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 6.0,  tint: 0.00, intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 7.0,  tint: 0.12, intensity: 0.30, brightness: 0.85),
        ColorKeyframe(hour: 8.5,  tint: 0.50, intensity: 0.00, brightness: 1.00),
        ColorKeyframe(hour: 15.0, tint: 0.50, intensity: 0.00, brightness: 1.00),
        ColorKeyframe(hour: 17.5, tint: 0.12, intensity: 0.20, brightness: 0.95),
        ColorKeyframe(hour: 19.5, tint: 0.08, intensity: 0.60, brightness: 0.70),
        ColorKeyframe(hour: 20.5, tint: 0.05, intensity: 0.85, brightness: 0.50),
        ColorKeyframe(hour: 21.5, tint: 0.00, intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 24.0, tint: 0.00, intensity: 1.00, brightness: 0.30)
    ]
    
    init() {
        if let nativeBrightness = GammaManager.shared.getNativeBrightness() {
            self.brightness = nativeBrightness
            self.lastSystemBrightness = nativeBrightness
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.applyAutoSettings()
        }
        
        // 🚀 UPGRADE: 120 FPS polling (0.0083 seconds)
        let smoothSyncTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.syncWithSystemBrightness()
        }
        RunLoop.main.add(smoothSyncTimer, forMode: .common)
        self.syncTimer = smoothSyncTimer
    }
    
    func syncWithSystemBrightness() {
        guard !isAutoMode, !isUserDraggingSlider else { 
            targetSystemBrightness = nil
            return 
        }
        
        if let systemBrightness = GammaManager.shared.getNativeBrightness() {
            let stepChange = abs(systemBrightness - lastSystemBrightness)
            
            // 1. Did the native brightness just move?
            if stepChange > 0.001 {
                let now = Date().timeIntervalSinceReferenceDate
                let timeSinceLastUpdate = now - lastNativeUpdateTime
                
                lastNativeUpdateTime = now
                lastSystemBrightness = systemBrightness
                
                // If updates are firing rapidly (< 50ms apart), the user is continuously dragging.
                if timeSinceLastUpdate < 0.05 {
                    // Abort any ongoing animations and snap instantly to perfectly follow the drag!
                    self.targetSystemBrightness = nil
                    self.isSyncingWithSystem = true
                    self.brightness = systemBrightness
                    self.isSyncingWithSystem = false
                } else {
                    // The value changed after being idle. This is the first frame of a new interaction.
                    if stepChange > 0.04 {
                        // Large jump -> A Click or Keyboard Tap. Start the ease-out animation!
                        self.targetSystemBrightness = systemBrightness
                    } else {
                        // Small jump -> The very beginning of a slow drag. Snap instantly.
                        self.isSyncingWithSystem = true
                        self.brightness = systemBrightness
                        self.isSyncingWithSystem = false
                    }
                }
            } 
            
            // 2. Process the ease-out animation if we have a target
            if let target = targetSystemBrightness {
                let diff = target - self.brightness
                
                // Snap to the target once we are visually indistinguishable from it
                if abs(diff) < 0.002 {
                    self.isSyncingWithSystem = true
                    self.brightness = target
                    self.isSyncingWithSystem = false
                    self.targetSystemBrightness = nil
                } else {
                    self.isSyncingWithSystem = true
                    
                    var step = diff * 0.12
                    let minSpeed: Float = 0.002
                    
                    if abs(step) < minSpeed {
                        step = diff > 0 ? minSpeed : -minSpeed
                    }
                    
                    // CRITICAL FIX: Prevent Overshoot
                    // This stops the minSpeed from making the slider vibrate/jitter at the very end
                    if abs(step) > abs(diff) {
                        step = diff
                    }
                    
                    self.brightness += step
                    self.isSyncingWithSystem = false
                }
                
            } else if stepChange <= 0.001 {
                // 3. Not animating, and no native movement this frame.
                // Clean up any microscopic drift to ensure 100% sync.
                let delta = abs(self.brightness - systemBrightness)
                if delta > 0.002 {
                    self.isSyncingWithSystem = true
                    self.brightness = systemBrightness
                    self.isSyncingWithSystem = false
                }
            }
        }
    }
    
    func applyAutoSettings() {
        guard isAutoMode else { return }
        
        let now = Date()
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: now))
        let minute = Double(calendar.component(.minute, from: now))
        let timeInHours = hour + (minute / 60.0)
        
        var start = schedule.first!
        var end = schedule.last!
        
        for i in 0..<(schedule.count - 1) {
            if timeInHours >= schedule[i].hour && timeInHours <= schedule[i+1].hour {
                start = schedule[i]
                end = schedule[i+1]
                break
            }
        }
        
        let duration = end.hour - start.hour
        let progress = duration > 0 ? Float((timeInHours - start.hour) / duration) : 0
        
        let newTint = start.tint + (end.tint - start.tint) * progress
        let newIntensity = start.intensity + (end.intensity - start.intensity) * progress
        let newBrightness = start.brightness + (end.brightness - start.brightness) * progress
        
        self.tint = newTint
        self.intensity = newIntensity
        self.brightness = newBrightness
    }
    
    func updateDisplay() {
        GammaManager.shared.setGamma(tint: tint, intensity: intensity, brightness: brightness, skipHardwareUpdate: isSyncingWithSystem)
    }
    
    func reset() {
        isAutoMode = false
        targetSystemBrightness = nil
        intensity = 0.0
        brightness = 1.0
    }
}

struct ColorKeyframe {
    let hour: Double
    let tint: Float
    let intensity: Float
    let brightness: Float
}

// MARK: - 5. System Manager (Gamma & Hardware Brightness)
class GammaManager {
    static let shared = GammaManager()
    
    private var lastTint: Float = -1.0
    private var lastIntensity: Float = -1.0
    private var lastBrightness: Float = -1.0
    private var isGloballyRestored: Bool = false
    
    private var setBrightnessFunc: (@convention(c) (CGDirectDisplayID, Float) -> Int32)?
    private var getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var canChangeBrightnessFunc: (@convention(c) (CGDirectDisplayID) -> Bool)?
    
    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle = handle {
            if let sym = dlsym(handle, "DisplayServicesSetBrightness") {
                self.setBrightnessFunc = unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
            }
            if let sym = dlsym(handle, "DisplayServicesGetBrightness") {
                self.getBrightnessFunc = unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
            }
            if let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") {
                self.canChangeBrightnessFunc = unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
            }
        }
    }
    
    func getNativeBrightness() -> Float? {
        guard let getFunc = getBrightnessFunc else { return nil }
        var brightness: Float = 1.0
        let result = getFunc(CGMainDisplayID(), &brightness)
        return result == 0 ? brightness : nil
    }
    
    func setGamma(tint: Float, intensity: Float, brightness: Float, skipHardwareUpdate: Bool = false) {
        if abs(tint - lastTint) < 0.001 && abs(intensity - lastIntensity) < 0.001 && abs(brightness - lastBrightness) < 0.001 {
            return
        }
        
        lastTint = tint
        lastIntensity = intensity
        lastBrightness = brightness
        
        let displays = getAllDisplays()
        var needsGlobalRestore = true
        
        for displayID in displays {
            var hardwareBrightnessSucceeded = false
            let canChange = canChangeBrightnessFunc?(displayID) ?? false
            
            if canChange {
                if !skipHardwareUpdate {
                    if let setBrightnessFunc = setBrightnessFunc {
                        let result = setBrightnessFunc(displayID, brightness)
                        if result == 0 { hardwareBrightnessSucceeded = true }
                    }
                } else {
                    hardwareBrightnessSucceeded = true
                }
            }
            
            let softwareBrightness = hardwareBrightnessSucceeded ? 1.0 : max(brightness, 0.05)
            
            if intensity > 0.001 || softwareBrightness < 0.999 {
                needsGlobalRestore = false
                
                let (redTable, greenTable, blueTable) = calculateGammaTable(tint: tint, intensity: intensity, brightness: softwareBrightness)
                let tableSize = UInt32(redTable.count)
                
                CGSetDisplayTransferByTable(displayID, tableSize, redTable, greenTable, blueTable)
            }
        }
        
        if needsGlobalRestore {
            if !isGloballyRestored {
                CGDisplayRestoreColorSyncSettings()
                isGloballyRestored = true
            }
        } else {
            isGloballyRestored = false
        }
    }
    
    func reset() {
        CGDisplayRestoreColorSyncSettings()
        lastTint = -1.0
        lastIntensity = -1.0
        lastBrightness = -1.0
    }
    
    private func getAllDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        if result != .success { return [CGMainDisplayID()] }
        
        let allocated = Int(displayCount)
        let activeDisplays = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: allocated)
        result = CGGetActiveDisplayList(displayCount, activeDisplays, &displayCount)
        
        if result != .success {
            activeDisplays.deallocate()
            return[CGMainDisplayID()]
        }
        
        var displays: [CGDirectDisplayID] = []
        for i in 0..<Int(displayCount) {
            displays.append(activeDisplays[i])
        }
        
        activeDisplays.deallocate()
        return displays
    }
    
    private func calculateGammaTable(tint: Float, intensity: Float, brightness: Float) -> ([CGGammaValue],[CGGammaValue], [CGGammaValue]) {
        let nsColor = NSColor(calibratedHue: CGFloat(tint), saturation: 1.0, brightness: 1.0, alpha: 1.0)
        let tintR = Float(nsColor.redComponent)
        let tintG = Float(nsColor.greenComponent)
        let tintB = Float(nsColor.blueComponent)
        
        let multR = 1.0 - (intensity * (1.0 - tintR))
        let multG = 1.0 - (intensity * (1.0 - tintG))
        let multB = 1.0 - (intensity * (1.0 - tintB))
        
        let tableSize = 256
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)
        
        for i in 0..<tableSize {
            let baseIntensity = Float(i) / Float(tableSize - 1)
            let dimmedIntensity = baseIntensity * brightness
            
            redTable[i] = dimmedIntensity * multR
            greenTable[i] = dimmedIntensity * multG
            blueTable[i] = dimmedIntensity * multB
        }
        
        return (redTable, greenTable, blueTable)
    }
}
