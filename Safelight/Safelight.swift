import SwiftUI
import Cocoa
import ApplicationServices
import Foundation // Required for dynamic library loading
import ServiceManagement
#if canImport(Sparkle) // Not in scripts/screenshots.sh's copy, which leaves updates out
import Sparkle
#endif

// MARK: - 1. App Entry Point
@main
struct SafelightApp: App {
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
    #if canImport(Sparkle)
    private let updates = Updates()
    #endif
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if canImport(Sparkle)
        // First, as it may quit to open the installed copy instead
        Updates.leaveTranslocation()
        updates.start()
        // Closed first like Customize…, so Sparkle's window isn't left behind it
        updates.willCheckForUpdates = { [weak self] in self?.popover.performClose(nil) }
        #endif

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // The app icon's dial, as a symbol drawn by scripts/make-icon.py
            let image = NSImage(named: "safelight.dial")
            image?.accessibilityDescription = SystemStrings.display
            button.image = image
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuView(customizeSchedule: { [weak self] in
            self?.popover.performClose(nil)
            ScheduleWindow.shared.show()
        }, options: { [weak self] in
            self?.optionItems() ?? []
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
        menu.items = optionItems()
        
        // Attached only while it's open, so a plain click still reaches the popover.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    /// The status item's menu, which the ⋯ button in the popover's corner opens too. Made each time
    /// it opens, as Open at Login can also be changed in System Settings › General › Login Items.
    func optionItems() -> [NSMenuItem] {
        let about = NSMenuItem(title: SystemStrings.aboutApp, action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        let openAtLogin = NSMenuItem(title: SystemStrings.openAtLogin, action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        openAtLogin.target = self
        openAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        var items = [about, .separator(), openAtLogin]
        #if canImport(Sparkle)
        items += updates.menuItems
        #endif
        #if DEBUG
        let scheduleLayout = NSMenuItem(title: "Schedule Layout…", action: #selector(showScheduleLayout(_:)), keyEquivalent: "")
        scheduleLayout.target = self
        let controlColors = NSMenuItem(title: "Control Colours…", action: #selector(showControlColors(_:)), keyEquivalent: "")
        controlColors.target = self
        items += [.separator(), scheduleLayout, controlColors]
        #endif
        let quit = NSMenuItem(title: SystemStrings.quitApp, action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        return items + [.separator(), quit]
    }
    
    /// AppKit's About panel, with the version and the copyright line from Info.plist, and the credits
    @objc private func showAbout(_ sender: NSMenuItem) {
        // Closed first like Customize…, so the panel isn't left behind it
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The build number is the version, for Sparkle, so it isn't shown again as "1.0 (1.0)"
        NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits, .version: ""])
    }
    
    /// Links to the source code, its issues and GitHub Sponsors, as the README has, one to a line so
    /// none breaks in two. Sparkle's licence, which asks to come with every copy of it, comes in the
    /// app's resources as Sparkle License.txt instead.
    private static var credits: NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString()
        let links = [
            (SystemStrings.sourceCode, "https://github.com/MorusPatre/Safelight"),
            (SystemStrings.reportAnIssue, "https://github.com/MorusPatre/Safelight/issues"),
            ("GitHub Sponsors", "https://github.com/sponsors/MorusPatre"),
        ]
        for (title, url) in links {
            if credits.length > 0 {
                credits.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
            credits.append(NSAttributedString(string: title, attributes: [.font: font, .link: URL(string: url)!]))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        return credits
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
            NSLog("Safelight: couldn't change Open at Login: \(error)")
        }
        // The user turned it off in Login Items before; only they can allow it again there.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
    
    #if DEBUG
    @objc private func showScheduleLayout(_ sender: NSMenuItem) {
        ScheduleLayoutWindow.shared.show()
    }

    // The popover opens beside the panel too, after the menu has closed, so its controls can be seen
    // changing
    @objc private func showControlColors(_ sender: NSMenuItem) {
        ControlColorsWindow.shared.show()
        DispatchQueue.main.async {
            if !self.popover.isShown { self.togglePopover(nil) }
        }
    }
    #endif

    @objc func quit(_ sender: Any?) {
        ColorController.shared.reset()
        NSApplication.shared.terminate(nil)
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                #if DEBUG
                // While the Control Colours panel is open, clicking in it leaves the popover open
                popover.behavior = ControlColorsWindow.shared.isVisible ? .semitransient : .transient
                #endif
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

// MARK: - Updates
#if canImport(Sparkle)
/// Keeps Safelight up to date with Sparkle, from the feed in Info.plist. With Automatic Updates on, as
/// it is to begin with, it looks at the latest GitHub release once a day, downloads anything newer in
/// the background, and installs it the next time Safelight quits, so an update never resets the screen
/// while it's in use. It installs only a disk image signed with the key whose public half is in
/// Info.plist (SUPublicEDKey); scripts/release.sh signs each one.
final class Updates: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController!
    /// Called when Check for Updates… is chosen, before Sparkle's window opens
    var willCheckForUpdates: () -> Void = {}

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Starts checking, once Safelight knows it isn't about to reopen from elsewhere.
    func start() {
        controller.startUpdater()
    }

    /// macOS runs an app that isn't notarized from a hidden, read-only copy of itself (App
    /// Translocation) for as long as it has the quarantine flag it was downloaded with, even once the
    /// user has allowed it with Open Anyway and copied it into Applications. Sparkle can't replace that
    /// copy, so Safelight would never update. So when it starts that way, it takes the flag off the
    /// copy that's installed, as Sparkle does with each update it installs, and opens that one
    /// instead. From a disk image, which is read-only, it carries on as it is.
    static func leaveTranslocation() {
        // In the Security framework, which AppKit has loaded already, but not in its public headers
        typealias IsTranslocatedURL = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> DarwinBoolean
        typealias CreateOriginalPathForURL = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let loaded = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let isTranslocatedURL = dlsym(loaded, "SecTranslocateIsTranslocatedURL").map({ unsafeBitCast($0, to: IsTranslocatedURL.self) }),
              let createOriginalPathForURL = dlsym(loaded, "SecTranslocateCreateOriginalPathForURL").map({ unsafeBitCast($0, to: CreateOriginalPathForURL.self) })
        else { return }

        let running = Bundle.main.bundleURL as CFURL
        var isTranslocated = false
        guard isTranslocatedURL(running, &isTranslocated, nil).boolValue, isTranslocated,
              let installed = createOriginalPathForURL(running, nil)?.takeRetainedValue() as URL?,
              removexattr(installed.path, "com.apple.quarantine", XATTR_NOFOLLOW) == 0
        else { return }
        if let files = FileManager.default.enumerator(at: installed, includingPropertiesForKeys: nil) {
            for case let file as URL in files {
                removexattr(file.path, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
        }

        // Opened once this copy has quit, so the two never run at once
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open \"$2\"",
                            "sh", String(getpid()), installed.path]
        if (try? reopen.run()) != nil {
            exit(0)
        }
    }

    /// For the status item's menu: the Automatic Updates switch, and Check for Updates…, which looks
    /// right away and shows what it finds.
    var menuItems: [NSMenuItem] {
        let automaticUpdates = NSMenuItem(title: SystemStrings.automaticUpdates, action: #selector(toggleAutomaticUpdates(_:)), keyEquivalent: "")
        automaticUpdates.target = self
        automaticUpdates.state = isAutomatic ? .on : .off
        let checkForUpdates = NSMenuItem(title: SystemStrings.checkForUpdates, action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        checkForUpdates.target = self
        return [automaticUpdates, checkForUpdates]
    }

    @objc private func checkForUpdates(_ sender: NSMenuItem) {
        willCheckForUpdates()
        controller.checkForUpdates(sender)
    }

    /// Check for Updates… is dimmed while Sparkle is checking already, as it is when it targets Sparkle
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(checkForUpdates(_:)) || controller.updater.canCheckForUpdates
    }

    /// Sparkle keeps checking and installing as two settings; the switch is on when both are. Sparkle's
    /// own update window can turn installing off by itself.
    private var isAutomatic: Bool {
        controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
    }

    /// Off, Safelight looks for updates only when asked to. Sparkle only changes installing while
    /// checking is on, so installing goes off first and on second.
    @objc private func toggleAutomaticUpdates(_ sender: NSMenuItem) {
        let updater = controller.updater
        if isAutomatic {
            updater.automaticallyDownloadsUpdates = false
            updater.automaticallyChecksForUpdates = false
        } else {
            updater.automaticallyChecksForUpdates = true
            updater.automaticallyDownloadsUpdates = true
        }
    }

    #if DEBUG
    /// A Debug build only looks when asked: an update it found by itself would replace the build being
    /// worked on with the release when it quits, and scripts/run.sh would then launch that instead.
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updatesInBackground {
            throw CocoaError(.userCancelled)
        }
    }
    #endif

    /// Safelight has no Dock icon, so Sparkle shows an update it found by itself behind the app in use
    /// rather than taking the focus from it. Saying that's all right keeps Sparkle from warning about it.
    var supportsGentleScheduledUpdateReminders: Bool { true }
}
#endif

// MARK: - 3. UI (Menu View)
struct MenuView: View {
    @ObservedObject var controller = ColorController.shared
    let customizeSchedule: () -> Void
    /// The status item's menu, for the ⋯ button
    let options: () -> [NSMenuItem]
    
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
                            .controlTint(hue: controller.tint, for: .colorFiltersSwitch)
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

                    intensitySlider
                        .controlTint(hue: controller.tint, for: .intensitySlider)
                        .disabled(controller.isAutoMode)
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
                // This drives System Settings › Displays' Brightness: one slider for every display, or
                // while they're adjusted independently, one for each, under its name.
                if controller.independentDisplays.isEmpty {
                    GridRow {
                        Text(SystemStrings.brightness)
                            .fontWeight(.medium)
                            .frame(minWidth: 75, alignment: .leading)

                        brightnessSlider(value: $controller.brightness)
                    }
                } else {
                    GridRow(alignment: .firstTextBaseline) {
                        Text(SystemStrings.brightness)
                            .fontWeight(.medium)
                            .frame(minWidth: 75, alignment: .leading)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(controller.independentDisplays) { display in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(display.name)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    brightnessSlider(value: $controller[brightnessOf: display.key])
                                }
                            }
                        }
                    }
                }

                // Only there with more than one display to adjust, unless it's on already
                if controller.displays.count > 1 || controller.adjustsDisplaysIndependently {
                    GridRow {
                        HStack {
                            Text(SystemStrings.adjustIndependently)
                                .fontWeight(.medium)
                            Spacer()
                            Toggle(SystemStrings.adjustIndependently, isOn: $controller.adjustsDisplaysIndependently)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .controlTint(Color(hue: 42 / 360, saturation: 0.55, brightness: 0.8).opacity(0.2), for: .adjustIndependentlySwitch)  // a muted gold
                        }
                        .gridCellColumns(2)
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // --- APPEARANCE SECTION ---
                // This drives System Settings › Appearance (Light and Dark).
                GridRow(alignment: .top) {
                    Text(SystemStrings.appearance)
                        .fontWeight(.medium)
                        .frame(minWidth: 75, alignment: .leading)

                    AppearancePicker(isDark: Binding(
                        get: { controller.isDarkAppearance },
                        set: { controller.chooseAppearance(isDark: $0) }
                    ))
                    .disabled(controller.isAutoMode || controller.isChangingAppearance)
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

                // Quit is in here, with the rest of the status item's menu, so it can be found
                // without a right-click
                OptionsButton(items: options)
                    .help(SystemStrings.options)
            }
        }
        .padding()
        .frame(width: 320)
        .animation(.easeInOut, value: controller.isAutoMode)
    }

    /// System Settings' Intensity slider: seven tick marks evenly spaced from end to end, with Low and
    /// High as the names of the first and last. Before macOS 26, which has no tick labels, Low and High
    /// go under the ends of a plain slider.
    @ViewBuilder
    private var intensitySlider: some View {
        let range = ColorFilterManager.shared.intensityRange
        if #available(macOS 26.0, *) {
            let spacing = (range.upperBound - range.lowerBound) / 6
            Slider(value: $controller.intensity, in: range) {
                Text(SystemStrings.intensity)
            } ticks: {
                SliderTick(SystemStrings.low, range.lowerBound)
                SliderTickContentForEach((1...5).map { range.lowerBound + spacing * Float($0) }, id: \.self) {
                    SliderTick($0)
                }
                SliderTick(SystemStrings.high, range.upperBound)
            }
            .labelsHidden()
        } else {
            VStack(spacing: 2) {
                Slider(value: $controller.intensity, in: range)

                HStack {
                    Text(SystemStrings.low).font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text(SystemStrings.high).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }

    private func brightnessSlider(value: Binding<Float>) -> some View {
        Slider(
            value: value,
            in: 0.0...1.0,
            onEditingChanged: { isEditing in
                controller.isUserDraggingSlider = isEditing
            }
        )
        .controlTint(.white, hasShadow: true, for: .brightnessSliders)
        .disabled(controller.isAutoMode)
    }
}

// MARK: - Options Button
/// The ⋯ in the popover's corner: a pull-down, like Finder's Action button, that opens the status
/// item's menu under itself. It opens as the mouse goes down, and an item can be chosen by dragging to
/// it and letting go, as in any menu.
struct OptionsButton: NSViewRepresentable {
    let items: () -> [NSMenuItem]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = Button(frame: .zero, pullsDown: true)
        button.isBordered = false
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.imagePosition = .imageOnly
        // The colour SwiftUI gives the gear button's icon
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(SystemStrings.options)
        button.menu?.delegate = context.coordinator
        button.menu?.items = [Coordinator.titleItem()]
        return button
    }

    // Only as big as the ⋯, so it lines up with the edge as Quit did. A pop-up button takes all the
    // width it's offered, and asks for room round its image besides.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.image?.size ?? nsView.intrinsicContentSize
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.items = items
    }

    /// Without the 5 points a pop-up button keeps to the left of its bezel: borderless, it centres the
    /// ⋯ in its whole frame, which put it that much short of the edge
    final class Button: NSPopUpButton {
        override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
    }

    final class Coordinator: NSObject, NSMenuDelegate {
        var items: () -> [NSMenuItem] = { [] }

        /// A pull-down shows its first item on the button, not in the menu
        static func titleItem() -> NSMenuItem {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: SystemStrings.options)
            return item
        }

        /// Made afresh each time it opens, as the status item's menu is
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.items = [Self.titleItem()] + items()
        }
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

// MARK: - Time Field
/// A time of day as hours and minutes in a field with a stepper, like `DatePicker`'s `.stepperField`
/// style, but with the time centred in the field: AppKit puts it 1.5 pt high, so the selected hour or
/// minute touches the top of the field.
struct TimeField: NSViewRepresentable {
    var label: String
    @Binding var selection: Date
    /// Whether the field takes the keyboard as soon as it's in a window, with its hours selected to type over
    var isFocusedOnAppear = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TimeFieldPicker {
        let picker = TimeFieldPicker()
        picker.becomesFirstResponderInWindow = isFocusedOnAppear
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        // Only as wide as the time and its stepper, like DatePicker
        picker.setContentHuggingPriority(.required, for: .horizontal)
        picker.setContentHuggingPriority(.required, for: .vertical)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateDidChange(_:))
        picker.setAccessibilityLabel(label)
        return picker
    }

    func updateNSView(_ picker: TimeFieldPicker, context: Context) {
        context.coordinator.dateDidChangeHandler = { selection = $0 }
        // Only the time zone is taken from the environment, as the picker's calendar, which it reads as
        // changed each time, selects the hours again whenever it's set
        if picker.timeZone != context.environment.timeZone {
            picker.timeZone = context.environment.timeZone
        }
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
        picker.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var dateDidChangeHandler: (Date) -> Void = { _ in }

        @objc func dateDidChange(_ sender: NSDatePicker) {
            dateDidChangeHandler(sender.dateValue)
        }
    }
}

/// A date picker set up as any other, field and all, but with a `TimeFieldCell`.
final class TimeFieldPicker: NSDatePicker {
    var becomesFirstResponderInWindow = false

    override class var cellClass: AnyClass? {
        get { TimeFieldCell.self }
        set { super.cellClass = newValue }
    }

    // SwiftUI puts the picker in the window while it updates the view, so the picker takes the keyboard
    // straight after, rather than make the field it takes it from end editing in the middle of the update
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard becomesFirstResponderInWindow, window != nil else { return }
        becomesFirstResponderInWindow = false
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
            self.needsDisplay = true // or its hours aren't shown selected until something else redraws it
            self.scrollToVisible(self.bounds) // in case the rows scroll
        }
    }
}

/// A date picker cell that draws its text and selection lower down, in the middle of its field.
/// AppKit only draws them along with the field, so the cell draws in three goes: a cell of its own
/// draws the field with no text, this cell draws its stepper, and then its text and selection without
/// the field, lower down. Clicks are still matched to the hours and minutes where AppKit puts them,
/// which is only 1.5 pt higher.
final class TimeFieldCell: NSDatePickerCell {
    private static let textDrop: CGFloat = 1.5
    /// The width AppKit gives the stepper at the right of the cell, which takes in the gap between it
    /// and the field
    private static let stepperWidth = NSStepperCell().cellSize.width

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Split where the stepper starts, with room all round, as AppKit draws a little past the frame
        let canvas = cellFrame.insetBy(dx: -cellFrame.width, dy: -cellFrame.height)
        let (stepperArea, fieldArea) = canvas.divided(atDistance: canvas.maxX - (cellFrame.maxX - Self.stepperWidth), from: .maxXEdge)

        let fieldCell = NSDatePickerCell()
        fieldCell.datePickerStyle = datePickerStyle
        fieldCell.datePickerElements = datePickerElements
        fieldCell.controlSize = controlSize
        fieldCell.font = font
        fieldCell.isEnabled = isEnabled
        fieldCell.isBezeled = isBezeled
        fieldCell.textColor = .clear
        draw(clippedTo: fieldArea) {
            fieldCell.draw(withFrame: cellFrame, in: controlView)
        }
        // The stepper is this cell's own, so it shows the arrow being pressed
        draw(clippedTo: stepperArea) {
            super.draw(withFrame: cellFrame, in: controlView)
        }
        // Without the field, which is put back straight after, before anything lays the cell out again
        let isBezeled = isBezeled
        self.isBezeled = false
        draw(clippedTo: fieldArea) {
            super.draw(withFrame: cellFrame.offsetBy(dx: 0, dy: controlView.isFlipped ? Self.textDrop : -Self.textDrop), in: controlView)
        }
        self.isBezeled = isBezeled
    }

    private func draw(clippedTo area: NSRect, _ drawing: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        area.clip()
        drawing()
        NSGraphicsContext.restoreGraphicsState()
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
    private static let thumbnailCornerRadius: CGFloat = 5

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
                                .clipShape(RoundedRectangle(cornerRadius: Self.thumbnailCornerRadius))
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

    /// A thumbnail scaled down to `height`, as an image for the Schedule window's `AppearanceSegments`:
    /// drawn as here, with its corners and the highlight in it in the accent colour, and redrawn each
    /// time it's shown, so it follows the accent colour. Its name is what VoiceOver reads for it.
    static func thumbnail(isDark: Bool, height: CGFloat) -> NSImage {
        let thumbnail = artwork?.image(forResource: isDark ? "AppearanceDark" : "AppearanceLight")
        let highlight = artwork?.image(forResource: "selectionColor_mask")
        let scale = height / thumbnailSize.height
        let size = NSSize(width: (thumbnailSize.width * scale).rounded(), height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            let cornerRadius = cornerRadius(ofThumbnail: height)
            guard let thumbnail else {
                // The same plain window colour stands in
                let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor(white: isDark ? 0.15 : 0.95, alpha: 1).setFill()
                outline.fill()
                NSColor.separatorColor.setStroke()
                outline.stroke()
                return true
            }
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).addClip()
            thumbnail.draw(in: rect)
            if let highlight, let context = NSGraphicsContext.current?.cgContext {
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                highlight.draw(in: rect)
                NSColor.controlAccentColor.setFill()
                rect.fill(using: .sourceAtop)
                context.endTransparencyLayer()
            }
            return true
        }
        image.accessibilityDescription = isDark ? SystemStrings.dark : SystemStrings.light
        return image
    }

    /// The radius of the corners of a thumbnail scaled down to `height`
    static func cornerRadius(ofThumbnail height: CGFloat) -> CGFloat {
        thumbnailCornerRadius * height / thumbnailSize.height
    }
}

/// Light and Dark for a keyframe in the Schedule window: a segmented control with the Appearance
/// picker's thumbnails in its segments. It's AppKit's own control rather than a segmented `Picker`,
/// whose segments leave 5 pt either side of an image, so the segments' widths can be set: each
/// thumbnail leaves `border` above and below it, and its segment is that much wider either side.
/// AppKit's selection would fill the chosen segment out to corners of its own, far rounder than the
/// thumbnail's, and right up to the thumbnail, hard to tell from the blue in it. So `Cell` draws the
/// control instead, as AppKit's own looks but with a thin ring around the chosen thumbnail, a gap
/// between them, and corners that follow the thumbnail's.
struct AppearanceSegments: NSViewRepresentable {
    @Binding var isDark: Bool

    private static let ringWidth: CGFloat = 2
    private static let gap: CGFloat = 1
    private static let border = ringWidth + gap
    /// The height of a segmented control, which each segment is
    private static let controlHeight = NSSegmentedControl(labels: [""], trackingMode: .selectOne, target: nil, action: nil).fittingSize.height
    private static let thumbnailHeight = controlHeight - 2 * border
    private static let thumbnails = [false, true].map { AppearancePicker.thumbnail(isDark: $0, height: thumbnailHeight) }
    private static let segmentWidths = thumbnails.map { $0.size.width + 2 * border }
    /// The corners of the track, the ring and a pressed segment, around the thumbnail's
    private static let cornerRadius = AppearancePicker.cornerRadius(ofThumbnail: thumbnailHeight) + border

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = Control(
            images: Self.thumbnails, trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.selectionDidChange(_:))
        )
        for (segment, width) in Self.segmentWidths.enumerated() {
            control.setWidth(width, forSegment: segment)
            control.setToolTip(segment == 1 ? SystemStrings.dark : SystemStrings.light, forSegment: segment)
        }
        control.setAccessibilityLabel(SystemStrings.appearance)
        return control
    }

    // The size is given rather than asked of the control. One made while SwiftUI is updating, as a
    // row added with + is, takes the widths set above only afterwards, and until then measures as if
    // its segments had their own widths (80 pt instead of 68 when it happened); once they arrive it
    // doesn't say its size has changed, so the row kept the wider frame, with the segments centred in
    // it, out of line.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: Self.segmentWidths.reduce(0, +), height: Self.controlHeight)
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selectionDidChangeHandler = { isDark = $0 }
        control.selectedSegment = isDark ? 1 : 0
        control.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var selectionDidChangeHandler: (Bool) -> Void = { _ in }

        @objc func selectionDidChange(_ sender: NSSegmentedControl) {
            selectionDidChangeHandler(sender.selectedSegment == 1)
        }
    }

    final class Control: NSSegmentedControl {
        override class var cellClass: AnyClass? {
            get { Cell.self }
            set {}
        }
    }

    /// Draws the control in place of AppKit, which still handles clicks, keys, tooltips and VoiceOver.
    /// Its track, the pressed segment and the selection in a window that isn't key are the colours of
    /// AppKit's own on macOS 27, and disabled, the thumbnails and ring are half as opaque, as there.
    final class Cell: NSSegmentedCell {
        /// The segment under the pointer while the control is pressed, darker until it's let go,
        /// or until the pointer leaves the control
        private var pressedSegment: Int?

        override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
            NSColor.secondarySystemFill.setFill()
            NSBezierPath(roundedRect: cellFrame, xRadius: cornerRadius, yRadius: cornerRadius).fill()

            let context = NSGraphicsContext.current?.cgContext
            let isKey = controlView.window?.isKeyWindow ?? false
            for segment in 0..<segmentCount {
                guard let image = image(forSegment: segment) else { continue }
                let imageRect = imageRect(of: image, inSegment: segment, of: cellFrame)
                let outline = outline(around: imageRect)
                if segment == pressedSegment {
                    NSColor.labelColor.withAlphaComponent(0.16).setFill()
                    outline.fill()
                }

                // In a layer of its own, as drawing an image sets the context's alpha to its own
                context?.saveGState()
                context?.setAlpha(isEnabled ? 1 : 0.5)
                context?.beginTransparencyLayer(auxiliaryInfo: nil)
                if isSelected(forSegment: segment) {
                    let ringRect = imageRect.insetBy(dx: -border + ringWidth, dy: -border + ringWidth)
                    outline.append(NSBezierPath(roundedRect: ringRect, xRadius: cornerRadius - ringWidth, yRadius: cornerRadius - ringWidth))
                    outline.windingRule = .evenOdd
                    (isKey ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
                    outline.fill()
                }
                image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                context?.endTransparencyLayer()
                context?.restoreGState()
            }
        }

        // Around the segment the arrow keys are on, as AppKit's own is, but with the corners above.
        // AppKit only says which that is privately; without it, the ring is AppKit's own.
        override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
            guard responds(to: NSSelectorFromString("_keySegment")), let segment = value(forKey: "_keySegment") as? Int,
                  (0..<segmentCount).contains(segment), let image = image(forSegment: segment) else {
                super.drawFocusRingMask(withFrame: cellFrame, in: controlView)
                return
            }
            outline(around: imageRect(of: image, inSegment: segment, of: cellFrame)).fill()
        }

        override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
            press(at: startPoint, in: controlView)
            return super.startTracking(at: startPoint, in: controlView)
        }

        override func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool {
            press(at: currentPoint, in: controlView)
            return super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)
        }

        override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
            press(at: nil, in: controlView)
            super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        }

        private func press(at point: NSPoint?, in controlView: NSView) {
            let segment = point.flatMap { point in
                (0..<segmentCount).first { frame(ofSegment: $0, in: controlView.bounds).contains(point) }
            }
            if segment != pressedSegment {
                pressedSegment = segment
                controlView.needsDisplay = true
            }
        }

        private func frame(ofSegment segment: Int, in cellFrame: NSRect) -> NSRect {
            let x = (0..<segment).reduce(cellFrame.minX) { $0 + width(forSegment: $1) }
            return NSRect(x: x, y: cellFrame.minY, width: width(forSegment: segment), height: cellFrame.height)
        }

        /// A segment's thumbnail, in the middle of it
        private func imageRect(of image: NSImage, inSegment segment: Int, of cellFrame: NSRect) -> NSRect {
            let frame = frame(ofSegment: segment, in: cellFrame)
            return NSRect(x: frame.midX - image.size.width / 2, y: frame.midY - image.size.height / 2,
                          width: image.size.width, height: image.size.height)
        }

        /// A thumbnail and the border around it, which the ring and a pressed segment fill
        private func outline(around imageRect: NSRect) -> NSBezierPath {
            NSBezierPath(roundedRect: imageRect.insetBy(dx: -border, dy: -border), xRadius: cornerRadius, yRadius: cornerRadius)
        }
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
            // (and, in Debug builds, as the Schedule Layout panel changes it)
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
        guard let window else { return }
        let isOpen = window.isVisible || window.isMiniaturized
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Each opening starts with no time selected, where the window would select the first row's, or
        // keep the one selected when it closed. Already open, it keeps the one being typed.
        if !isOpen {
            window.makeFirstResponder(nil)
        }
    }

    // The window grows downwards as rows are added, and to the right as columns are, so one near the
    // bottom or right of the screen moves to stay on it
    func windowDidResize(_ notification: Notification) {
        guard let window, let visibleFrame = window.screen?.visibleFrame else { return }
        var origin = window.frame.origin
        if window.frame.minY < visibleFrame.minY {
            origin.y = visibleFrame.minY
        }
        if window.frame.maxX > visibleFrame.maxX {
            origin.x = max(visibleFrame.maxX - window.frame.width, visibleFrame.minX)
        }
        if origin != window.frame.origin {
            window.setFrameOrigin(origin)
        }
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
    #if DEBUG
    @ObservedObject private var layoutTuner = ScheduleLayoutTuner.shared
    private var layout: ScheduleLayout { layoutTuner.layout }
    #else
    private let layout = ScheduleLayout.standard
    #endif
    /// The keyframe the + button added last, whose time is ready to type as soon as its row is in
    @State private var addedKeyframeID: ColorKeyframe.ID?

    // Laid out like a grouped Form, whose sections are never wider than about 700 pt, so the window
    // can be as wide as the columns need
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.boxSpacing) {
                ScheduleDayView(schedule: controller.schedule, displays: brightnessColumns.map { $0?.key })
                    .scheduleBox(padding: layout.boxPadding)

                // Each column after the first is set off from the one before by its own gap
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: layout.rowSpacing) {
                    GridRow {
                        Text(SystemStrings.time)
                        Text(SystemStrings.colorFilters)
                            .padding(.leading, layout.gapBeforeColorFilters)
                        Text(SystemStrings.intensity)
                            .padding(.leading, layout.gapBeforeIntensity)
                        Text(SystemStrings.tint)
                            .padding(.leading, layout.gapBeforeTint)
                        ForEach(brightnessColumns, id: \.self) { display in
                            Text(display?.name ?? SystemStrings.brightness)
                                .padding(.leading, layout.gapBeforeBrightness)
                        }
                        Text(SystemStrings.appearance)
                            .padding(.leading, layout.gapBeforeAppearance)

                        // Add heads the column of the keyframes' Delete buttons
                        Button {
                            addedKeyframeID = controller.addKeyframe()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help(SystemStrings.add)
                        .accessibilityLabel(SystemStrings.add)
                        .padding(.leading, layout.gapBeforeDelete)
                    }
                    .foregroundStyle(.secondary)

                    ForEach($controller.schedule) { $keyframe in
                        // A grouped Form's lighter line between rows
                        Rectangle()
                            .fill(Color(nsColor: .quinaryLabelColor))
                            .frame(height: 1)
                            .gridCellUnsizedAxes(.horizontal)

                        GridRow {
                            TimeField(label: SystemStrings.time, selection: time(of: keyframe.id), isFocusedOnAppear: keyframe.id == addedKeyframeID)
                                .environment(\.timeZone, Self.utc)

                            Toggle(SystemStrings.colorFilters, isOn: $keyframe.isColorFilterOn)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .controlTint(hue: keyframe.tint, for: .scheduleColorFiltersSwitches)
                                .padding(.leading, layout.gapBeforeColorFilters)

                            // Holding any of the sliders shows its keyframe on screen until it's let go
                            Slider(value: $keyframe.intensity, in: ColorFilterManager.shared.intensityRange) {
                                Text(SystemStrings.intensity)
                            } onEditingChanged: { isEditing in
                                controller.preview(isEditing ? keyframe.id : nil)
                            }
                            .labelsHidden()
                            .controlTint(hue: keyframe.tint, for: .scheduleIntensitySliders)
                            .disabled(!keyframe.isColorFilterOn)
                            .frame(width: layout.intensityWidth)
                            .padding(.leading, layout.gapBeforeIntensity)

                            TintSlider(value: $keyframe.tint) { isEditing in
                                controller.preview(isEditing ? keyframe.id : nil)
                            }
                            .disabled(!keyframe.isColorFilterOn)
                            .opacity(keyframe.isColorFilterOn ? 1.0 : 0.6)
                            .frame(width: layout.tintWidth)
                            .padding(.leading, layout.gapBeforeTint)

                            ForEach(brightnessColumns, id: \.self) { display in
                                Slider(value: display.map { $keyframe[brightnessOf: $0.key] } ?? $keyframe.brightness, in: 0.0...1.0) {
                                    Text(display?.name ?? SystemStrings.brightness)
                                } onEditingChanged: { isEditing in
                                    controller.preview(isEditing ? keyframe.id : nil)
                                }
                                .labelsHidden()
                                .controlTint(.white, hasShadow: true, for: .scheduleBrightnessSliders)
                                .frame(width: layout.brightnessWidth)
                                .padding(.leading, layout.gapBeforeBrightness)
                            }

                            AppearanceSegments(isDark: $keyframe.isDarkAppearance)
                                .fixedSize()
                                .padding(.leading, layout.gapBeforeAppearance)

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
                            .padding(.leading, layout.gapBeforeDelete)
                        }
                    }
                }
                // Only as wide as its columns and gaps (offered more, a Grid shares it out between
                // all its columns), and the window with it
                .fixedSize(horizontal: true, vertical: false)
                .scheduleBox(padding: layout.boxPadding)
            }
            .padding(.horizontal, layout.sideMargin)
            .padding(.top, layout.topMargin)
            .padding(.bottom, layout.bottomMargin)
        }
        .frame(maxHeight: maxHeight)
        .fixedSize()
    }

    /// A Brightness column for each display while they're adjusted independently, headed by its name,
    /// or one for all of them
    private var brightnessColumns: [Display?] {
        controller.independentDisplays.isEmpty ? [nil] : controller.independentDisplays
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
/// through it, a line at the current time, and a dot under each keyframe. While the displays are
/// adjusted independently, the strip has a band for each, from the top down in the order of their columns.
struct ScheduleDayView: View {
    let schedule: [ColorKeyframe]
    /// The `Display.key` of each band, or nil for one band for all displays
    let displays: [String?]

    private let stripHeight: CGFloat = 36

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            Canvas { context, size in
                let outline = Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: stripHeight), cornerRadius: 6)
                func x(ofMinute minute: Double) -> CGFloat { size.width * minute / 1440 }

                context.drawLayer { strip in
                    strip.clip(to: outline)
                    let bandHeight = stripHeight / CGFloat(max(displays.count, 1))
                    for x in 0..<Int(size.width.rounded(.up)) {
                        guard let settings = ColorKeyframe.settings(in: schedule, at: Double(x) / size.width * 1440) else { continue }
                        for (band, display) in displays.enumerated() {
                            let pixel = CGRect(x: CGFloat(x), y: CGFloat(band) * bandHeight, width: 1, height: bandHeight)
                            strip.fill(Path(pixel), with: .color(settings.previewColor(ofDisplay: display)))
                        }
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

private extension View {
    /// One of the Schedule window's boxes, drawn like a section of a grouped Form, as wide as the window has room for.
    func scheduleBox(padding: CGFloat) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(scheduleBoxFill, in: RoundedRectangle(cornerRadius: 12, style: .circular))
    }
}

/// A grouped Form's sections are a touch darker in light mode, and lighter in dark mode, than the window.
private let scheduleBoxFill = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.03) : NSColor(white: 0, alpha: 0.03)
})

// MARK: - Schedule Layout
/// The widths of the Schedule window's sliders and the space around its boxes, rows and columns,
/// which the window takes its size from. Debug builds can change them in the Schedule Layout panel to
/// try others out; release builds always use `standard`, which matches a grouped Form.
struct ScheduleLayout: Equatable {
    var sideMargin: CGFloat = 28
    var topMargin: CGFloat = 20
    var bottomMargin: CGFloat = 20
    var boxPadding: CGFloat = 10
    var boxSpacing: CGFloat = 28
    var intensityWidth: CGFloat = 160
    var tintWidth: CGFloat = 160
    var brightnessWidth: CGFloat = 160
    var rowSpacing: CGFloat = 15
    var gapBeforeColorFilters: CGFloat = 40
    var gapBeforeIntensity: CGFloat = 40
    var gapBeforeTint: CGFloat = 40
    var gapBeforeBrightness: CGFloat = 40
    var gapBeforeAppearance: CGFloat = 40
    var gapBeforeDelete: CGFloat = 40

    static let standard = ScheduleLayout()
}

#if DEBUG
extension ScheduleLayout {
    /// The tighter spacing the Schedule window had as a grouped Form, before it could be changed.
    static let compact = ScheduleLayout(
        boxSpacing: 10,
        intensityWidth: 120, tintWidth: 120, brightnessWidth: 120,
        rowSpacing: 10,
        gapBeforeColorFilters: 16, gapBeforeIntensity: 16, gapBeforeTint: 16,
        gapBeforeBrightness: 16, gapBeforeAppearance: 16, gapBeforeDelete: 16
    )

    /// Layouts the Schedule Layout panel can switch to at once.
    static let templates: [(name: String, layout: ScheduleLayout)] = [
        ("Spacious", .standard),
        ("Compact", .compact),
    ]
}
#endif

#if DEBUG
/// The layout the Schedule window has in Debug builds, kept between launches until it's restored.
final class ScheduleLayoutTuner: ObservableObject {
    static let shared = ScheduleLayoutTuner()

    /// A value the panel has a slider for, and the key it's saved under.
    struct Field: Identifiable {
        let key: String
        let name: String
        let keyPath: WritableKeyPath<ScheduleLayout, CGFloat>
        let range: ClosedRange<CGFloat>
        var id: String { key }
    }

    static let windowFields = [
        Field(key: "sideMargin", name: "Sides", keyPath: \.sideMargin, range: 0...80),
        Field(key: "topMargin", name: "Top", keyPath: \.topMargin, range: 0...80),
        Field(key: "bottomMargin", name: "Bottom", keyPath: \.bottomMargin, range: 0...80),
    ]

    static let boxFields = [
        Field(key: "boxPadding", name: "Inside each box", keyPath: \.boxPadding, range: 0...40),
        Field(key: "boxSpacing", name: "Between boxes", keyPath: \.boxSpacing, range: 0...40),
    ]

    static let widthFields = [
        Field(key: "intensityWidth", name: SystemStrings.intensity, keyPath: \.intensityWidth, range: 60...300),
        Field(key: "tintWidth", name: SystemStrings.tint, keyPath: \.tintWidth, range: 60...300),
        Field(key: "brightnessWidth", name: SystemStrings.brightness, keyPath: \.brightnessWidth, range: 60...300),
    ]

    static let gapFields = [
        Field(key: "gapBeforeColorFilters", name: SystemStrings.colorFilters, keyPath: \.gapBeforeColorFilters, range: 0...80),
        Field(key: "gapBeforeIntensity", name: SystemStrings.intensity, keyPath: \.gapBeforeIntensity, range: 0...80),
        Field(key: "gapBeforeTint", name: SystemStrings.tint, keyPath: \.gapBeforeTint, range: 0...80),
        Field(key: "gapBeforeBrightness", name: SystemStrings.brightness, keyPath: \.gapBeforeBrightness, range: 0...80),
        Field(key: "gapBeforeAppearance", name: SystemStrings.appearance, keyPath: \.gapBeforeAppearance, range: 0...80),
        Field(key: "gapBeforeDelete", name: SystemStrings.delete, keyPath: \.gapBeforeDelete, range: 0...80),
    ]

    static let rowSpacingField = Field(key: "rowSpacing", name: "Row spacing", keyPath: \.rowSpacing, range: 0...30)

    private static let fields = windowFields + boxFields + widthFields + gapFields + [rowSpacingField]

    private static let defaultsKey = "scheduleLayout"

    @Published var layout: ScheduleLayout {
        didSet { save() }
    }

    private init() {
        var layout = ScheduleLayout.standard
        let saved = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        for field in Self.fields {
            if let value = saved[field.key] { layout[keyPath: field.keyPath] = value }
        }
        self.layout = layout
    }

    // Saved as numbers by name, so `defaults read Mo.Safelight scheduleLayout` shows them
    private func save() {
        guard layout != .standard else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        let values = Self.fields.map { ($0.key, Double(layout[keyPath: $0.keyPath])) }
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: values), forKey: Self.defaultsKey)
    }
}

/// Sliders for the Schedule window's layout, which moves as they're dragged. Each changes only the
/// width or space it's named for, and the window grows and shrinks to fit.
struct ScheduleLayoutPanel: View {
    @ObservedObject var tuner = ScheduleLayoutTuner.shared

    var body: some View {
        Form {
            Section {
                Picker("Template", selection: template) {
                    ForEach(ScheduleLayout.templates, id: \.name) { template in
                        Text(template.name).tag(Optional(template.name))
                    }
                    // Only there to name values that aren't a template's
                    if templateName == nil {
                        Text("Custom").tag(String?.none)
                    }
                }
            }

            Section("Space to the window's edges") {
                ForEach(ScheduleLayoutTuner.windowFields, content: row)
            }

            Section("Space around the boxes") {
                ForEach(ScheduleLayoutTuner.boxFields, content: row)
            }

            Section("Width of each slider") {
                ForEach(ScheduleLayoutTuner.widthFields, content: row)
            }

            Section("Space before each column") {
                row("All columns", value: allGaps, in: 0...80, isChanged: ScheduleLayoutTuner.gapFields.contains(where: isChanged), help: "Sets every column's gap at once") {
                    for field in ScheduleLayoutTuner.gapFields { reset(field) }
                }
                ForEach(ScheduleLayoutTuner.gapFields, content: row)
            }

            Section {
                row(ScheduleLayoutTuner.rowSpacingField)
            } footer: {
                Button(SystemStrings.restoreDefaults) {
                    tuner.layout = .standard
                }
                .disabled(tuner.layout == .standard)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ field: ScheduleLayoutTuner.Field) -> some View {
        row(field.name, value: $tuner.layout[dynamicMember: field.keyPath], in: field.range, isChanged: isChanged(field), help: "Standard: \(Int(ScheduleLayout.standard[keyPath: field.keyPath])) pt") {
            reset(field)
        }
    }

    /// A slider and stepper for one value, which reads in bold once it's been changed, with a button
    /// to put it back that's there only then.
    private func row(_ name: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>, isChanged: Bool, help: String, reset: @escaping () -> Void) -> some View {
        LabeledContent(name) {
            HStack {
                // Rounded to whole points as it's dragged; a `step` would draw a tick mark for each one
                Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: range)
                    .frame(width: 150)
                Text("\(Int(value.wrappedValue)) pt")
                    .monospacedDigit()
                    .fontWeight(isChanged ? .bold : .regular)
                    .frame(width: 52, alignment: .trailing)
                Stepper(name, value: value, in: range, step: 1)
                    .labelsHidden()

                // Hidden rather than left out while there's nothing to reset, so the rows stay lined up
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset")
                .accessibilityLabel("Reset \(name)")
                .opacity(isChanged ? 1 : 0)
                .disabled(!isChanged)
            }
        }
        .help(help)
    }

    private func isChanged(_ field: ScheduleLayoutTuner.Field) -> Bool {
        tuner.layout[keyPath: field.keyPath] != ScheduleLayout.standard[keyPath: field.keyPath]
    }

    private func reset(_ field: ScheduleLayoutTuner.Field) {
        tuner.layout[keyPath: field.keyPath] = ScheduleLayout.standard[keyPath: field.keyPath]
    }

    /// The template the layout is, if it's one of them.
    private var templateName: String? {
        ScheduleLayout.templates.first { $0.layout == tuner.layout }?.name
    }

    /// Choosing a template sets every value to its own.
    private var template: Binding<String?> {
        Binding(
            get: { templateName },
            set: { name in
                if let template = ScheduleLayout.templates.first(where: { $0.name == name }) {
                    tuner.layout = template.layout
                }
            }
        )
    }

    /// Every column's gap at once, reading as the widest of them.
    private var allGaps: Binding<CGFloat> {
        Binding(
            get: { ScheduleLayoutTuner.gapFields.map { tuner.layout[keyPath: $0.keyPath] }.max() ?? 0 },
            set: { gap in
                for field in ScheduleLayoutTuner.gapFields { tuner.layout[keyPath: field.keyPath] = gap }
            }
        )
    }
}

/// The floating panel with `ScheduleLayoutPanel`, from Schedule Layout… in the status item's menu.
final class ScheduleLayoutWindow {
    static let shared = ScheduleLayoutWindow()
    private var panel: NSPanel?

    func show() {
        ScheduleWindow.shared.show()
        if panel == nil {
            let hostingController = NSHostingController(rootView: ScheduleLayoutPanel())
            hostingController.sizingOptions = [.minSize, .maxSize]
            let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.contentViewController = hostingController
            panel.title = "Schedule Layout"
            panel.isFloatingPanel = true
            panel.isReleasedWhenClosed = false
            panel.setContentSize(hostingController.sizeThatFits(in: panel.contentMaxSize))
            panel.center()
            panel.setFrameAutosaveName("ScheduleLayout") // back where it was left, if it's been moved
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
    }
}
#endif

// MARK: - Control Colours
/// A switch or slider drawn in a colour of its own, or in each of the Schedule window's rows. Debug
/// builds can draw each in the accent colour instead, in the Control Colours panel.
enum TintedControl: String, CaseIterable, Identifiable {
    case colorFiltersSwitch
    case intensitySlider
    case brightnessSliders
    case adjustIndependentlySwitch
    case scheduleColorFiltersSwitches
    case scheduleIntensitySliders
    case scheduleBrightnessSliders

    var id: String { rawValue }
}

extension View {
    /// Draws `control` in `color`, with a soft shadow if `hasShadow`, which sets a white slider apart
    /// from a light background, unless a Debug build is set to draw it in the accent colour, with no
    /// shadow, as macOS would.
    func controlTint(_ color: Color, hasShadow: Bool = false, for control: TintedControl) -> some View {
        modifier(ControlTint(color: color, hasShadow: hasShadow, control: control))
    }

    /// Draws `control` in the colour filter's hue, `tint` degrees round the colour wheel, so it shows
    /// the tint that's applied.
    func controlTint(hue tint: Float, for control: TintedControl) -> some View {
        controlTint(Color(hue: Double(tint) / 360, saturation: 1.0, brightness: 1.0), for: control)
    }
}

private struct ControlTint: ViewModifier {
    let color: Color
    let hasShadow: Bool
    let control: TintedControl
    #if DEBUG
    @ObservedObject private var controlColors = ControlColors.shared
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        if controlColors.accentColored.contains(control) {
            content
        } else {
            tinted(content)
        }
        #else
        tinted(content)
        #endif
    }

    @ViewBuilder
    private func tinted(_ content: Content) -> some View {
        if hasShadow {
            content
                .tint(color)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        } else {
            content
                .tint(color)
        }
    }
}

#if DEBUG
extension TintedControl {
    static let popover: [TintedControl] = [.colorFiltersSwitch, .intensitySlider, .brightnessSliders, .adjustIndependentlySwitch]
    static let schedule: [TintedControl] = [.scheduleColorFiltersSwitches, .scheduleIntensitySliders, .scheduleBrightnessSliders]

    var name: String {
        switch self {
        case .colorFiltersSwitch, .scheduleColorFiltersSwitches: SystemStrings.colorFilters
        case .intensitySlider, .scheduleIntensitySliders: SystemStrings.intensity
        case .brightnessSliders, .scheduleBrightnessSliders: SystemStrings.brightness
        case .adjustIndependentlySwitch: SystemStrings.adjustIndependently
        }
    }

    /// What Custom draws it in.
    var customColor: String {
        switch self {
        case .colorFiltersSwitch, .intensitySlider, .scheduleColorFiltersSwitches, .scheduleIntensitySliders: "the filter's hue"
        case .brightnessSliders, .scheduleBrightnessSliders: "white, with a soft shadow"
        case .adjustIndependentlySwitch: "a muted gold"
        }
    }
}

/// The switches and sliders Debug builds draw in the accent colour, kept between launches until
/// they're all Custom again. Release builds draw every one in its own colour.
final class ControlColors: ObservableObject {
    static let shared = ControlColors()
    private static let defaultsKey = "controlColors"

    /// Choices the panel can make for every control at once.
    static let presets: [(name: String, accentColored: Set<TintedControl>)] = [
        ("Custom", []),
        // The filter's hue only on the controls that show the tint
        ("Mixed", [.brightnessSliders, .adjustIndependentlySwitch, .scheduleBrightnessSliders]),
        ("Accent Colour", Set(TintedControl.allCases)),
    ]

    @Published var accentColored: Set<TintedControl> {
        didSet { save() }
    }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        accentColored = Set(saved.compactMap(TintedControl.init))
    }

    // Saved by name, so `defaults read Mo.Safelight controlColors` shows them
    private func save() {
        guard !accentColored.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            return
        }
        let names = TintedControl.allCases.filter(accentColored.contains).map(\.rawValue)
        UserDefaults.standard.set(names, forKey: Self.defaultsKey)
    }
}

/// Custom or Accent Colour for each switch and slider that has a colour of its own, which it takes on
/// as it's chosen, and presets that choose for every one at once.
struct ControlColorsPanel: View {
    @ObservedObject var controlColors = ControlColors.shared

    var body: some View {
        Form {
            Section {
                Picker("Preset", selection: preset) {
                    ForEach(ControlColors.presets, id: \.name) { preset in
                        Text(preset.name).tag(Optional(preset.name))
                    }
                    // Only there to name choices that aren't a preset's
                    if presetName == nil {
                        Text("Individual").tag(String?.none)
                    }
                }
            }

            Section("Popover") {
                ForEach(TintedControl.popover, content: row)
            }

            Section("Schedule window") {
                ForEach(TintedControl.schedule, content: row)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ control: TintedControl) -> some View {
        Picker(control.name, selection: usesAccentColor(control)) {
            Text("Custom").tag(false)
            Text("Accent Colour").tag(true)
        }
        .pickerStyle(.segmented)
        .help("Custom: \(control.customColor)")
    }

    private func usesAccentColor(_ control: TintedControl) -> Binding<Bool> {
        Binding(
            get: { controlColors.accentColored.contains(control) },
            set: { usesAccentColor in
                if usesAccentColor {
                    controlColors.accentColored.insert(control)
                } else {
                    controlColors.accentColored.remove(control)
                }
            }
        )
    }

    /// The preset the choices are, if they're one of them.
    private var presetName: String? {
        ControlColors.presets.first { $0.accentColored == controlColors.accentColored }?.name
    }

    /// Choosing a preset makes every choice its own.
    private var preset: Binding<String?> {
        Binding(
            get: { presetName },
            set: { name in
                if let preset = ControlColors.presets.first(where: { $0.name == name }) {
                    controlColors.accentColored = preset.accentColored
                }
            }
        )
    }
}

/// The floating panel with `ControlColorsPanel`, from Control Colours… in the status item's menu.
final class ControlColorsWindow {
    static let shared = ControlColorsWindow()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible == true }

    func show() {
        if panel == nil {
            let hostingController = NSHostingController(rootView: ControlColorsPanel())
            hostingController.sizingOptions = [.minSize, .maxSize]
            let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            panel.contentViewController = hostingController
            panel.title = "Control Colours"
            panel.isFloatingPanel = true
            panel.isReleasedWhenClosed = false
            panel.setContentSize(hostingController.sizeThatFits(in: panel.contentMaxSize))
            panel.center()
            panel.setFrameAutosaveName("ControlColors") // back where it was left, if it's been moved
            self.panel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}
#endif

// MARK: - 4. Logic Controller
class ColorController: ObservableObject {
    static let shared = ColorController()
    
    // Mirror of the system Color Tint filter, kept the way System Settings keeps it: `intensity` is
    // the value the system stores, and `tint` is in degrees (0–360), stored as degrees / 360.
    @Published var isColorFilterOn: Bool = false { didSet { updateColorFilter() } }
    @Published var intensity: Float = 1.0 { didSet { colorSliderChanged() } }
    @Published var tint: Float = 0.0      { didSet { colorSliderChanged() } }
    @Published var brightness: Float = 1.0 { didSet { updateBrightness() } }
    /// Each display's own brightness, by its `Display.key`, while the displays are adjusted independently
    @Published var displayBrightness: [String: Float] = [:] { didSet { updateBrightness() } }

    /// The displays the Mac draws to, kept up to date as they're connected, disconnected and arranged
    @Published private(set) var displays: [Display] = Display.connected()
    /// Whether each display has a brightness of its own, in the Schedule too, rather than all of them
    /// having one. Saved as it's changed.
    @Published var adjustsDisplaysIndependently = UserDefaults.standard.bool(forKey: ColorController.adjustsDisplaysIndependentlyDefaultsKey) {
        didSet { displayAdjustmentChanged() }
    }
    private static let adjustsDisplaysIndependentlyDefaultsKey = "adjustsDisplaysIndependently"

    /// The displays with a brightness of their own, in the order their sliders are shown, or none while
    /// they all have one
    var independentDisplays: [Display] { adjustsDisplaysIndependently ? displays : [] }

    // Mirror of the system appearance: Dark or Light, whether it was chosen or Auto switched to it.
    @Published private(set) var isDarkAppearance: Bool = false
    /// True from when an appearance is chosen here until the screen has changed over to it.
    @Published private(set) var isChangingAppearance: Bool = false
    
    @Published var isAutoMode: Bool = false {
        didSet {
            scheduledIsDarkAppearance = nil
            scheduledDisplayBrightness = [:]
            if isAutoMode { applyAutoSettings() }
        }
    }

    /// The appearance the Schedule has for now, once it's been set. It's set again only when this
    /// changes, so an appearance chosen in System Settings or Control Center stays until then, rather
    /// than the screen fading back within the minute.
    private var scheduledIsDarkAppearance: Bool?
    /// Each display's brightness on the Schedule when it last set them, while they're adjusted
    /// independently. A display stepped with the brightness keys stays where they put it until the
    /// Schedule moves on, as the display macOS sets the brightness of does.
    private var scheduledDisplayBrightness: [String: Float] = [:]

    var isUserDraggingSlider: Bool = false
    /// The keyframe on screen while one of its sliders in the Schedule window is held down. Meanwhile
    /// the settings above aren't written to the system or read back from it, so they're what comes back.
    private var previewedKeyframeID: ColorKeyframe.ID?
    /// The display whose slider is being moved to where the system has set it, so it isn't set again
    private var syncingDisplay: CGDirectDisplayID?
    private var isSyncingColorFilter: Bool = false
    
    /// The displays the Mac sets the brightness of itself, which a slider follows as the system changes it
    private var displaysWithSystemBrightness: Set<CGDirectDisplayID> = []
    private var brightnessFollowers: [CGDirectDisplayID: BrightnessFollower] = [:]
    /// Where the brightness keys have put each display whose slider is still easing over to it
    private var brightnessKeyTargets: [String: Float] = [:]

    /// The display the Brightness slider follows while the displays have one brightness: the main
    /// display, or if it's dimmed in software, the first that the Mac sets the brightness of itself
    private var leadDisplay: CGDirectDisplayID? {
        let mainDisplay = CGMainDisplayID()
        if displaysWithSystemBrightness.contains(mainDisplay) { return mainDisplay }
        return displays.first { displaysWithSystemBrightness.contains($0.id) }?.id
    }
    
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
        displaysWithSystemBrightness = Set(displays.map(\.id).filter(GammaManager.shared.canSetBrightness))
        // Each display's slider starts where the display is, and the displays dimmed in software aren't
        // yet. Set first, as setting either sets the displays, and with only `brightness` they'd all take it.
        if adjustsDisplaysIndependently {
            self.displayBrightness = Dictionary(displays.map { ($0.key, GammaManager.shared.getNativeBrightness(of: $0.id) ?? 1.0) }) { first, _ in first }
        }
        if let leadDisplay, let nativeBrightness = GammaManager.shared.getNativeBrightness(of: leadDisplay) {
            self.brightness = nativeBrightness
        }
        
        // Follow displays being connected, disconnected and rearranged
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.displaysDidChange()
        }
        // An iPad's name can arrive after its display, which until then has macOS's own name for it
        NotificationCenter.default.addObserver(
            forName: Sidecar.connectedDevicesChangedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            if let self, Display.connected() != displays { displaysDidChange() }
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

        // While the displays are adjusted independently, the brightness keys set the one under the pointer
        BrightnessKeys.shared.handlePress = { [weak self] isUp, isFine in
            self?.brightnessKeyPressed(isUp: isUp, isFine: isFine) ?? false
        }
        if adjustsDisplaysIndependently {
            BrightnessKeys.shared.start(askingPermission: false)
        }

        // 🚀 UPGRADE: 120 FPS polling (0.0083 seconds)
        let smoothSyncTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.syncWithSystemBrightness()
            self?.easeTowardBrightnessKeyTargets()
        }
        RunLoop.main.add(smoothSyncTimer, forMode: .common)
        self.syncTimer = smoothSyncTimer
    }
    
    func syncWithSystemBrightness() {
        guard !isAutoMode, !isUserDraggingSlider, previewedKeyframeID == nil else {
            brightnessFollowers = [:]
            return 
        }
        
        // Each display the Mac sets the brightness of moves its own slider, or while the displays have
        // one brightness, the one the Brightness slider follows moves it
        if adjustsDisplaysIndependently {
            for display in displays where displaysWithSystemBrightness.contains(display.id) {
                follow(display.id, from: self[brightnessOf: display.key]) { self[brightnessOf: display.key] = $0 }
            }
        } else if let leadDisplay {
            follow(leadDisplay, from: brightness) { brightness = $0 }
        }
    }

    /// Moves a slider at `current` after the brightness the system has set a display to.
    private func follow(_ displayID: CGDirectDisplayID, from current: Float, by setBrightness: (Float) -> Void) {
        guard let systemBrightness = GammaManager.shared.getNativeBrightness(of: displayID) else { return }
        var follower = brightnessFollowers[displayID] ?? BrightnessFollower(systemBrightness: systemBrightness)
        if let brightness = follower.follow(systemBrightness, from: current) {
            syncingDisplay = displayID
            setBrightness(brightness)
            syncingDisplay = nil
        }
        brightnessFollowers[displayID] = follower
    }

    /// Steps the display under the pointer the way macOS steps the one it sets the brightness of: by a
    /// sixteenth, or a quarter of that with Option-Shift, from between two steps to the next one along.
    /// Returns false to leave the key to macOS: while the displays have one brightness, as they all
    /// follow the display macOS sets, and when that display is under the pointer and its only one.
    private func brightnessKeyPressed(isUp: Bool, isFine: Bool) -> Bool {
        guard adjustsDisplaysIndependently,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let display = displays.first(where: { $0.id == number.uint32Value }),
              displaysWithSystemBrightness != [display.id] else { return false }

        let steps: Float = isFine ? 64 : 16
        let current = brightnessKeyTargets[display.key] ?? self[brightnessOf: display.key]
        let step = isUp ? (current * steps + 0.01).rounded(.down) + 1 : (current * steps - 0.01).rounded(.up) - 1
        brightnessKeyTargets[display.key] = min(max(step / steps, 0), 1)
        return true
    }

    /// Moves each slider the brightness keys have stepped a frame further over to where they put it,
    /// easing over as a slider following a key press on the display macOS sets does. Holding a slider
    /// stops them where they are.
    private func easeTowardBrightnessKeyTargets() {
        guard !brightnessKeyTargets.isEmpty else { return }
        guard !isUserDraggingSlider, previewedKeyframeID == nil else {
            brightnessKeyTargets = [:]
            return
        }
        for (display, target) in brightnessKeyTargets {
            let brightness = BrightnessFollower.ease(from: self[brightnessOf: display], to: target)
            self[brightnessOf: display] = brightness
            if brightness == target { brightnessKeyTargets[display] = nil }
        }
    }

    /// A display's brightness while the displays are adjusted independently, which is `brightness`
    /// until it's been set
    subscript(brightnessOf display: String) -> Float {
        get { displayBrightness[display] ?? brightness }
        set { displayBrightness[display] = newValue }
    }

    /// The displays carry on from where they are: split, each starts at the brightness they all had,
    /// and joined, they all take the brightness of the one the Brightness slider follows. Split, the
    /// brightness keys are caught as well, with permission, which macOS asks for the first time.
    private func displayAdjustmentChanged() {
        UserDefaults.standard.set(adjustsDisplaysIndependently, forKey: Self.adjustsDisplaysIndependentlyDefaultsKey)
        brightnessFollowers = [:]
        brightnessKeyTargets = [:]
        scheduledDisplayBrightness = [:]
        if adjustsDisplaysIndependently {
            displayBrightness = Dictionary(displays.map { ($0.key, brightness) }) { first, _ in first }
            // After the switch has redrawn, as macOS's request for permission comes up over it
            DispatchQueue.main.async { [weak self] in
                if self?.adjustsDisplaysIndependently == true { BrightnessKeys.shared.start(askingPermission: true) }
            }
        } else {
            BrightnessKeys.shared.stop()
            if let display = displays.first(where: { $0.id == leadDisplay }) ?? displays.first {
                brightness = self[brightnessOf: display.key]
            }
        }
        applyAutoSettings()
    }

    /// Lists the displays again, and sets them all again, as the system puts back the colors of a
    /// display it changes. A display connected for the first time while they're adjusted independently
    /// starts where it is.
    private func displaysDidChange() {
        displays = Display.connected()
        displaysWithSystemBrightness = Set(displays.map(\.id).filter(GammaManager.shared.canSetBrightness))
        brightnessFollowers = [:]
        GammaManager.shared.reset()

        let newDisplays = displays.filter { displayBrightness[$0.key] == nil }
        if adjustsDisplaysIndependently && !newDisplays.isEmpty {
            displayBrightness.merge(newDisplays.map { ($0.key, GammaManager.shared.getNativeBrightness(of: $0.id) ?? 1.0) }) { current, _ in current }
        }
        applyAutoSettings()
        updateBrightness()
        showPreview()
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
        if adjustsDisplaysIndependently {
            let scheduled = Dictionary(displays.map { ($0.key, settings.brightness(of: $0.key)) }) { first, _ in first }
            // One the Schedule hasn't moved on for stays where it is, which is elsewhere if the brightness keys stepped it
            self.displayBrightness = Dictionary(uniqueKeysWithValues: scheduled.map { display, brightness in
                (display, scheduledDisplayBrightness[display] == brightness ? displayBrightness[display] ?? brightness : brightness)
            })
            scheduledDisplayBrightness = scheduled
        }
        if settings.isDarkAppearance != scheduledIsDarkAppearance {
            scheduledIsDarkAppearance = settings.isDarkAppearance
            applyScheduledAppearance()
        }
    }

    /// Adds a keyframe at the next free half hour, set to what the schedule already has there, and returns its ID.
    @discardableResult
    func addKeyframe() -> ColorKeyframe.ID {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nextHalfHour = ((now.hour! * 60 + now.minute!) / 30 + 1) * 30
        let taken = Set(schedule.map(\.minute))
        let minute = (0..<48).lazy.map { (nextHalfHour + $0 * 30) % 1440 }.first { !taken.contains($0) } ?? nextHalfHour % 1440

        let settings = ColorKeyframe.settings(in: schedule, at: Double(minute))
            ?? ColorKeyframe.Settings(intensity: isColorFilterOn ? intensity : 0, tint: tint, brightness: brightness, displayBrightness: displayBrightness, isDarkAppearance: isDarkAppearance)
        let keyframe = ColorKeyframe(
            minute: minute,
            isColorFilterOn: settings.isColorFilterOn,
            intensity: settings.filterIntensity,
            tint: settings.tint,
            brightness: settings.brightness,
            displayBrightness: settings.displayBrightness,
            isDarkAppearance: settings.isDarkAppearance
        )
        schedule.append(keyframe)
        return keyframe.id
    }

    /// The schedule always keeps at least one keyframe.
    func deleteKeyframe(_ id: ColorKeyframe.ID) {
        guard schedule.count > 1 else { return }
        schedule.removeAll { $0.id == id }
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
        GammaManager.shared.setBrightness(brightnessByDisplay(keyframe.brightness, keyframe.displayBrightness))
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
        GammaManager.shared.setBrightness(brightnessByDisplay(brightness, displayBrightness), skippingHardwareOf: syncingDisplay)
    }

    /// Each display's brightness: `brightness` for all of them, or while they're adjusted independently,
    /// each one's own from `displayBrightness`, if it has one.
    private func brightnessByDisplay(_ brightness: Float, _ displayBrightness: [String: Float]) -> [CGDirectDisplayID: Float] {
        Dictionary(displays.map { display in
            (display.id, adjustsDisplaysIndependently ? displayBrightness[display.key] ?? brightness : brightness)
        }) { first, _ in first }
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
            self?.changeSystemAppearance(isDark: isDark)
        }
    }

    /// Changes the screen over to the Schedule's appearance in the same order. The picker is dimmed
    /// already while the Schedule is on, but whatever changed the Schedule's appearance (a row in the
    /// Schedule window, or the Schedule switch) shows it first for as long as the picker would dim.
    private func applyScheduledAppearance() {
        guard isAutoMode, let isDark = scheduledIsDarkAppearance, !isChangingAppearance else { return }
        guard isDark != isDarkAppearance else {
            AppearanceManager.shared.setDark(isDark) // nothing to change over to, but Auto would change it at sunset
            return
        }

        isDarkAppearance = isDark
        isChangingAppearance = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.changeSystemAppearance(isDark: isDark)
        }
    }

    private func changeSystemAppearance(isDark: Bool) {
        AppearanceManager.shared.setDark(isDark) { [weak self] in
            guard let self else { return }
            isChangingAppearance = false
            syncWithSystemAppearance()
            // The Schedule moved on to another appearance before the screen had changed over
            if scheduledIsDarkAppearance != isDark { applyScheduledAppearance() }
        }
    }

    func syncWithSystemAppearance() {
        guard !isChangingAppearance, let isDark = AppearanceManager.shared.isDark() else { return }
        if isDarkAppearance != isDark { isDarkAppearance = isDark }
    }
    
    func reset() {
        isAutoMode = false
        brightnessFollowers = [:]
        brightnessKeyTargets = [:]
        isColorFilterOn = false
        brightness = 1.0
        displayBrightness = [:]
    }
}

/// Follows a display's brightness as the system changes it (with the brightness keys, Control Center
/// or System Settings) for a slider to show: it keeps up while the system's slider is dragged, and eases
/// over to a jump made with a click or a key.
struct BrightnessFollower {
    private var lastSystemBrightness: Float
    private var lastNativeUpdateTime: TimeInterval = 0
    private var targetSystemBrightness: Float?

    init(systemBrightness: Float) {
        lastSystemBrightness = systemBrightness
    }

    /// Where a slider at `current` moves to now that the display is at `systemBrightness`, or nil if it stays.
    mutating func follow(_ systemBrightness: Float, from current: Float) -> Float? {
        var current = current
        var newBrightness: Float?
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
                targetSystemBrightness = nil
                current = systemBrightness
                newBrightness = systemBrightness
            } else {
                // The value changed after being idle. This is the first frame of a new interaction.
                if stepChange > 0.04 {
                    // Large jump -> A Click or Keyboard Tap. Start the ease-out animation!
                    targetSystemBrightness = systemBrightness
                } else {
                    // Small jump -> The very beginning of a slow drag. Snap instantly.
                    current = systemBrightness
                    newBrightness = systemBrightness
                }
            }
        } 
        
        // 2. Process the ease-out animation if we have a target
        if let target = targetSystemBrightness {
            newBrightness = Self.ease(from: current, to: target)
            if newBrightness == target { targetSystemBrightness = nil }
        } else if stepChange <= 0.001 {
            // 3. Not animating, and no native movement this frame.
            // Clean up any microscopic drift to ensure 100% sync.
            let delta = abs(current - systemBrightness)
            if delta > 0.002 {
                newBrightness = systemBrightness
            }
        }
        return newBrightness
    }

    /// One frame of a slider's ease-out from `current` over to `target`, which it lands on exactly.
    static func ease(from current: Float, to target: Float) -> Float {
        let diff = target - current

        // Snap to the target once we are visually indistinguishable from it
        if abs(diff) < 0.002 { return target }

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

        return current + step
    }
}

/// A point on the Schedule: the settings it reaches `minute` minutes after midnight. In between, the
/// settings move steadily from one keyframe to the next, and from the last round midnight to the first,
/// except the appearance, which can't: it changes over at each keyframe and stays until the next.
struct ColorKeyframe: Identifiable, Codable, Equatable {
    var id = UUID()
    var minute: Int
    var isColorFilterOn: Bool
    var intensity: Float // kept while the filter is off, for when it's turned back on
    var tint: Float      // degrees
    var brightness: Float
    /// Each display's own brightness, by its `Display.key`, for while the displays are adjusted
    /// independently. Kept while they aren't, for when they are again.
    var displayBrightness: [String: Float] = [:]
    var isDarkAppearance: Bool

    /// A display's brightness, which is `brightness` until it's been given its own
    subscript(brightnessOf display: String) -> Float {
        get { displayBrightness[display] ?? brightness }
        set { displayBrightness[display] = newValue }
    }

    static let defaultSchedule: [ColorKeyframe] = [
        ColorKeyframe(minute: 5 * 60 + 30,  isColorFilterOn: true,  intensity: 0.90, tint: 0,   brightness: 0.82, isDarkAppearance: true),
        ColorKeyframe(minute: 6 * 60,       isColorFilterOn: false, intensity: 0.25, tint: 180, brightness: 1.00, isDarkAppearance: false),
        ColorKeyframe(minute: 18 * 60,      isColorFilterOn: false, intensity: 0.25, tint: 180, brightness: 1.00, isDarkAppearance: false),
        ColorKeyframe(minute: 18 * 60 + 30, isColorFilterOn: true,  intensity: 0.80, tint: 0,   brightness: 0.92, isDarkAppearance: true),
        ColorKeyframe(minute: 20 * 60 + 30, isColorFilterOn: true,  intensity: 0.90, tint: 0,   brightness: 0.68, isDarkAppearance: true)
    ]

    struct Settings {
        /// 0 where the filter is off, so fading to or from an off keyframe passes the filter's lowest
        /// intensity part way, and that's where the filter switches.
        var intensity: Float
        var tint: Float
        var brightness: Float
        /// The brightness of each display either keyframe has one of its own for
        var displayBrightness: [String: Float] = [:]
        /// The appearance of the keyframe at or before this time
        var isDarkAppearance: Bool

        /// A display's brightness, or with no display, the brightness for all of them
        func brightness(of display: String?) -> Float {
            display.flatMap { displayBrightness[$0] } ?? brightness
        }

        /// The system filter bottoms out at its "Low" intensity, so below that the schedule switches it off
        var isColorFilterOn: Bool { intensity >= ColorFilterManager.shared.intensityRange.lowerBound }
        var filterIntensity: Float {
            let intensityRange = ColorFilterManager.shared.intensityRange
            return min(max(intensity, intensityRange.lowerBound), intensityRange.upperBound)
        }

        /// Roughly how white looks on a display with these settings, for the Schedule window's preview.
        func previewColor(ofDisplay display: String? = nil) -> Color {
            Color(hue: Double(tint) / 360, saturation: isColorFilterOn ? Double(filterIntensity) : 0, brightness: Double(brightness(of: display)))
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
        let displays = Set(start.displayBrightness.keys).union(end.displayBrightness.keys)
        return Settings(
            intensity: startIntensity + (endIntensity - startIntensity) * progress,
            tint: tint,
            brightness: start.brightness + (end.brightness - start.brightness) * progress,
            displayBrightness: Dictionary(uniqueKeysWithValues: displays.map { display in
                (display, start[brightnessOf: display] + (end[brightnessOf: display] - start[brightnessOf: display]) * progress)
            }),
            isDarkAppearance: start.isDarkAppearance
        )
    }
}

extension ColorKeyframe {
    /// Keyframes saved before they had an appearance come back Dark where the color filter is on, as
    /// in the default schedule, and ones saved before displays had a brightness each come back without.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        minute = try container.decode(Int.self, forKey: .minute)
        isColorFilterOn = try container.decode(Bool.self, forKey: .isColorFilterOn)
        intensity = try container.decode(Float.self, forKey: .intensity)
        tint = try container.decode(Float.self, forKey: .tint)
        brightness = try container.decode(Float.self, forKey: .brightness)
        displayBrightness = try container.decodeIfPresent([String: Float].self, forKey: .displayBrightness) ?? [:]
        isDarkAppearance = try container.decodeIfPresent(Bool.self, forKey: .isDarkAppearance) ?? isColorFilterOn
    }
}

// MARK: - 5. System Manager (Gamma & Hardware Brightness)
/// A display the Mac draws to. Mirrored displays are one of these, and take its brightness.
struct Display: Identifiable, Hashable {
    let id: CGDirectDisplayID
    /// The display's UUID, which, unlike its ID, stays the same while it's unplugged and between launches
    let key: String
    /// Its name in System Settings › Displays
    let name: String

    /// The displays from left to right, as they're arranged in System Settings › Displays.
    static func connected() -> [Display] {
        NSScreen.screens
            .sorted { ($0.frame.minX, -$0.frame.maxY) < ($1.frame.minX, -$1.frame.maxY) }
            .compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
                      let key = CFUUIDCreateString(nil, uuid) as String? else { return nil }
                let sidecarName = isSidecar(number.uint32Value) ? Sidecar.deviceName : nil
                return Display(id: number.uint32Value, key: key, name: sidecarName ?? screen.localizedName)
            }
    }

    /// Whether a display is an iPad used with Sidecar, which System Settings tells by its vendor and
    /// model codes, "aapl" and "iPad"
    static func isSidecar(_ displayID: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(displayID) == 0x6161_706C && CGDisplayModelNumber(displayID) == 0x6950_6164
    }
}

/// The iPad used with Sidecar, as the private SidecarCore framework knows it. System Settings names a
/// Sidecar display after it ("iPad"), rather than "Sidecar Display (AirPlay)" as macOS otherwise does.
enum Sidecar {
    /// Posted when an iPad is connected with Sidecar, or disconnected
    static let connectedDevicesChangedNotification = Notification.Name("SidecarDisplayManagerConnectedDevicesChangedNotification")

    private static let manager: NSObject? = {
        let sharedManager = NSSelectorFromString("sharedManager")
        guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) != nil,
              let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              managerClass.responds(to: sharedManager) else { return nil }
        return managerClass.perform(sharedManager)?.takeUnretainedValue() as? NSObject
    }()

    /// The connected iPad's name, as it's called on the iPad. Like System Settings, this takes the first
    /// iPad connected, as Sidecar connects one at a time.
    static var deviceName: String? {
        guard let manager, manager.responds(to: NSSelectorFromString("connectedDevices")),
              let device = (manager.value(forKey: "connectedDevices") as? [NSObject])?.first,
              device.responds(to: NSSelectorFromString("name")),
              let name = device.value(forKey: "name") as? String, !name.isEmpty else { return nil }
        return name
    }
}

class GammaManager {
    static let shared = GammaManager()

    /// The brightness each display was last set to, so one that hasn't changed isn't set again
    private var lastBrightness: [CGDirectDisplayID: Float] = [:]
    /// The displays dimmed in software, and how far
    private var softwareBrightness: [CGDirectDisplayID: Float] = [:]
    /// The dark layer over each display that's sent its picture, as dimming it in software can't reach it
    private var dimmingWindows: [CGDirectDisplayID: DimmingWindow] = [:]
    /// Whether each display is sent its picture, as it was when last asked
    private var streamedDisplays: [CGDirectDisplayID: Bool] = [:]

    private var setBrightnessFunc: (@convention(c) (CGDirectDisplayID, Float) -> Int32)?
    private var getBrightnessFunc: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)?
    private var canChangeBrightnessFunc: (@convention(c) (CGDirectDisplayID) -> Bool)?
    private var displayInfoFunc: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?)?

    init() {
        if let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
           let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") {
            self.displayInfoFunc = unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?).self)
        }
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
    
    /// Whether the Mac sets this display's brightness itself, rather than it being dimmed in software
    func canSetBrightness(of displayID: CGDirectDisplayID) -> Bool {
        canChangeBrightnessFunc?(displayID) ?? false
    }

    func getNativeBrightness(of displayID: CGDirectDisplayID) -> Float? {
        guard let getFunc = getBrightnessFunc else { return nil }
        var brightness: Float = 1.0
        let result = getFunc(displayID, &brightness)
        return result == 0 ? brightness : nil
    }

    /// Sets each display to its brightness, a display that mirrors another to that one's, and leaves
    /// out any display without one. `skippedHardware` is a display the system has set already, which is
    /// only dimmed in software if it can't be set directly.
    func setBrightness(_ displayBrightness: [CGDirectDisplayID: Float], skippingHardwareOf skippedHardware: CGDirectDisplayID? = nil) {
        let displays = getAllDisplays()
        lastBrightness = lastBrightness.filter { displays.contains($0.key) }
        var newSoftwareBrightness = softwareBrightness.filter { displays.contains($0.key) }
        for (displayID, window) in dimmingWindows where !displays.contains(displayID) || !isStreamed(displayID) {
            window.close()
            dimmingWindows[displayID] = nil
        }

        for displayID in displays {
            let mirrorSet = CGDisplayPrimaryDisplay(displayID)
            guard let brightness = displayBrightness[displayID]
                    ?? displayBrightness.first(where: { CGDisplayPrimaryDisplay($0.key) == mirrorSet })?.value else { continue }
            if let lastBrightness = lastBrightness[displayID], abs(brightness - lastBrightness) < 0.001 {
                continue
            }

            lastBrightness[displayID] = brightness

            // A display that's sent its picture is dimmed under a dark layer, which the displays mirroring
            // it show as well, so they're left as they are. It keeps a tenth of the picture, as under a
            // darker layer the iPad looks black.
            if isStreamed(mirrorSet) {
                if displayID == mirrorSet { setDimmingWindow(of: displayID, to: max(brightness, 0.1)) }
                newSoftwareBrightness[displayID] = nil
                continue
            }

            var hardwareBrightnessSucceeded = false

            if canSetBrightness(of: displayID) {
                if displayID != skippedHardware {
                    if let setBrightnessFunc = setBrightnessFunc {
                        let result = setBrightnessFunc(displayID, brightness)
                        if result == 0 { hardwareBrightnessSucceeded = true }
                    }
                } else {
                    hardwareBrightnessSucceeded = true
                }
            }

            let softwareBrightness = hardwareBrightnessSucceeded ? 1.0 : max(brightness, 0.05)
            newSoftwareBrightness[displayID] = softwareBrightness < 0.999 ? softwareBrightness : nil
        }

        // A display's own colors can only be put back along with every other display's, so the ones
        // still dimmed are then dimmed again
        let needsGlobalRestore = softwareBrightness.keys.contains { displays.contains($0) && newSoftwareBrightness[$0] == nil }
        if needsGlobalRestore {
            CGDisplayRestoreColorSyncSettings()
        }
        for (displayID, softwareBrightness) in newSoftwareBrightness where needsGlobalRestore || self.softwareBrightness[displayID] != softwareBrightness {
            let table = calculateGammaTable(brightness: softwareBrightness)
            CGSetDisplayTransferByTable(displayID, UInt32(table.count), table, table, table)
        }
        softwareBrightness = newSoftwareBrightness
    }

    func reset() {
        CGDisplayRestoreColorSyncSettings()
        dimmingWindows.values.forEach { $0.close() }
        dimmingWindows = [:]
        streamedDisplays = [:]
        lastBrightness = [:]
        softwareBrightness = [:]
    }

    /// Whether a display is sent its picture, as Sidecar's iPad and AirPlay displays are. It's sent
    /// before the display's colors are adjusted, so dimming it in software doesn't change it.
    private func isStreamed(_ displayID: CGDirectDisplayID) -> Bool {
        if let isStreamed = streamedDisplays[displayID] { return isStreamed }
        let info = displayInfoFunc?(displayID)?.takeRetainedValue() as NSDictionary?
        let isStreamed = info?["kCGDisplayIsVirtualDevice"] as? Bool ?? false
        streamedDisplays[displayID] = isStreamed
        return isStreamed
    }

    /// Lays a dark layer over a display that lets `brightness` of its picture through, or none at full brightness
    private func setDimmingWindow(of displayID: CGDirectDisplayID, to brightness: Float) {
        guard brightness < 0.999,
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else {
            dimmingWindows.removeValue(forKey: displayID)?.close()
            return
        }
        let window = dimmingWindows[displayID] ?? DimmingWindow()
        window.setFrame(screen.frame, display: false)
        window.alphaValue = CGFloat(1 - brightness)
        window.orderFrontRegardless()
        dimmingWindows[displayID] = window
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

/// A black layer over a whole display that clicks go through, which darkens its picture as dimming it in
/// software does: over everything (the menu bar and full-screen apps too) and on every Space.
final class DimmingWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        backgroundColor = .black
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}

// MARK: - Brightness Keys
/// Catches the brightness keys before macOS acts on them, so a key can set a display macOS doesn't.
/// Catching keys takes permission in System Settings › Privacy & Security › Accessibility; until
/// it's given, they're left to macOS.
final class BrightnessKeys {
    static let shared = BrightnessKeys()

    /// What a press does: brightness up or down, a quarter step (with Option-Shift) or not. Returns
    /// whether it set a display, in which case macOS doesn't see the key. Called on the main thread.
    var handlePress: (_ isUp: Bool, _ isFine: Bool) -> Bool = { _, _ in false }

    /// Apple's keyboards send the brightness keys as these key codes; others send them as media keys,
    /// like the volume keys
    private static let brightnessUpKeyCode: Int64 = 144
    private static let brightnessDownKeyCode: Int64 = 145

    private var tap: CFMachPort?
    /// Checks for permission while it's waited for
    private var permissionTimer: Timer?
    /// The keys (up or down) whose press was handled here, so their release is kept from macOS as
    /// well. Only touched on the tap's thread.
    private var handledKeys: Set<Bool> = []

    /// Starts catching the keys, or once there's permission, if there isn't yet. `askingPermission`
    /// puts up macOS's request for it, which leads to System Settings.
    func start(askingPermission: Bool) {
        guard tap == nil else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: askingPermission] as CFDictionary

        // At the head of the session's taps, where the keys arrive before macOS acts on them
        let keys = CGEventMask(1 << NX_SYSDEFINED) | CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard AXIsProcessTrustedWithOptions(options), let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keys,
            callback: { _, type, event, _ in
                BrightnessKeys.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            permissionTimer = permissionTimer ?? Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.start(askingPermission: false)
            }
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = nil
        self.tap = tap

        // Every key goes through the tap, so it runs on a thread of its own: typing never waits on
        // the main thread, which only hears about the brightness keys. The thread ends with the tap.
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "Brightness Keys"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap) // which takes it off its thread's run loop, and so ends the thread
        self.tap = nil
    }

    /// Whether `event` is a brightness key dealt with here. Presses with Option alone (which opens
    /// Displays settings), Control or Command go on to macOS.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            DispatchQueue.main.async { [self] in
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return false
        }
        guard let (isUp, isPress) = brightnessKey(type, event) else { return false }
        guard isPress else { return handledKeys.remove(isUp) != nil }

        let modifiers = event.flags
        let isFine = modifiers.contains([.maskAlternate, .maskShift])
        guard !modifiers.contains(.maskControl), !modifiers.contains(.maskCommand),
              isFine || !modifiers.contains(.maskAlternate),
              DispatchQueue.main.sync(execute: { handlePress(isUp, isFine) }) else {
            handledKeys.remove(isUp)
            return false
        }
        handledKeys.insert(isUp)
        return true
    }

    /// Which brightness key `event` is, if it's one, and whether it's a press (or its repeat while
    /// the key is held) or a release.
    private func brightnessKey(_ type: CGEventType, _ event: CGEvent) -> (isUp: Bool, isPress: Bool)? {
        if type == .keyDown || type == .keyUp {
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case Self.brightnessUpKeyCode: return (true, type == .keyDown)
            case Self.brightnessDownKeyCode: return (false, type == .keyDown)
            default: return nil
            }
        }
        guard type.rawValue == UInt32(NX_SYSDEFINED),
              let keyEvent = NSEvent(cgEvent: event),
              Int32(keyEvent.subtype.rawValue) == NX_SUBTYPE_AUX_CONTROL_BUTTONS else { return nil }
        let key = Int32((keyEvent.data1 & 0xFFFF0000) >> 16)
        guard key == NX_KEYTYPE_BRIGHTNESS_UP || key == NX_KEYTYPE_BRIGHTNESS_DOWN else { return nil }
        // 0xA is a press, 0xB a release
        return (key == NX_KEYTYPE_BRIGHTNESS_UP, (keyEvent.data1 & 0xFF00) >> 8 == 0xA)
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
/// Every label in the app, read from the string tables System Settings (or Control Center, the Dock,
/// or an app's menus) loads the same label from, so it comes out in the system language, worded
/// exactly as there.
/// Each keeps its English text as a fallback in case a table ever moves or drops the key.
enum SystemStrings {
    private static let accessibilitySettings = "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
    private static let displaysSettings = "/System/Library/ExtensionKit/Extensions/DisplaysExt.appex"
    private static let controlCenterSettings = "/System/Library/ExtensionKit/Extensions/ControlCenterSettings.appex"
    /// Where `AppearancePicker` finds its thumbnails as well.
    static let appearanceSettings = "/System/Library/ExtensionKit/Extensions/Appearance.appex"
    private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework"
    private static let controlCenter = "/System/Library/CoreServices/ControlCenter.app"
    private static let dock = "/System/Library/CoreServices/Dock.app"
    private static let softwareUpdateSettings = "/System/Library/ExtensionKit/Extensions/SoftwareUpdateSettingsExtension.appex"
    private static let maps = "/System/Applications/Maps.app"
    private static let linkPresentation = "/System/Library/Frameworks/LinkPresentation.framework"
    
    // System Settings › Accessibility › Display › Color Filters
    static let colorFilters = lookup("display.colorFilter.enable", in: accessibilitySettings, english: "Color filters")
    static let intensity = lookup("display.colorFilter.intensity", in: accessibilitySettings, english: "Intensity")
    static let low = lookup("display.colorFilter.intensity.low", in: accessibilitySettings, english: "Low")
    static let high = lookup("display.colorFilter.intensity.high", in: accessibilitySettings, english: "High")
    static let tint = lookup("display.colorFilter.tint", in: accessibilitySettings, english: "Tint")
    
    // System Settings › Accessibility › Hearing Devices' switch for setting each hearing aid by itself
    static let adjustIndependently = lookup("mfi.hearingaids.adjust.independently.toggle.title", in: accessibilitySettings, english: "Adjust Independently")
    
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

    // The title of Control Center's Display module, which this popover stands in for
    static let display = lookup("Display", table: "Display", in: controlCenter, english: "Display")
    
    // System Settings › Control Center's Reset button
    static let reset = lookup("Reset", in: controlCenterSettings, english: "Reset")
    
    // The status item's menu, under the name of the Dock's Options menu, which has Open at Login in it;
    // and the app menu's About and Quit items
    static let options = lookup("OPTIONS", table: "DockMenus", in: dock, english: "Options")
    static let openAtLogin = lookup("OPEN_AT_LOGIN", table: "DockMenus", in: dock, english: "Open at Login")
    static let aboutApp = String(format: lookup("About %@", table: "MainMenu", in: swiftUI, english: "About %@"), appName)
    static let quitApp = String(format: lookup("Quit %@", table: "MainMenu", in: swiftUI, english: "Quit %@"), appName)
    // ...and System Settings › General › Software Update's Automatic Updates and Check for Updates,
    // the second with an ellipsis, as it opens a window
    static let automaticUpdates = lookup("Automatic Updates", in: softwareUpdateSettings, english: "Automatic Updates")
    static let checkForUpdates = lookup("Check for Updates", in: softwareUpdateSettings, english: "Check for Updates") + "…"
    
    // The About panel's links: what a link preview calls a source code file, and Maps' Report an Issue
    static let sourceCode = lookup("Source Code (file type)", in: linkPresentation, english: "Source Code")
    static let reportAnIssue = lookup("Report an Issue", in: maps, english: "Report an Issue")
    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Safelight"
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
