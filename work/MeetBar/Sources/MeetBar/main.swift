import AppKit
import Foundation
import Network

struct MeetState {
    var inCall: Bool
    var muted: Bool?
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
    case leave = "leave"
}

final class LocalMeetBridge {
    private let queue = DispatchQueue(label: "local.meetbar.bridge")
    private var listener: NWListener?
    private var state = MeetState(inCall: false, muted: nil, browser: "Chrome extension", title: nil, message: "Waiting for MeetBar Chrome extension")
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
            pendingAction = action == .toggleMic ? "toggleMute" : "leave"
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
                let title = json["title"] as? String
                state = MeetState(inCall: inCall, muted: muted, browser: "Chrome extension", title: title, message: nil)
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
        return MeetState(inCall: false, muted: nil, browser: nil, title: nil, message: "No active Google Meet call")
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
    private var timer: Timer?
    private var state = MeetState(inCall: false, muted: nil, browser: nil, title: nil, message: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        bridge.start()
        configureStatusItem()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = menuBarIcon(inCall: false, muted: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func refresh() {
        state = bridge.currentState()
        DispatchQueue.main.async {
            self.updateIcon()
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

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }

        if state.inCall {
            toggleMic()
        } else {
            showMenu()
        }
    }

    private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let statusTitle: String
        if state.inCall {
            let mic = state.muted == true ? "Muted" : state.muted == false ? "Live" : "Mic unknown"
            statusTitle = "\(mic) in \(state.browser ?? "browser")"
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

        let muteTitle = state.muted == true ? "Unmute Microphone" : "Mute Microphone"
        let mute = NSMenuItem(title: muteTitle, action: #selector(toggleMic), keyEquivalent: "")
        mute.target = self
        mute.isEnabled = state.inCall
        menu.addItem(mute)

        let leave = NSMenuItem(title: "End Call", action: #selector(endCall), keyEquivalent: "")
        leave.target = self
        leave.isEnabled = state.inCall
        menu.addItem(leave)

        menu.addItem(.separator())

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
        _ = bridge.send(.toggleMic)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
    }

    @objc private func endCall() {
        _ = bridge.send(.leave)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.refresh() }
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
