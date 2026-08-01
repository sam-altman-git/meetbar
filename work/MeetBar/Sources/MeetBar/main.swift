import AppKit
import Foundation
import Network

struct MeetState: Equatable {
    var inCall: Bool
    var muted: Bool?
    var cameraOff: Bool?
    var browser: String?
    var title: String?
    var message: String?
}

struct ScriptResult {
    var value: String?
    var error: String?
}

enum MeetAction: String {
    case toggleMic = "toggleMic"
    case toggleCamera = "toggleCamera"
    case leave = "leave"
    case bringToFront = "bringToFront"
}

enum ExpandTrigger: String, CaseIterable {
    case none = "NONE"
    case hover = "HOVER"
    case click = "CLICK"
}

enum ExpandType: String, CaseIterable {
    case popover = "POPOVER"
    case strip = "STRIP"
}

enum ExpandOption: String, CaseIterable {
    case endCall = "End Call"
    case cameraToggle = "Camera Toggle"
    case micToggle = "Mic Toggle"
    case bringToFront = "Bring to Front"
}

final class AppSettings {
    private enum Key {
        static let trigger = "expandTrigger"
        static let type = "expandType"
        static let optionEndCall = "optionEndCall"
        static let optionCameraToggle = "optionCameraToggle"
        static let optionMicToggle = "optionMicToggle"
        static let optionBringToFront = "optionBringToFront"
        static let hoverOpenDelayMs = "hoverOpenDelayMs"
        static let hoverCloseDelayMs = "hoverCloseDelayMs"
    }

    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.trigger: ExpandTrigger.none.rawValue,
            Key.type: ExpandType.popover.rawValue,
            Key.optionEndCall: true,
            Key.optionCameraToggle: true,
            Key.optionMicToggle: true,
            Key.optionBringToFront: true,
            Key.hoverOpenDelayMs: 250,
            Key.hoverCloseDelayMs: 300
        ])
    }

    var trigger: ExpandTrigger {
        get { ExpandTrigger(rawValue: defaults.string(forKey: Key.trigger) ?? "") ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Key.trigger) }
    }

    var type: ExpandType {
        get { ExpandType(rawValue: defaults.string(forKey: Key.type) ?? "") ?? .popover }
        set { defaults.set(newValue.rawValue, forKey: Key.type) }
    }

    var hoverOpenDelayMs: Int {
        get { clampedDelay(defaults.integer(forKey: Key.hoverOpenDelayMs), fallback: 250) }
        set { defaults.set(clampedDelay(newValue, fallback: 250), forKey: Key.hoverOpenDelayMs) }
    }

    var hoverCloseDelayMs: Int {
        get { clampedDelay(defaults.integer(forKey: Key.hoverCloseDelayMs), fallback: 300) }
        set { defaults.set(clampedDelay(newValue, fallback: 300), forKey: Key.hoverCloseDelayMs) }
    }

    func isEnabled(_ option: ExpandOption) -> Bool {
        defaults.bool(forKey: key(for: option))
    }

    func setEnabled(_ enabled: Bool, for option: ExpandOption) {
        defaults.set(enabled, forKey: key(for: option))
    }

    private func key(for option: ExpandOption) -> String {
        switch option {
        case .endCall:
            return Key.optionEndCall
        case .cameraToggle:
            return Key.optionCameraToggle
        case .micToggle:
            return Key.optionMicToggle
        case .bringToFront:
            return Key.optionBringToFront
        }
    }

    private func clampedDelay(_ value: Int, fallback: Int) -> Int {
        if value <= 0 { return fallback }
        return min(max(value, 0), 5000)
    }
}

final class SettingsWindowController: NSWindowController {
    private let settings = AppSettings.shared
    private let triggerPopup = NSPopUpButton()
    private let typePopup = NSPopUpButton()
    private let hoverOpenDelayField = NSTextField()
    private let hoverCloseDelayField = NSTextField()
    private let hoverOpenDelayStepper = NSStepper()
    private let hoverCloseDelayStepper = NSStepper()
    private var optionChecks: [ExpandOption: NSButton] = [:]

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 390, height: 320))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MeetBar Settings"
        window.contentView = contentView
        window.center()
        super.init(window: window)
        buildContent(in: contentView)
        syncControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent(in contentView: NSView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20)
        ])

        stack.addArrangedSubview(row(label: "Expand options trigger", control: triggerPopup))
        triggerPopup.addItems(withTitles: ExpandTrigger.allCases.map(\.rawValue))
        triggerPopup.target = self
        triggerPopup.action = #selector(triggerChanged)

        stack.addArrangedSubview(row(label: "Expand options type", control: typePopup))
        typePopup.addItems(withTitles: ExpandType.allCases.map(\.rawValue))
        typePopup.target = self
        typePopup.action = #selector(typeChanged)

        configureDelayField(hoverOpenDelayField, stepper: hoverOpenDelayStepper)
        stack.addArrangedSubview(row(label: "Hover open delay (ms)", control: delayControl(field: hoverOpenDelayField, stepper: hoverOpenDelayStepper)))

        configureDelayField(hoverCloseDelayField, stepper: hoverCloseDelayStepper)
        stack.addArrangedSubview(row(label: "Hover close delay (ms)", control: delayControl(field: hoverCloseDelayField, stepper: hoverCloseDelayStepper)))

        let optionsLabel = NSTextField(labelWithString: "Visible expand options")
        optionsLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        stack.addArrangedSubview(optionsLabel)

        for option in ExpandOption.allCases {
            let checkbox = NSButton(checkboxWithTitle: option.rawValue, target: self, action: #selector(optionChanged(_:)))
            checkbox.identifier = NSUserInterfaceItemIdentifier(option.rawValue)
            optionChecks[option] = checkbox
            stack.addArrangedSubview(checkbox)
        }
    }

    private func row(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.widthAnchor.constraint(equalToConstant: 175).isActive = true
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func configureDelayField(_ field: NSTextField, stepper: NSStepper) {
        field.formatter = integerFormatter()
        field.target = self
        field.action = #selector(delayChanged(_:))
        field.delegate = self
        stepper.minValue = 0
        stepper.maxValue = 5000
        stepper.increment = 50
        stepper.target = self
        stepper.action = #selector(delayStepperChanged(_:))
    }

    private func delayControl(field: NSTextField, stepper: NSStepper) -> NSView {
        field.widthAnchor.constraint(equalToConstant: 84).isActive = true
        stepper.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let stack = NSStackView(views: [field, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func integerFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 5000
        formatter.allowsFloats = false
        return formatter
    }

    private func syncControls() {
        triggerPopup.selectItem(withTitle: settings.trigger.rawValue)
        typePopup.selectItem(withTitle: settings.type.rawValue)
        hoverOpenDelayField.integerValue = settings.hoverOpenDelayMs
        hoverCloseDelayField.integerValue = settings.hoverCloseDelayMs
        hoverOpenDelayStepper.integerValue = settings.hoverOpenDelayMs
        hoverCloseDelayStepper.integerValue = settings.hoverCloseDelayMs
        for option in ExpandOption.allCases {
            optionChecks[option]?.state = settings.isEnabled(option) ? .on : .off
        }
        updateEnabledState()
    }

    private func updateEnabledState() {
        let enabled = settings.trigger != .none
        let hoverEnabled = settings.trigger == .hover
        typePopup.isEnabled = enabled
        hoverOpenDelayField.isEnabled = hoverEnabled
        hoverCloseDelayField.isEnabled = hoverEnabled
        hoverOpenDelayStepper.isEnabled = hoverEnabled
        hoverCloseDelayStepper.isEnabled = hoverEnabled
        for checkbox in optionChecks.values {
            checkbox.isEnabled = enabled
        }
    }

    @objc private func triggerChanged() {
        settings.trigger = ExpandTrigger(rawValue: triggerPopup.titleOfSelectedItem ?? "") ?? .none
        updateEnabledState()
    }

    @objc private func typeChanged() {
        settings.type = ExpandType(rawValue: typePopup.titleOfSelectedItem ?? "") ?? .popover
    }

    @objc private func optionChanged(_ sender: NSButton) {
        guard let rawValue = sender.identifier?.rawValue,
              let option = ExpandOption(rawValue: rawValue) else { return }
        settings.setEnabled(sender.state == .on, for: option)
    }

    @objc private func delayChanged(_ sender: NSTextField) {
        if sender === hoverOpenDelayField {
            settings.hoverOpenDelayMs = sender.integerValue
            hoverOpenDelayField.integerValue = settings.hoverOpenDelayMs
            hoverOpenDelayStepper.integerValue = settings.hoverOpenDelayMs
        } else if sender === hoverCloseDelayField {
            settings.hoverCloseDelayMs = sender.integerValue
            hoverCloseDelayField.integerValue = settings.hoverCloseDelayMs
            hoverCloseDelayStepper.integerValue = settings.hoverCloseDelayMs
        }
    }

    @objc private func delayStepperChanged(_ sender: NSStepper) {
        if sender === hoverOpenDelayStepper {
            settings.hoverOpenDelayMs = sender.integerValue
            hoverOpenDelayField.integerValue = settings.hoverOpenDelayMs
            hoverOpenDelayStepper.integerValue = settings.hoverOpenDelayMs
        } else if sender === hoverCloseDelayStepper {
            settings.hoverCloseDelayMs = sender.integerValue
            hoverCloseDelayField.integerValue = settings.hoverCloseDelayMs
            hoverCloseDelayStepper.integerValue = settings.hoverCloseDelayMs
        }
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        delayChanged(field)
    }
}

final class LocalMeetBridge {
    private let queue = DispatchQueue(label: "local.meetbar.bridge")
    private var listener: NWListener?
    private var state = MeetState(inCall: false, muted: nil, cameraOff: nil, browser: "Chrome extension", title: nil, message: "Waiting for MeetBar Chrome extension")
    private var commandId = 0
    private var pendingAction: String?

    var lastMessage = "Bridge starting"

    func start() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: 17654)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener?.start(queue: queue)
            lastMessage = "Bridge listening on 127.0.0.1:17654"
        } catch {
            lastMessage = "Bridge failed: \(error.localizedDescription)"
        }
    }

    func currentState() -> MeetState {
        queue.sync { state }
    }

    func send(_ action: MeetAction) -> String {
        queue.sync {
            commandId += 1
            switch action {
            case .toggleMic:
                pendingAction = "toggleMute"
            case .toggleCamera:
                pendingAction = "toggleCamera"
            case .leave:
                pendingAction = "leave"
            case .bringToFront:
                pendingAction = "bringToFront"
            }
            lastMessage = "Queued \(pendingAction ?? "command") for extension"
            return lastMessage
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let response = self.response(for: request)
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: String) -> String {
        if request.hasPrefix("OPTIONS ") {
            return httpResponse("{}")
        }

        if request.hasPrefix("POST /state ") {
            if let body = request.components(separatedBy: "\r\n\r\n").last,
               let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let inCall = json["inCall"] as? Bool ?? false
                let muted = json["muted"] as? Bool
                let cameraOff = json["cameraOff"] as? Bool
                let title = json["title"] as? String
                state = MeetState(inCall: inCall, muted: muted, cameraOff: cameraOff, browser: "Chrome extension", title: title, message: nil)
                lastMessage = inCall ? "Extension reports active Meet tab" : "Extension connected; no active call"
            }
            return httpResponse("{\"ok\":true}")
        }

        if request.hasPrefix("GET /command") {
            let body: String
            if let pendingAction {
                body = "{\"id\":\(commandId),\"action\":\"\(pendingAction)\"}"
                self.pendingAction = nil
            } else {
                body = "{\"id\":\(commandId),\"action\":null}"
            }
            return httpResponse(body)
        }

        if request.hasPrefix("GET /health") {
            return httpResponse("{\"ok\":true,\"message\":\"\(jsonEscape(lastMessage))\"}")
        }

        return httpResponse("{\"error\":\"not found\"}", status: "404 Not Found")
    }

    private func httpResponse(_ body: String, status: String = "200 OK") -> String {
        """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
    }

    private func jsonEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

final class BrowserController {
    private let browsers = ["Google Chrome", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi"]
    private(set) var lastMessage = "Starting up"

    func currentState() -> MeetState {
        var sawRunningBrowser = false
        for browser in browsers {
            guard isRunning(browser) else { continue }
            sawRunningBrowser = true
            let script = detectionScript(for: browser)
            let result = runAppleScript(script)
            if let error = result.error {
                lastMessage = "\(browser): \(error)"
                continue
            }
            guard let output = result.value, !output.isEmpty else { continue }
            if let state = parseState(output, browser: browser) {
                lastMessage = "Connected to \(browser)"
                return state
            }
        }
        if !sawRunningBrowser {
            lastMessage = "Open Chrome, Edge, Brave, Arc, or Vivaldi."
        }
        return MeetState(inCall: false, muted: nil, cameraOff: nil, browser: nil, title: nil, message: "No active Google Meet call")
    }

    func perform(_ action: MeetAction) -> String {
        for browser in browsers {
            guard isRunning(browser) else { continue }
            let script = actionScript(for: browser, action: action)
            let result = runAppleScript(script)
            if let error = result.error {
                lastMessage = "\(browser): \(error)"
                return lastMessage
            }
            if let output = result.value, !output.isEmpty {
                lastMessage = output
                return output
            }
        }
        lastMessage = "No controllable Google Meet tab found."
        return "No controllable Google Meet tab found."
    }

    func testChromePermission() -> String {
        let browser = "Google Chrome"
        guard isRunning(browser) else {
            lastMessage = "Google Chrome is not running."
            return lastMessage
        }

        let script = """
        tell application "\(browser)"
          set tabCount to 0
          repeat with w in windows
            set tabCount to tabCount + (count of tabs of w)
          end repeat
          return "Chrome automation OK. Tabs visible: " & tabCount
        end tell
        """
        let result = runAppleScript(script)
        if let error = result.error {
            lastMessage = "Chrome test failed: \(error)"
            return lastMessage
        }
        lastMessage = result.value ?? "Chrome automation OK."
        return lastMessage
    }

    private func isRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == appName }
    }

    private func runAppleScript(_ source: String) -> ScriptResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return ScriptResult(value: nil, error: "Could not create AppleScript.")
        }
        let descriptor = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
            NSLog("MeetBar AppleScript error: %@", message)
            return ScriptResult(value: nil, error: message)
        }
        return ScriptResult(value: descriptor.stringValue, error: nil)
    }

    private func parseState(_ output: String, browser: String) -> MeetState? {
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 2, parts[0] == "MEET" else { return nil }
        return MeetState(
            inCall: true,
            muted: nil,
            cameraOff: nil,
            browser: browser,
            title: parts[1],
            message: nil
        )
    }

    private func escapedForAppleScript(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func detectionScript(for browser: String) -> String {
        return """
        tell application "\(browser)"
          repeat with w in windows
            repeat with t in tabs of w
              set tabUrl to URL of t
              if tabUrl starts with "https://meet.google.com/" then
                return "MEET||" & (title of t)
              end if
            end repeat
          end repeat
        end tell
        return ""
        """
    }

    private func actionScript(for browser: String, action: MeetAction) -> String {
        let actionBody: String
        if action == .toggleMic {
            actionBody = """
                    tell application "\(browser)" to activate
                    delay 0.1
                    tell application "System Events" to keystroke "d" using command down
                    return "Sent Google Meet mute shortcut."
            """
        } else {
            actionBody = """
                    close t
                    return "Closed Google Meet tab."
            """
        }
        return """
        tell application "\(browser)"
          repeat with wIndex from 1 to count of windows
            set w to window wIndex
            repeat with tIndex from 1 to count of tabs of w
              set t to tab tIndex of w
              set tabUrl to URL of t
              if tabUrl starts with "https://meet.google.com/" then
                set active tab index of w to tIndex
                set index of w to 1
        \(actionBody)
              end if
            end repeat
          end repeat
        end tell
        return "No Google Meet tab found."
        """
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let bridge = LocalMeetBridge()
    private let settings = AppSettings.shared
    private var timer: Timer?
    private var state = MeetState(inCall: false, muted: nil, cameraOff: nil, browser: nil, title: nil, message: nil)
    private var expandPopover: NSPopover?
    private var settingsWindowController: SettingsWindowController?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var isHoveringStatusItem = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var hoverPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        bridge.start()
        configureStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        hoverPollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.handleMouseMoved(at: NSEvent.mouseLocation)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = menuBarIcon(inCall: false, muted: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp])
        installMouseMonitors()
    }

    @objc private func refresh() {
        let previousState = state
        state = bridge.currentState()
        DispatchQueue.main.async {
            self.updateIcon()
            if self.expandPopover != nil, previousState != self.state {
                self.rebuildExpandedOptions()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = menuBarIcon(inCall: state.inCall, muted: state.muted)
        button.toolTip = state.inCall ? "Google Meet active" : "No active Google Meet call"
    }

    private func menuBarIcon(inCall: Bool, muted: Bool?) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        let background: NSColor
        let symbolName: String
        if inCall, muted == false {
            background = NSColor(red: 0.12, green: 0.68, blue: 0.35, alpha: 1.0)
            symbolName = "mic.fill"
        } else if inCall, muted == true {
            background = NSColor(red: 0.90, green: 0.18, blue: 0.20, alpha: 1.0)
            symbolName = "mic.slash.fill"
        } else {
            background = NSColor(red: 0.36, green: 0.38, blue: 0.42, alpha: 1.0)
            symbolName = "mic.slash.fill"
        }

        background.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()

        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let symbolSize = symbol.size
            let rect = NSRect(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            NSColor.white.set()
            symbol.draw(in: rect, from: .zero, operation: .sourceAtop, fraction: 1.0)
        }
        return image
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            showMenu()
            return
        }

        if event.modifierFlags.contains(.control) {
            showMenu()
            return
        }

        if settings.trigger == .click {
            showExpandedOptions()
        } else if state.inCall {
            toggleMic()
        } else {
            showMenu()
        }
    }

    private func installMouseMonitors() {
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if self?.shouldOpenContextMenu(for: event) == true {
                self?.showMenu(with: event)
                return nil
            }

            if event.type == .mouseMoved {
                self?.handleMouseMoved(at: NSEvent.mouseLocation)
            } else {
                self?.closeExpandedOptionsIfClickIsOutside(NSEvent.mouseLocation)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if event.type == .mouseMoved {
                self?.handleMouseMoved(at: NSEvent.mouseLocation)
            } else {
                self?.closeExpandedOptionsIfClickIsOutside(NSEvent.mouseLocation)
            }
        }
    }

    private func shouldOpenContextMenu(for event: NSEvent) -> Bool {
        let isContextClick = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isContextClick else { return false }
        return statusItemScreenRect()?.contains(NSEvent.mouseLocation) == true
    }

    private func handleMouseMoved(at screenPoint: NSPoint) {
        guard settings.trigger == .hover else {
            isHoveringStatusItem = false
            hoverOpenWorkItem?.cancel()
            hoverCloseWorkItem?.cancel()
            return
        }

        let isInside = isPointInsideHoverRegion(screenPoint)
        guard isInside != isHoveringStatusItem else { return }
        isHoveringStatusItem = isInside

        if isInside {
            hoverOpenWorkItem?.cancel()
            hoverCloseWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.showExpandedOptions()
            }
            hoverOpenWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delayInterval(settings.hoverOpenDelayMs), execute: workItem)
        } else {
            hoverOpenWorkItem?.cancel()
            hoverCloseWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.closeExpandedOptions()
            }
            hoverCloseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delayInterval(settings.hoverCloseDelayMs), execute: workItem)
        }
    }

    private func delayInterval(_ milliseconds: Int) -> TimeInterval {
        TimeInterval(milliseconds) / 1000.0
    }

    private func statusItemScreenRect() -> NSRect? {
        guard let button = statusItem.button,
              let window = button.window else { return nil }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow).insetBy(dx: -8, dy: -8)
    }

    private func isPointInsideHoverRegion(_ screenPoint: NSPoint) -> Bool {
        if statusItemScreenRect()?.contains(screenPoint) == true {
            return true
        }

        guard let popoverWindow = expandPopover?.contentViewController?.view.window else {
            return false
        }
        return popoverWindow.frame.insetBy(dx: -8, dy: -8).contains(screenPoint)
    }

    private func closeExpandedOptionsIfClickIsOutside(_ screenPoint: NSPoint) {
        guard expandPopover != nil else { return }
        guard !isPointInsideHoverRegion(screenPoint) else { return }
        hoverOpenWorkItem?.cancel()
        hoverCloseWorkItem?.cancel()
        isHoveringStatusItem = false
        closeExpandedOptions()
    }

    private func showMenu(with event: NSEvent? = nil) {
        closeExpandedOptions()
        guard let button = statusItem.button else { return }
        let menu = buildMenu()
        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    private func showExpandedOptions() {
        guard settings.trigger != .none else { return }
        guard let button = statusItem.button else { return }
        closeExpandedOptions()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = expandedOptionsViewController()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        expandPopover = popover
    }

    private func rebuildExpandedOptions() {
        guard expandPopover != nil else { return }
        showExpandedOptions()
    }

    private func closeExpandedOptions() {
        expandPopover?.performClose(nil)
        expandPopover = nil
    }

    private func expandedOptionsViewController() -> NSViewController {
        let controller = NSViewController()
        let stack = NSStackView()
        stack.orientation = settings.type == .strip ? .horizontal : .vertical
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let enabledOptions = ExpandOption.allCases.filter { settings.isEnabled($0) }
        if enabledOptions.isEmpty {
            stack.addArrangedSubview(NSTextField(labelWithString: "No controls selected"))
        } else {
            for option in enabledOptions {
                stack.addArrangedSubview(expandedButton(for: option))
            }
        }

        controller.view = stack
        return controller
    }

    private func expandedButton(for option: ExpandOption) -> NSButton {
        let button = NSButton(title: title(for: option), target: self, action: selector(for: option))
        button.bezelStyle = .rounded
        button.image = NSImage(systemSymbolName: symbolName(for: option), accessibilityDescription: option.rawValue)
        button.imagePosition = settings.type == .strip ? .imageOnly : .imageLeft
        button.toolTip = title(for: option)
        button.isEnabled = state.inCall
        if settings.type == .strip {
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        return button
    }

    private func title(for option: ExpandOption) -> String {
        switch option {
        case .endCall:
            return "End Call"
        case .cameraToggle:
            return state.cameraOff == true ? "Turn Camera On" : "Turn Camera Off"
        case .micToggle:
            return state.muted == true ? "Unmute" : "Mute"
        case .bringToFront:
            return "Bring to Front"
        }
    }

    private func symbolName(for option: ExpandOption) -> String {
        switch option {
        case .endCall:
            return "phone.down.fill"
        case .cameraToggle:
            return state.cameraOff == true ? "video.fill" : "video.slash.fill"
        case .micToggle:
            return state.muted == true ? "mic.fill" : "mic.slash.fill"
        case .bringToFront:
            return "rectangle.on.rectangle"
        }
    }

    private func selector(for option: ExpandOption) -> Selector {
        switch option {
        case .endCall:
            return #selector(endCall)
        case .cameraToggle:
            return #selector(toggleCamera)
        case .micToggle:
            return #selector(toggleMic)
        case .bringToFront:
            return #selector(bringMeetToFront)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let statusTitle: String
        if state.inCall {
            let mic = state.muted == true ? "Muted" : state.muted == false ? "Live" : "Mic unknown"
            let camera = state.cameraOff == true ? "Camera off" : state.cameraOff == false ? "Camera on" : "Camera unknown"
            statusTitle = "\(mic), \(camera) in \(state.browser ?? "browser")"
        } else {
            statusTitle = "No active Google Meet call"
        }

        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let detail = NSMenuItem(title: bridge.lastMessage, action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)

        if let title = state.title, state.inCall {
            let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let test = NSMenuItem(title: "Show Bridge Status", action: #selector(showBridgeStatus), keyEquivalent: "")
        test.target = self
        menu.addItem(test)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let quit = NSMenuItem(title: "Quit MeetBar", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func toggleMic() {
        closeExpandedOptions()
        _ = bridge.send(.toggleMic)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    @objc private func toggleCamera() {
        closeExpandedOptions()
        _ = bridge.send(.toggleCamera)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    @objc private func bringMeetToFront() {
        closeExpandedOptions()
        _ = bridge.send(.bringToFront)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    @objc private func endCall() {
        closeExpandedOptions()
        _ = bridge.send(.leave)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showBridgeStatus() {
        showAlert(title: "MeetBar Bridge", message: bridge.lastMessage)
        refresh()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
