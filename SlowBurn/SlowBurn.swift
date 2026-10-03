import SwiftUI
import Cocoa
import ApplicationServices
import Foundation // Required for dynamic library loading
import ServiceManagement

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
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(customizeSchedule: { [weak self] in
            self?.popover.performClose(nil)
            ScheduleWindow.shared.show()
        }))
    }
    
    /// A click opens the popover; a right-click or Control-click opens the menu instead.
    @objc func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }
    
    private func showMenu() {
        popover.performClose(nil)
        
        let menu = NSMenu()
        let openAtLogin = NSMenuItem(title: SystemStrings.openAtLogin, action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        openAtLogin.target = self
        // Read each time, as it can also be changed in System Settings › General › Login Items.
        openAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(openAtLogin)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: SystemStrings.quitApp, action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        
        // Attached only while it's open, so a plain click still reaches the popover.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("SlowBurn: couldn't change Open at Login: \(error)")
        }
        // The user turned it off in Login Items before; only they can allow it again there.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    
    @objc func quit(_ sender: Any?) {
        ColorController.shared.reset()
        NSApplication.shared.terminate(nil)
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
    let customizeSchedule: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            
            // --- AUTO TOGGLE ---
            HStack {
                Text(SystemStrings.schedule)
                    .fontWeight(.medium)
                Spacer()
                Button(action: customizeSchedule) {
                    Label(SystemStrings.customize, systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help(SystemStrings.customize)
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

                // --- APPEARANCE SECTION ---
                // This drives System Settings › Appearance (Light and Dark). The Schedule leaves it alone.
                GridRow(alignment: .top) {
                    Text(SystemStrings.appearance)
                        .fontWeight(.medium)
                        .frame(minWidth: 75, alignment: .leading)

                    AppearancePicker(isDark: Binding(
                        get: { controller.isDarkAppearance },
                        set: { controller.chooseAppearance(isDark: $0) }
                    ))
                    .disabled(controller.isChangingAppearance)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
/// `HueSliderRepresentable`), set up the same way: a `HueSlider` over 0–360° with its track drawn as
/// a hue scale, and a single tick mark at 180° that the slider snaps to on its own, like any NSSlider
/// with tick marks.
struct TintSlider: NSViewRepresentable {
    @Binding var value: Float // degrees
    /// Like `Slider`'s: called with true when the slider is pressed, and with false when it's let go.
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// `NSColorScaleSliderCell`'s scale type for a hue track.
    private static let hueScaleType = 7

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HueSlider {
        let slider = HueSlider(
            value: 360, minValue: 0, maxValue: 360,
            target: context.coordinator, action: #selector(Coordinator.valueDidChange(_:))
        )
        slider.controlSize = .small
        slider.numberOfTickMarks = 1
        slider.allowsTickMarkValuesOnly = false
        slider.tickMarkPosition = .above
        slider.isContinuous = true
        slider.altIncrementValue = 1
        if let cell = slider.cell, cell.responds(to: NSSelectorFromString("setDrawsTrackAsColorScaleType:")) {
            cell.setValue(NSColor.red, forKey: "color")
            cell.setValue(Self.hueScaleType, forKey: "drawsTrackAsColorScaleType")
        }
        return slider
    }

    func updateNSView(_ slider: HueSlider, context: Context) {
        context.coordinator.valueDidChangeHandler = { value = Float($0) }
        slider.onEditingChanged = onEditingChanged
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

/// AppKit's `NSColorScaleSlider` (not in the public headers), rebuilt from its parts so it can say when
/// it's pressed and let go: that class is an NSSlider whose cell, `NSColorScaleSliderCell`, draws the
/// track and takes the settings the slider passes on, with these alignment insets. A plain slider
/// stands in if AppKit ever stops shipping the cell.
final class HueSlider: NSSlider {
    private static let colorScaleCellClass = NSClassFromString("NSColorScaleSliderCell") as? NSSliderCell.Type

    var onEditingChanged: (Bool) -> Void = { _ in }

    override class var cellClass: AnyClass? {
        get { colorScaleCellClass ?? super.cellClass }
        set { super.cellClass = newValue }
    }

    override var alignmentRectInsets: NSEdgeInsets {
        Self.colorScaleCellClass == nil ? super.alignmentRectInsets : NSEdgeInsets(top: 1, left: 1, bottom: 4, right: 1)
    }

    override func mouseDown(with event: NSEvent) {
        onEditingChanged(true)
        super.mouseDown(with: event) // tracks the mouse until it's let go
        onEditingChanged(false)
    }
}

// MARK: - Appearance Picker (System Settings' Appearance Thumbnails)
/// The Light and Dark of the picker in System Settings › Appearance (its `AppearanceThemePicker`, which
/// comes with Auto and can't be had without it), rebuilt from its parts: System Settings' thumbnails,
/// each over its shadow, with the highlight in it drawn in the accent colour, a ring in that colour around
/// the one that's chosen, and its name underneath. Disabled, it dims the way that picker does while the
/// appearance is changing.
struct AppearancePicker: View {
    @Binding var isDark: Bool

    private static let artwork = Bundle(path: SystemStrings.appearanceSettings)
    private static let thumbnailSize = CGSize(width: 67, height: 44)

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            option(SystemStrings.light, thumbnail: "AppearanceLight", isDark: false)
            option(SystemStrings.dark, thumbnail: "AppearanceDark", isDark: true)
        }
    }

    private func option(_ name: String, thumbnail: String, isDark: Bool) -> some View {
        let isSelected = self.isDark == isDark
        return Button {
            self.isDark = isDark
        } label: {
            VStack(spacing: 1) {
                Group {
                    if let artwork = Self.artwork, artwork.image(forResource: thumbnail) != nil {
                        // Loaded by name: with `Image(nsImage:)` the picker's dimming takes 0.3 s longer to be over
                        ZStack {
                            Image(thumbnail, bundle: artwork)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            Image("selectionColor_mask", bundle: artwork)
                                .renderingMode(.template)
                                .foregroundStyle(Color.accentColor)
                        }
                    } else {
                        // A plain window colour stands in if System Settings ever stops shipping the thumbnails
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(white: isDark ? 0.15 : 0.95))
                            .strokeBorder(.separator)
                    }
                }
                .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                .padding(3.5)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                // Around a thumbnail with no ring, and behind either of them when the picker is dimmed
                .shadow(color: .black.opacity(0.33), radius: isSelected ? 0 : 2)

                Text(name)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Schedule Window
/// The window the gear button next to the Schedule switch opens.
final class ScheduleWindow: NSObject, NSWindowDelegate {
    static let shared = ScheduleWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            // The window can't be resized: it takes the editor's size, and follows it as rows come and go
            let hostingController = NSHostingController(rootView: ScheduleEditor())
            hostingController.sizingOptions = [.minSize, .maxSize]
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask.remove(.resizable)
            window.title = SystemStrings.schedule
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(hostingController.sizeThatFits(in: window.contentMaxSize)) // so it's centred at its size
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // The window grows downwards as rows are added, so one near the bottom of the screen moves up to stay on it
    func windowDidResize(_ notification: Notification) {
        guard let window, let visibleFrame = window.screen?.visibleFrame, window.frame.minY < visibleFrame.minY else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: visibleFrame.minY))
    }

    // Undo and Redo (⌘Z and ⇧⌘Z) in the window take back and put back changes to the schedule
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        ColorController.shared.scheduleUndoManager
    }

    func windowDidResignKey(_ notification: Notification) {
        ColorController.shared.endScheduleEdit()
    }
}

/// The Schedule's keyframes, a row each, under a preview of the day they make.
struct ScheduleEditor: View {
    @ObservedObject var controller = ColorController.shared

    var body: some View {
        Form {
            Section {
                ScheduleDayView(schedule: controller.schedule)
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text(SystemStrings.time)
                        Text(SystemStrings.colorFilters)
                        Text(SystemStrings.intensity)
                        Text(SystemStrings.tint)
                        Text(SystemStrings.brightness)
                    }
                    .foregroundStyle(.secondary)

                    ForEach($controller.schedule) { $keyframe in
                        Divider()

                        GridRow {
                            DatePicker(SystemStrings.time, selection: time(of: keyframe.id), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.stepperField)
                                .environment(\.timeZone, Self.utc)

                            Toggle(SystemStrings.colorFilters, isOn: $keyframe.isColorFilterOn)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)

                            // Holding any of the sliders shows its keyframe on screen until it's let go
                            Slider(value: $keyframe.intensity, in: ColorFilterManager.shared.intensityRange) {
                                Text(SystemStrings.intensity)
                            } onEditingChanged: { isEditing in
                                controller.preview(isEditing ? keyframe.id : nil)
                            }
                            .labelsHidden()
                            .tint(Color(hue: Double(keyframe.tint) / 360, saturation: 1.0, brightness: 1.0))
                            .disabled(!keyframe.isColorFilterOn)
                            .frame(minWidth: 90)

                            TintSlider(value: $keyframe.tint) { isEditing in
                                controller.preview(isEditing ? keyframe.id : nil)
                            }
                            .disabled(!keyframe.isColorFilterOn)
                            .opacity(keyframe.isColorFilterOn ? 1.0 : 0.6)
                            .frame(minWidth: 90)

                            Slider(value: $keyframe.brightness, in: 0.0...1.0) {
                                Text(SystemStrings.brightness)
                            } onEditingChanged: { isEditing in
                                controller.preview(isEditing ? keyframe.id : nil)
                            }
                            .labelsHidden()
                            .tint(.white)
                            .frame(minWidth: 90)

                            Button {
                                controller.deleteKeyframe(keyframe.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(SystemStrings.delete)
                            .accessibilityLabel(SystemStrings.delete)
                            .disabled(controller.schedule.count == 1)
                        }
                    }
                }
            } footer: {
                HStack {
                    Button(SystemStrings.restoreDefaults) {
                        controller.restoreDefaultSchedule()
                    }

                    // The Edit menu's Undo and Redo. Whatever changes which of them there is to do
                    // changes the schedule as well, and that redraws them. Their symbols are set as
                    // text, which makes the buttons as tall as the ones either side.
                    Button {
                        controller.scheduleUndoManager.undo()
                    } label: {
                        Text(Image(systemName: "arrow.uturn.backward"))
                    }
                    .help(SystemStrings.undo)
                    .accessibilityLabel(SystemStrings.undo)
                    .disabled(!controller.scheduleUndoManager.canUndo)

                    Button {
                        controller.scheduleUndoManager.redo()
                    } label: {
                        Text(Image(systemName: "arrow.uturn.forward"))
                    }
                    .help(SystemStrings.redo)
                    .accessibilityLabel(SystemStrings.redo)
                    .disabled(!controller.scheduleUndoManager.canRedo)

                    Spacer()
                    Button(SystemStrings.add) {
                        controller.addKeyframe()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 760)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    // As tall as its rows, until the window fills the height of the screen, and then they scroll
    private var maxHeight: CGFloat {
        guard let screen = NSScreen.main else { return .infinity }
        return NSWindow.contentRect(forFrameRect: screen.visibleFrame, styleMask: [.titled, .closable, .miniaturizable]).height
    }

    // Times of day are edited as times on the first day of 2001 in UTC, which has no daylight saving
    // changes to skip or repeat a time, so every time reads back as it was set.
    private static let utc = TimeZone(identifier: "UTC")!

    // Setting a time slides its row to its new place, so the keyframe is found by its ID, not by the
    // place it had when the row was drawn.
    private func time(of id: ColorKeyframe.ID) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: Double(controller.schedule.first { $0.id == id }?.minute ?? 0) * 60) },
            set: { date in
                withAnimation {
                    controller.setMinute((Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down)) % 1440 + 1440) % 1440, ofKeyframe: id)
                }
            }
        )
    }
}

/// The day the Schedule makes, from midnight to midnight: a strip of roughly how white looks on screen
/// through it, a line at the current time, and a dot under each keyframe.
struct ScheduleDayView: View {
    let schedule: [ColorKeyframe]

    private let stripHeight: CGFloat = 36

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            Canvas { context, size in
                let outline = Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: stripHeight), cornerRadius: 6)
                func x(ofMinute minute: Double) -> CGFloat { size.width * minute / 1440 }

                context.drawLayer { strip in
                    strip.clip(to: outline)
                    for x in 0..<Int(size.width.rounded(.up)) {
                        guard let settings = ColorKeyframe.settings(in: schedule, at: Double(x) / size.width * 1440) else { continue }
                        strip.fill(Path(CGRect(x: CGFloat(x), y: 0, width: 1, height: stripHeight)), with: .color(settings.previewColor))
                    }

                    let now = Calendar.current.dateComponents([.hour, .minute], from: timeline.date)
                    let nowX = x(ofMinute: Double(now.hour! * 60 + now.minute!))
                    strip.fill(Path(CGRect(x: nowX - 1, y: 0, width: 2, height: stripHeight)), with: .color(.accentColor))
                }
                context.stroke(outline, with: .style(.separator))

                for keyframe in schedule {
                    let dot = CGRect(x: x(ofMinute: Double(keyframe.minute)) - 2.5, y: stripHeight + 4, width: 5, height: 5)
                    context.fill(Path(ellipseIn: dot), with: .style(.secondary))
                }

                // Midnight, 6, noon, 6 and midnight, the ends kept inside the strip
                for hour in stride(from: 0, through: 24, by: 6) {
                    let date = Calendar.current.date(bySettingHour: hour % 24, minute: 0, second: 0, of: timeline.date) ?? timeline.date
                    let label = Text(date.formatted(.dateTime.hour())).font(.system(size: 10)).foregroundColor(.secondary)
                    let anchor: UnitPoint = hour == 0 ? .topLeading : hour == 24 ? .topTrailing : .top
                    context.draw(label, at: CGPoint(x: x(ofMinute: Double(hour * 60)), y: stripHeight + 13), anchor: anchor)
                }
            }
        }
        .frame(height: stripHeight + 27)
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

    // Mirror of the system appearance: Dark or Light, whether it was chosen or Auto switched to it.
    @Published private(set) var isDarkAppearance: Bool = false
    /// True from when an appearance is chosen here until the screen has changed over to it.
    @Published private(set) var isChangingAppearance: Bool = false
    
    @Published var isAutoMode: Bool = false {
        didSet { if isAutoMode { applyAutoSettings() } }
    }
    
    var isUserDraggingSlider: Bool = false
    /// The keyframe on screen while one of its sliders in the Schedule window is held down. Meanwhile
    /// the settings above aren't written to the system or read back from it, so they're what comes back.
    private var previewedKeyframeID: ColorKeyframe.ID?
    private var isSyncingWithSystem: Bool = false
    private var isSyncingColorFilter: Bool = false
    
    private var targetSystemBrightness: Float? = nil
    private var lastSystemBrightness: Float = -1.0
    private var lastNativeUpdateTime: TimeInterval = 0
    
    private var timer: Timer?
    private var syncTimer: Timer?

    /// The Schedule's keyframes in time order, saved as they're edited. A keyframe whose time changes
    /// moves to its new place at once, and its row in the Schedule window with it.
    @Published var schedule: [ColorKeyframe] = ColorController.loadSchedule() {
        didSet {
            let sorted = schedule.sorted { $0.minute < $1.minute }
            if sorted != schedule { schedule = sorted }
            registerUndo(toSchedule: oldValue)
            if let data = try? JSONEncoder().encode(schedule) {
                UserDefaults.standard.set(data, forKey: Self.scheduleDefaultsKey)
            }
            applyAutoSettings()
            showPreview()
        }
    }

    private static let scheduleDefaultsKey = "schedule"

    /// Takes back and puts back changes to the schedule, for Undo and Redo in the Schedule window.
    let scheduleUndoManager = UndoManager()

    /// Changes that are undone in one go: the ones made while a slider is held, and the ones made to
    /// one keyframe's time straight after each other.
    private enum ScheduleEdit: Equatable {
        case slider
        case time(ColorKeyframe.ID)
    }
    private var timeEdit: ScheduleEdit?
    /// The edit the last change to the schedule was part of, which the next change may carry on.
    private var lastScheduleEdit: ScheduleEdit?

    private static func loadSchedule() -> [ColorKeyframe] {
        guard let data = UserDefaults.standard.data(forKey: scheduleDefaultsKey),
              let schedule = try? JSONDecoder().decode([ColorKeyframe].self, from: data),
              !schedule.isEmpty else { return ColorKeyframe.defaultSchedule }
        return schedule.sorted { $0.minute < $1.minute }
    }

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

        // And the same for the appearance, which Auto changes at sunrise and sunset too
        syncWithSystemAppearance()
        DistributedNotificationCenter.default().addObserver(
            forName: AppearanceManager.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.syncWithSystemAppearance()
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
        guard !isAutoMode, !isUserDraggingSlider, previewedKeyframeID == nil else {
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
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        guard let settings = ColorKeyframe.settings(in: schedule, at: Double(hour * 60 + minute)) else { return }

        self.tint = settings.tint
        self.intensity = settings.filterIntensity
        self.isColorFilterOn = settings.isColorFilterOn
        self.brightness = settings.brightness
    }

    /// Adds a keyframe at the next free half hour, set to what the schedule already has there.
    func addKeyframe() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nextHalfHour = ((now.hour! * 60 + now.minute!) / 30 + 1) * 30
        let taken = Set(schedule.map(\.minute))
        let minute = (0..<48).lazy.map { (nextHalfHour + $0 * 30) % 1440 }.first { !taken.contains($0) } ?? nextHalfHour % 1440

        let settings = ColorKeyframe.settings(in: schedule, at: Double(minute))
            ?? ColorKeyframe.Settings(intensity: isColorFilterOn ? intensity : 0, tint: tint, brightness: brightness)
        schedule.append(ColorKeyframe(
            minute: minute,
            isColorFilterOn: settings.isColorFilterOn,
            intensity: settings.filterIntensity,
            tint: settings.tint,
            brightness: settings.brightness
        ))
    }

    /// The schedule always keeps at least one keyframe.
    func deleteKeyframe(_ id: ColorKeyframe.ID) {
        guard schedule.count > 1 else { return }
        schedule.removeAll { $0.id == id }
    }

    func restoreDefaultSchedule() {
        schedule = ColorKeyframe.defaultSchedule
    }

    /// Sets a keyframe's time. Setting the same keyframe's time again straight after is undone with it.
    func setMinute(_ minute: Int, ofKeyframe id: ColorKeyframe.ID) {
        guard let index = schedule.firstIndex(where: { $0.id == id }) else { return }
        timeEdit = .time(id)
        schedule[index].minute = minute
        timeEdit = nil
    }

    /// Registers the way back from a change to the schedule, unless it carries on the edit the last
    /// change was part of. Undoing puts `previous` back, which registers the way forward for Redo.
    private func registerUndo(toSchedule previous: [ColorKeyframe]) {
        // Putting the keyframes in time order sets the schedule a second time, which isn't a change of its own
        guard schedule != previous.sorted(by: { $0.minute < $1.minute }) else { return }
        let edit = previewedKeyframeID == nil ? timeEdit : .slider
        defer { lastScheduleEdit = edit }
        if let edit, edit == lastScheduleEdit { return }

        scheduleUndoManager.registerUndo(withTarget: self) { controller in
            // Rows that stay slide to the places their times put them back in, as they do when a time is set
            let keepsRows = Set(previous.map(\.id)) == Set(controller.schedule.map(\.id))
            withAnimation(keepsRows ? .default : nil) { controller.schedule = previous }
        }
    }

    /// Makes the next change to the schedule one to undo by itself, whatever the last one was.
    func endScheduleEdit() {
        lastScheduleEdit = nil
    }

    /// Shows the keyframe with this ID on screen, following its edits, until this is called with nil,
    /// which puts back the settings that were there before (or the Schedule's for now, if it's on).
    func preview(_ id: ColorKeyframe.ID?) {
        endScheduleEdit() // each hold of a slider is undone by itself
        previewedKeyframeID = id
        if id == nil {
            updateColorFilter()
            updateBrightness()
        } else {
            showPreview()
        }
    }

    private func showPreview() {
        guard let keyframe = schedule.first(where: { $0.id == previewedKeyframeID }) else { return }
        ColorFilterManager.shared.write(ColorFilterManager.State(isOn: keyframe.isColorFilterOn, hue: keyframe.tint / 360, intensity: keyframe.intensity))
        GammaManager.shared.setGamma(brightness: keyframe.brightness)
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
        guard !isSyncingColorFilter, previewedKeyframeID == nil else { return }
        ColorFilterManager.shared.write(ColorFilterManager.State(isOn: isColorFilterOn, hue: tint / 360, intensity: intensity))
    }

    func syncWithSystemColorFilter() {
        guard previewedKeyframeID == nil, let state = ColorFilterManager.shared.read() else { return }

        isSyncingColorFilter = true
        if isColorFilterOn != state.isOn { isColorFilterOn = state.isOn }
        if abs(tint - state.hue * 360) > 0.0001 { tint = state.hue * 360 }
        if abs(intensity - state.intensity) > 0.0001 { intensity = state.intensity }
        isSyncingColorFilter = false
    }
    
    func updateBrightness() {
        guard previewedKeyframeID == nil else { return }
        GammaManager.shared.setGamma(brightness: brightness, skipHardwareUpdate: isSyncingWithSystem)
    }

    /// Chooses Light or Dark in System Settings' order: the choice shows at once, the picker dims, and
    /// only when it has does the screen change over, after which the picker comes back. The screen
    /// fades from a picture of itself, so the choice has to be showing before that's taken, or it only
    /// appears as the fade ends. Choices made before the screen has changed over are ignored.
    func chooseAppearance(isDark: Bool) {
        guard !isChangingAppearance else { return }
        guard isDark != isDarkAppearance else {
            AppearanceManager.shared.setDark(isDark) // nothing to change over to, but this turns Auto off
            return
        }

        isDarkAppearance = isDark
        withAnimation(.default, completionCriteria: .logicallyComplete) {
            isChangingAppearance = true
        } completion: { [weak self] in
            AppearanceManager.shared.setDark(isDark) {
                self?.isChangingAppearance = false
                self?.syncWithSystemAppearance()
            }
        }
    }

    func syncWithSystemAppearance() {
        guard !isChangingAppearance, let isDark = AppearanceManager.shared.isDark() else { return }
        if isDarkAppearance != isDark { isDarkAppearance = isDark }
    }
    
    func reset() {
        isAutoMode = false
        targetSystemBrightness = nil
        isColorFilterOn = false
        brightness = 1.0
    }
}

/// A point on the Schedule: the settings it reaches `minute` minutes after midnight. In between, the
/// settings move steadily from one keyframe to the next, and from the last round midnight to the first.
struct ColorKeyframe: Identifiable, Codable, Equatable {
    var id = UUID()
    var minute: Int
    var isColorFilterOn: Bool
    var intensity: Float // kept while the filter is off, for when it's turned back on
    var tint: Float      // degrees
    var brightness: Float

    static let defaultSchedule: [ColorKeyframe] = [
        ColorKeyframe(minute: 5 * 60 + 45,  isColorFilterOn: true,  intensity: 0.35, tint: 0,   brightness: 0.82),
        ColorKeyframe(minute: 6 * 60,       isColorFilterOn: false, intensity: 0.25, tint: 180, brightness: 1.00),
        ColorKeyframe(minute: 18 * 60 + 45, isColorFilterOn: false, intensity: 0.25, tint: 180, brightness: 1.00),
        ColorKeyframe(minute: 19 * 60,      isColorFilterOn: true,  intensity: 0.46, tint: 0,   brightness: 0.92),
        ColorKeyframe(minute: 20 * 60 + 30, isColorFilterOn: true,  intensity: 0.78, tint: 0,   brightness: 0.68)
    ]

    struct Settings {
        /// 0 where the filter is off, so fading to or from an off keyframe passes the filter's lowest
        /// intensity part way, and that's where the filter switches.
        var intensity: Float
        var tint: Float
        var brightness: Float

        /// The system filter bottoms out at its "Low" intensity, so below that the schedule switches it off
        var isColorFilterOn: Bool { intensity >= ColorFilterManager.shared.intensityRange.lowerBound }
        var filterIntensity: Float {
            let intensityRange = ColorFilterManager.shared.intensityRange
            return min(max(intensity, intensityRange.lowerBound), intensityRange.upperBound)
        }

        /// Roughly how white looks on screen with these settings, for the Schedule window's preview.
        var previewColor: Color {
            Color(hue: Double(tint) / 360, saturation: isColorFilterOn ? Double(filterIntensity) : 0, brightness: Double(brightness))
        }
    }

    /// The settings `schedule` has reached `minute` minutes after midnight, or nil if it's empty.
    static func settings(in schedule: [ColorKeyframe], at minute: Double) -> Settings? {
        let keyframes = schedule.sorted { $0.minute < $1.minute }
        guard !keyframes.isEmpty else { return nil }

        // The keyframes either side of `minute`, either of which may be across midnight from it
        let startIndex = keyframes.lastIndex { Double($0.minute) <= minute }
        let start = keyframes[startIndex ?? keyframes.count - 1]
        let end = keyframes[((startIndex ?? -1) + 1) % keyframes.count]
        let startMinute = Double(start.minute) - (startIndex == nil ? 1440 : 0)
        var endMinute = Double(end.minute)
        if endMinute <= startMinute { endMinute += 1440 }
        let progress = Float((minute - startMinute) / (endMinute - startMinute))

        // An off keyframe's tint doesn't show, so fading to or from one holds the other one's tint,
        // and the tint takes the short way round the hue circle, so red to pink doesn't pass through green
        let startTint = start.isColorFilterOn || !end.isColorFilterOn ? start.tint : end.tint
        let endTint = end.isColorFilterOn || !start.isColorFilterOn ? end.tint : start.tint
        var tintChange = (endTint - startTint).truncatingRemainder(dividingBy: 360)
        if tintChange > 180 { tintChange -= 360 } else if tintChange < -180 { tintChange += 360 }
        var tint = (startTint + tintChange * progress).truncatingRemainder(dividingBy: 360)
        if tint < 0 { tint += 360 }

        let startIntensity = start.isColorFilterOn ? start.intensity : 0
        let endIntensity = end.isColorFilterOn ? end.intensity : 0
        return Settings(
            intensity: startIntensity + (endIntensity - startIntensity) * progress,
            tint: tint,
            brightness: start.brightness + (end.brightness - start.brightness) * progress
        )
    }
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

// MARK: - 7. Appearance Manager (Light & Dark Appearance)
/// Reads and sets the appearance in System Settings › Appearance. System Settings sets it through these
/// SkyLight functions (exported, but not in the public headers), and has AppKit fade the whole screen
/// from the old appearance to the new one.
class AppearanceManager {
    static let shared = AppearanceManager()

    /// Distributed notification the system posts whenever the appearance changes.
    static let changedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")

    // `SLSAppearanceTheme`'s two values
    private let lightTheme: Int32 = 0
    private let darkTheme: Int32 = 1

    private var getThemeFunc: (@convention(c) () -> Int32)?
    private var setThemeFunc: (@convention(c) (Int32, Bool) -> Void)?
    private var getSwitchesAutomaticallyFunc: (@convention(c) () -> Bool)?
    private var setSwitchesAutomaticallyFunc: (@convention(c) (Bool) -> Void)?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else { return }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: type) }
        }

        getThemeFunc = load("SLSGetAppearanceThemeLegacy", as: (@convention(c) () -> Int32).self)
        setThemeFunc = load("SLSSetAppearanceThemeNotifying", as: (@convention(c) (Int32, Bool) -> Void).self)
        getSwitchesAutomaticallyFunc = load("SLSGetAppearanceThemeSwitchesAutomatically", as: (@convention(c) () -> Bool).self)
        setSwitchesAutomaticallyFunc = load("SLSSetAppearanceThemeSwitchesAutomatically", as: (@convention(c) (Bool) -> Void).self)
    }

    /// Whether the appearance is Dark right now, which with Auto depends on the time of day.
    func isDark() -> Bool? {
        getThemeFunc.map { $0() == darkTheme }
    }

    /// Choosing Light or Dark turns Auto off, as it does in System Settings, even if that's what Auto
    /// has it set to already. `completion` is called on the main thread once the screen has changed over.
    func setDark(_ isDark: Bool, completion: @escaping () -> Void = {}) {
        guard let current = self.isDark(), let setTheme = setThemeFunc else { return completion() }

        if getSwitchesAutomaticallyFunc?() == true {
            setSwitchesAutomaticallyFunc?(false)
        }
        guard isDark != current else { return completion() }

        // System Settings' steps: `NSGlobalPreferenceTransition` (not in the public headers) takes a
        // picture of the screen, the appearance is set without telling anyone, and then the transition
        // tells every app and fades the picture out over them as they redraw. Without it, the
        // appearance is set the plain way, and apps change over one by one.
        let makeTransition = NSSelectorFromString("transition")
        let postChange = NSSelectorFromString("postChangeNotification:completionHandler:")
        if let transitionClass = NSClassFromString("NSGlobalPreferenceTransition") as? NSObject.Type,
           transitionClass.responds(to: makeTransition),
           let transition = transitionClass.perform(makeTransition)?.takeUnretainedValue() as? NSObject,
           transition.responds(to: postChange) {
            setTheme(isDark ? darkTheme : lightTheme, false)
            // The transition keeps the completion handler until the fade is over, so it has to be escaping
            typealias PostChange = @convention(c) (NSObject, Selector, UInt, @escaping @convention(block) () -> Void) -> Void
            unsafeBitCast(transition.method(for: postChange), to: PostChange.self)(transition, postChange, 0) {
                DispatchQueue.main.async(execute: completion)
            }
        } else {
            setTheme(isDark ? darkTheme : lightTheme, true)
            completion()
        }
    }
}

// MARK: - 8. System Strings (System Settings' Translations)
/// Every label in the app, read from the string tables System Settings (or Control Center, or
/// AppKit) loads the same label from, so it comes out in the system language, worded exactly as there.
/// Each keeps its English text as a fallback in case a table ever moves or drops the key.
enum SystemStrings {
    private static let accessibilitySettings = "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
    private static let displaysSettings = "/System/Library/ExtensionKit/Extensions/DisplaysExt.appex"
    private static let controlCenterSettings = "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex"
    /// Where `AppearancePicker` finds its thumbnails as well.
    static let appearanceSettings = "/System/Library/ExtensionKit/Extensions/Appearance.appex"
    private static let appKit = "/System/Library/Frameworks/AppKit.framework"
    private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework"
    private static let controlCenter = "/System/Library/CoreServices/ControlCenter.app"
    private static let dock = "/System/Library/CoreServices/Dock.app"
    
    // System Settings › Accessibility › Display › Color Filters
    static let colorFilters = lookup("display.colorFilter.enable", in: accessibilitySettings, english: "Color filters")
    static let intensity = lookup("display.colorFilter.intensity", in: accessibilitySettings, english: "Intensity")
    static let low = lookup("display.colorFilter.intensity.low", in: accessibilitySettings, english: "Low")
    static let high = lookup("display.colorFilter.intensity.high", in: accessibilitySettings, english: "High")
    static let tint = lookup("display.colorFilter.tint", in: accessibilitySettings, english: "Tint")
    
    // System Settings › Displays (Schedule is Night Shift's)
    static let brightness = lookup("Brightness", in: displaysSettings, english: "Brightness")
    static let schedule = lookup("Schedule", in: displaysSettings, english: "Schedule")
    static let customize = lookup("Customize…", in: displaysSettings, english: "Customize…")

    // System Settings › Appearance
    static let appearance = lookup("Appearance", in: appearanceSettings, english: "Appearance")
    static let light = lookup("Light", in: appearanceSettings, english: "Light")
    static let dark = lookup("Dark", in: appearanceSettings, english: "Dark")

    // System Settings › Accessibility's buttons for lists, and System Settings › Control Center's Time
    static let add = lookup("global.button.add", in: accessibilitySettings, english: "Add")
    static let delete = lookup("global.button.delete", in: accessibilitySettings, english: "Delete")
    static let restoreDefaults = lookup("keyboard.access.restoreDefaults", in: accessibilitySettings, english: "Restore Defaults")
    static let time = lookup("Time", in: controlCenterSettings, english: "Time")

    // The Edit menu SwiftUI gives this app, whose Undo and Redo the Schedule window's buttons are
    static let undo = lookup("Undo", table: "MainMenu", in: swiftUI, english: "Undo")
    static let redo = lookup("Redo", table: "MainMenu", in: swiftUI, english: "Redo")

    // The title of Control Center's Display module, which this popover stands in for
    static let display = lookup("Display", table: "Display", in: controlCenter, english: "Display")
    
    // System Settings › Control Center's Reset button, and AppKit's Quit button
    static let reset = lookup("Reset", in: controlCenterSettings, english: "Reset")
    static let quit = lookup("Quit", table: "Document", in: appKit, english: "Quit")
    
    // The status item's menu: the Dock's Options › Open at Login, and the app menu's Quit item
    static let openAtLogin = lookup("OPEN_AT_LOGIN", table: "DockMenus", in: dock, english: "Open at Login")
    static let quitApp = String(format: lookup("Quit %@", table: "MainMenu", in: swiftUI, english: "Quit %@"), appName)
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SlowBurn"
    }
    
    /// The user's preferred languages. This app has no translations of its own, so a plain
    /// `localizedString` lookup would follow the app into English; asking with these picks each
    /// table's closest match the way System Settings does (e.g. French (Canada) before French).
    private static let languages = Locale.preferredLanguages.map(Locale.Language.init(identifier:))
    
    private static func lookup(_ key: String, table: String = "Localizable", in bundlePath: String, english: String) -> String {
        guard let bundle = Bundle(path: bundlePath) else { return english }
        return bundle.localizedString(forKey: key, value: english, table: table, localizations: languages)
    }
}
