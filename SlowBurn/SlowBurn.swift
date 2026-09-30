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
            button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: SystemStrings.display)
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
        // Ensure software dimming is cleared when the app is force-quit
        GammaManager.shared.reset()
    }
}

// MARK: - 3. UI (Menu View)
struct MenuView: View {
    @ObservedObject var controller = ColorController.shared
    
    var body: some View {
        VStack(spacing: 20) {
            
            // --- AUTO TOGGLE ---
            HStack {
                Text(SystemStrings.schedule)
                    .fontWeight(.medium)
                Spacer()
                Toggle(SystemStrings.schedule, isOn: $controller.isAutoMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            
            Divider()

            // The slider labels share one column, as wide as the longest of them in the system language.
            Grid(alignment: .leading, verticalSpacing: 16) {
                // --- COLOR FILTER SECTION ---
                // These drive System Settings › Accessibility › Display › Color Filters (Color Tint).
                // 1. ON/OFF (the "Color filters" switch)
                GridRow {
                    HStack {
                        Text(SystemStrings.colorFilters)
                            .fontWeight(.medium)
                        Spacer()
                        Toggle(SystemStrings.colorFilters, isOn: $controller.isColorFilterOn)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(controller.isAutoMode)
                    }
                    .gridCellColumns(2)
                }

                // 2. INTENSITY
                GridRow(alignment: .top) {
                    Text(SystemStrings.intensity)
                        .fontWeight(.medium)
                        .frame(minWidth: 75, alignment: .leading)
                        .padding(.top, 4)

                    VStack(spacing: 2) {
                        Slider(value: $controller.intensity, in: ColorFilterManager.shared.intensityRange)
                            .tint(Color(hue: Double(controller.tint) / 360, saturation: 1.0, brightness: 1.0))
                            .disabled(controller.isAutoMode)

                        HStack {
                            Text(SystemStrings.low).font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text(SystemStrings.high).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }

                // 3. TINT
                GridRow {
                    Text(SystemStrings.tint)
                        .fontWeight(.medium)
                        .frame(minWidth: 75, alignment: .leading)

                    TintSlider(value: $controller.tint)
                        .disabled(controller.isAutoMode)
                        .opacity(controller.isAutoMode ? 0.6 : 1.0)
                }

                Divider()
                    .padding(.vertical, 4)

                // --- BRIGHTNESS SECTION ---
                GridRow(alignment: .top) {
                    Text(SystemStrings.brightness)
                        .fontWeight(.medium)
                        .frame(minWidth: 75, alignment: .leading)
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
                            Text(SystemStrings.low).font(.system(size: 10)).foregroundColor(.secondary)
                            Spacer()
                            Text(SystemStrings.high).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            // --- ACTION BUTTONS ---
            HStack {
                Button(SystemStrings.reset) {
                    controller.reset()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(SystemStrings.quit) {
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

// MARK: - Tint Slider (System Settings' Hue Slider)
/// The control System Settings › Accessibility › Display uses for Color Tint's Tint slider (its
/// `HueSliderRepresentable`), set up the same way: AppKit's `NSColorScaleSlider` (not in the public
/// headers) over 0–360° with its track drawn as a hue scale, and a single tick mark at 180° that the
/// slider snaps to on its own, like any NSSlider with tick marks.
struct TintSlider: NSViewRepresentable {
    @Binding var value: Float // degrees

    /// A plain slider stands in if AppKit ever stops shipping `NSColorScaleSlider`.
    private static let sliderClass = (NSClassFromString("NSColorScaleSlider") as? NSSlider.Type) ?? NSSlider.self
    /// `NSColorScaleSlider`'s scale type for a hue track.
    private static let hueScaleType = 7

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = Self.sliderClass.init(
            value: 360, minValue: 0, maxValue: 360,
            target: context.coordinator, action: #selector(Coordinator.valueDidChange(_:))
        )
        slider.controlSize = .small
        slider.numberOfTickMarks = 1
        slider.allowsTickMarkValuesOnly = false
        slider.tickMarkPosition = .above
        slider.isContinuous = true
        slider.altIncrementValue = 1
        if slider.responds(to: NSSelectorFromString("setDrawsTrackAsColorScaleType:")) {
            slider.setValue(NSColor.red, forKey: "color")
            slider.setValue(Self.hueScaleType, forKey: "drawsTrackAsColorScaleType")
        }
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.valueDidChangeHandler = { value = Float($0) }
        slider.doubleValue = Double(value)
        slider.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var valueDidChangeHandler: (Double) -> Void = { _ in }

        @objc func valueDidChange(_ sender: NSSlider) {
            valueDidChangeHandler(sender.doubleValue)
        }
    }
}

// MARK: - 4. Logic Controller
class ColorController: ObservableObject {
    static let shared = ColorController()
    
    // Mirror of the system Color Tint filter, kept the way System Settings keeps it: `intensity` is
    // the value the system stores, and `tint` is in degrees (0–360), stored as degrees / 360.
    @Published var isColorFilterOn: Bool = false { didSet { updateColorFilter() } }
    @Published var intensity: Float = 1.0 { didSet { colorSliderChanged() } }
    @Published var tint: Float = 0.0      { didSet { colorSliderChanged() } }
    @Published var brightness: Float = 1.0 { didSet { updateBrightness() } }
    
    @Published var isAutoMode: Bool = false {
        didSet { if isAutoMode { applyAutoSettings() } }
    }
    
    var isUserDraggingSlider: Bool = false
    private var isSyncingWithSystem: Bool = false
    private var isSyncingColorFilter: Bool = false
    
    private var targetSystemBrightness: Float? = nil
    private var lastSystemBrightness: Float = -1.0
    private var lastNativeUpdateTime: TimeInterval = 0
    
    private var timer: Timer?
    private var syncTimer: Timer?
    
    private let schedule: [ColorKeyframe] = [
        ColorKeyframe(hour: 0.0,  tint: 0.0,   intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 6.0,  tint: 0.0,   intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 7.0,  tint: 43.2,  intensity: 0.30, brightness: 0.85),
        ColorKeyframe(hour: 8.5,  tint: 180.0, intensity: 0.00, brightness: 1.00),
        ColorKeyframe(hour: 15.0, tint: 180.0, intensity: 0.00, brightness: 1.00),
        ColorKeyframe(hour: 17.5, tint: 43.2,  intensity: 0.20, brightness: 0.95),
        ColorKeyframe(hour: 19.5, tint: 28.8,  intensity: 0.60, brightness: 0.70),
        ColorKeyframe(hour: 20.5, tint: 18.0,  intensity: 0.85, brightness: 0.50),
        ColorKeyframe(hour: 21.5, tint: 0.0,   intensity: 1.00, brightness: 0.30),
        ColorKeyframe(hour: 24.0, tint: 0.0,   intensity: 1.00, brightness: 0.30)
    ]
    
    init() {
        if let nativeBrightness = GammaManager.shared.getNativeBrightness() {
            self.brightness = nativeBrightness
            self.lastSystemBrightness = nativeBrightness
        }
        
        // Follow changes made in System Settings (or anywhere else) to the color filter
        syncWithSystemColorFilter()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer = observer else { return }
                Unmanaged<ColorController>.fromOpaque(observer).takeUnretainedValue().syncWithSystemColorFilter()
            },
            ColorFilterManager.settingsChangedNotification as CFString,
            nil,
            .deliverImmediately
        )
        
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
        
        // The system filter bottoms out at its "Low" intensity, so below that the schedule switches it off
        let intensityRange = ColorFilterManager.shared.intensityRange
        self.tint = newTint
        self.intensity = min(max(newIntensity, intensityRange.lowerBound), intensityRange.upperBound)
        self.isColorFilterOn = newIntensity >= intensityRange.lowerBound
        self.brightness = newBrightness
    }
    
    /// Dragging Intensity or Tint turns the filter on, the way raising Intensity from zero used to.
    private func colorSliderChanged() {
        if !isColorFilterOn && !isAutoMode && !isSyncingColorFilter {
            isColorFilterOn = true // its didSet writes the new slider values as well
        } else {
            updateColorFilter()
        }
    }
    
    func updateColorFilter() {
        guard !isSyncingColorFilter else { return }
        ColorFilterManager.shared.write(ColorFilterManager.State(isOn: isColorFilterOn, hue: tint / 360, intensity: intensity))
    }

    func syncWithSystemColorFilter() {
        guard let state = ColorFilterManager.shared.read() else { return }

        isSyncingColorFilter = true
        if isColorFilterOn != state.isOn { isColorFilterOn = state.isOn }
        if abs(tint - state.hue * 360) > 0.0001 { tint = state.hue * 360 }
        if abs(intensity - state.intensity) > 0.0001 { intensity = state.intensity }
        isSyncingColorFilter = false
    }
    
    func updateBrightness() {
        GammaManager.shared.setGamma(brightness: brightness, skipHardwareUpdate: isSyncingWithSystem)
    }
    
    func reset() {
        isAutoMode = false
        targetSystemBrightness = nil
        isColorFilterOn = false
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
    
    func setGamma(brightness: Float, skipHardwareUpdate: Bool = false) {
        if abs(brightness - lastBrightness) < 0.001 {
            return
        }
        
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
            
            if softwareBrightness < 0.999 {
                needsGlobalRestore = false
                
                let table = calculateGammaTable(brightness: softwareBrightness)
                CGSetDisplayTransferByTable(displayID, UInt32(table.count), table, table, table)
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
    
    private func calculateGammaTable(brightness: Float) -> [CGGammaValue] {
        let tableSize = 256
        return (0..<tableSize).map { i in
            Float(i) / Float(tableSize - 1) * brightness
        }
    }
}

// MARK: - 6. Color Filter Manager (Accessibility Color Filters)
/// Reads and writes the Color Tint filter in System Settings › Accessibility › Display › Color Filters.
/// System Settings drives it through these MediaAccessibility functions (exported, but not in the
/// public headers), and the OS applies the filter itself, so it keeps working outside this app.
class ColorFilterManager {
    static let shared = ColorFilterManager()
    
    /// Darwin notification MediaAccessibility posts whenever any display filter setting changes.
    static let settingsChangedNotification = "com.apple.mediaaccessibility.displayFilterSettingsChanged"
    
    struct State {
        var isOn: Bool
        var hue: Float
        var intensity: Float
    }
    
    /// The range of System Settings' Intensity slider (`kMADisplayFilterPrefSingleColorIntensityMin`...`Max`).
    private(set) var intensityRange: ClosedRange<Float> = 0.25...1.0
    
    // The on/off switch and filter type are stored per category. Category 1 is "Color",
    // and type 16 within it is "Color Tint".
    private let colorCategory = 1
    private let colorTintType = 16
    
    private var getCategoryEnabledFunc: (@convention(c) (Int) -> Bool)?
    private var setCategoryEnabledFunc: (@convention(c) (Int, Bool) -> Void)?
    private var getTypeFunc: (@convention(c) (Int) -> Int)?
    private var setTypeFunc: (@convention(c) (Int, Int) -> Void)?
    private var getHueFunc: (@convention(c) () -> Double)?
    private var setHueFunc: (@convention(c) (Double) -> Void)?
    private var getIntensityFunc: (@convention(c) () -> Double)?
    private var setIntensityFunc: (@convention(c) (Double) -> Void)?
    
    init() {
        guard let handle = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_LAZY) else { return }
        
        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }
        
        getCategoryEnabledFunc = load("MADisplayFilterPrefGetCategoryEnabled", as: (@convention(c) (Int) -> Bool).self)
        setCategoryEnabledFunc = load("MADisplayFilterPrefSetCategoryEnabled", as: (@convention(c) (Int, Bool) -> Void).self)
        getTypeFunc = load("MADisplayFilterPrefGetType", as: (@convention(c) (Int) -> Int).self)
        setTypeFunc = load("MADisplayFilterPrefSetType", as: (@convention(c) (Int, Int) -> Void).self)
        getHueFunc = load("MADisplayFilterPrefGetSingleColorHue", as: (@convention(c) () -> Double).self)
        setHueFunc = load("MADisplayFilterPrefSetSingleColorHue", as: (@convention(c) (Double) -> Void).self)
        getIntensityFunc = load("MADisplayFilterPrefGetSingleColorIntensity", as: (@convention(c) () -> Double).self)
        setIntensityFunc = load("MADisplayFilterPrefSetSingleColorIntensity", as: (@convention(c) (Double) -> Void).self)
        
        if let minSym = dlsym(handle, "kMADisplayFilterPrefSingleColorIntensityMin"),
           let maxSym = dlsym(handle, "kMADisplayFilterPrefSingleColorIntensityMax") {
            intensityRange = Float(minSym.load(as: Double.self))...Float(maxSym.load(as: Double.self))
        }
    }
    
    /// `isOn` is only true when the Color Filters switch is on *and* the filter type is Color Tint.
    func read() -> State? {
        guard let getCategoryEnabled = getCategoryEnabledFunc, let getType = getTypeFunc,
              let getHue = getHueFunc, let getIntensity = getIntensityFunc else { return nil }
        
        let isOn = getCategoryEnabled(colorCategory) && getType(colorCategory) == colorTintType
        return State(isOn: isOn, hue: Float(getHue()), intensity: Float(getIntensity()))
    }
    
    /// Writes only what differs from the system, so slider drags don't re-post unchanged values.
    func write(_ state: State) {
        guard let current = read(),
              let setCategoryEnabled = setCategoryEnabledFunc, let setType = setTypeFunc,
              let setHue = setHueFunc, let setIntensity = setIntensityFunc else { return }
        
        if abs(state.hue - current.hue) > 0.0001 {
            setHue(Double(state.hue))
        }
        if abs(state.intensity - current.intensity) > 0.0001 {
            setIntensity(Double(state.intensity))
        }
        if state.isOn != current.isOn {
            if state.isOn {
                setType(colorCategory, colorTintType)
                setCategoryEnabled(colorCategory, true)
            } else {
                // Only reached when Color Tint is the active filter, so e.g. a Grayscale filter is left alone
                setCategoryEnabled(colorCategory, false)
            }
        }
    }
}

// MARK: - 7. System Strings (System Settings' Translations)
/// Every label in the app, read from the string tables System Settings (or Control Center, or
/// AppKit) loads the same label from, so it comes out in the system language, worded exactly as there.
/// Each keeps its English text as a fallback in case a table ever moves or drops the key.
enum SystemStrings {
    private static let accessibilitySettings = "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
    private static let displaysSettings = "/System/Library/ExtensionKit/Extensions/DisplaysExt.appex"
    private static let controlCenterSettings = "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex"
    private static let appKit = "/System/Library/Frameworks/AppKit.framework"
    private static let controlCenter = "/System/Library/CoreServices/ControlCenter.app"
    
    // System Settings › Accessibility › Display › Color Filters
    static let colorFilters = lookup("display.colorFilter.enable", in: accessibilitySettings, english: "Color filters")
    static let intensity = lookup("display.colorFilter.intensity", in: accessibilitySettings, english: "Intensity")
    static let low = lookup("display.colorFilter.intensity.low", in: accessibilitySettings, english: "Low")
    static let high = lookup("display.colorFilter.intensity.high", in: accessibilitySettings, english: "High")
    static let tint = lookup("display.colorFilter.tint", in: accessibilitySettings, english: "Tint")
    
    // System Settings › Displays (Schedule is Night Shift's)
    static let brightness = lookup("Brightness", in: displaysSettings, english: "Brightness")
    static let schedule = lookup("Schedule", in: displaysSettings, english: "Schedule")
    
    // The title of Control Center's Display module, which this popover stands in for
    static let display = lookup("Display", table: "Display", in: controlCenter, english: "Display")
    
    // System Settings › Control Center's Reset button, and AppKit's Quit button
    static let reset = lookup("Reset", in: controlCenterSettings, english: "Reset")
    static let quit = lookup("Quit", table: "Document", in: appKit, english: "Quit")
    
    /// The user's preferred languages. This app has no translations of its own, so a plain
    /// `localizedString` lookup would follow the app into English; asking with these picks each
    /// table's closest match the way System Settings does (e.g. French (Canada) before French).
    private static let languages = Locale.preferredLanguages.map(Locale.Language.init(identifier:))
    
    private static func lookup(_ key: String, table: String = "Localizable", in bundlePath: String, english: String) -> String {
        guard let bundle = Bundle(path: bundlePath) else { return english }
        return bundle.localizedString(forKey: key, value: english, table: table, localizations: languages)
    }
}
