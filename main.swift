import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var process: Process?
    private var endDate: Date?
    private var stepIndex: Int?
    private var tickTimer: Timer?

    private let defaults = UserDefaults.standard
    private var preventDisplaySleep: Bool {
        get { defaults.object(forKey: "preventDisplaySleep") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "preventDisplaySleep") }
    }

    // Left-click steps through these in order; one more click past the last turns it off.
    private let steps: [(title: String, seconds: Int?)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 60 * 60),
        ("2 hours", 2 * 60 * 60),
        ("4 hours", 4 * 60 * 60),
        ("8 hours", 8 * 60 * 60),
        ("Indefinitely", nil),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()

        // Optional: `--start` (indefinite) or `--start <minutes>` to begin immediately.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--start") {
            let minutes = args.indices.contains(i + 1) ? Int(args[i + 1]) : nil
            start(seconds: minutes.map { $0 * 60 })
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    private var isActive: Bool { process?.isRunning == true }

    // Left-click advances to the next timeout step; right-click (or ctrl-click) shows the menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = buildMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            advanceStep()
        }
    }

    private func advanceStep() {
        let next = isActive ? (stepIndex ?? -1) + 1 : 0
        if next >= steps.count {
            stop()
        } else {
            start(step: next)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if isActive {
            menu.addItem(item("Turn Off", #selector(turnOff), key: "o"))
            menu.addItem(.separator())
        }

        let header = NSMenuItem(title: "Keep Awake for…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (index, step) in steps.enumerated() {
            let mi = item(step.title, #selector(startStep(_:)))
            mi.tag = index
            mi.indentationLevel = 1
            mi.state = isActive && stepIndex == index ? .on : .off
            menu.addItem(mi)
        }

        menu.addItem(.separator())
        let display = item("Keep Display Awake", #selector(toggleDisplay))
        display.state = preventDisplaySleep ? .on : .off
        menu.addItem(display)

        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Quit Caffeinator", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func startStep(_ sender: NSMenuItem) { start(step: sender.tag) }

    @objc private func turnOff() { stop() }

    @objc private func toggleDisplay() {
        preventDisplaySleep.toggle()
        if isActive {
            let remaining = endDate.map { max(1, Int($0.timeIntervalSinceNow)) }
            let step = stepIndex
            start(seconds: remaining)
            stepIndex = step
            refresh()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func start(step: Int) {
        start(seconds: steps[step].seconds)
        stepIndex = step
        refresh()
    }

    private func start(seconds: Int?) {
        stop()

        // -i prevents idle sleep; -d also keeps the display on; -w ties caffeinate to this app's lifetime.
        var args = ["-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if preventDisplaySleep { args.append("-d") }
        if let seconds { args += ["-t", String(seconds)] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = args
        p.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                self.clearState()
                self.refresh()
            }
        }
        do {
            try p.run()
            process = p
            endDate = seconds.map { Date().addingTimeInterval(TimeInterval($0)) }
            stepIndex = steps.firstIndex { $0.seconds == seconds }
        } catch {
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    private func stop() {
        let p = process
        clearState()
        if let p, p.isRunning { p.terminate() }
        refresh()
    }

    private func clearState() {
        process = nil
        endDate = nil
        stepIndex = nil
    }

    private func statusText() -> String {
        guard isActive else { return "Caffeinate: Off" }
        guard let endDate else { return "Caffeinate: On (indefinitely)" }
        return "Caffeinate: On – \(format(endDate.timeIntervalSinceNow)) left"
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // Short menu bar label: "45s", "59m", "1h05", "8h".
    private func compactFormat(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
    }

    private func makeIcon() -> NSImage {
        let cupName = isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let cup = NSImage(systemSymbolName: cupName, accessibilityDescription: "Caffeinator")?
            .withSymbolConfiguration(config) ?? NSImage()
        cup.isTemplate = true
        return cup
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.image = makeIcon()
        button.imagePosition = .imageLeading
        if isActive {
            let text = endDate.map { compactFormat($0.timeIntervalSinceNow) } ?? "∞"
            button.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .baselineOffset: 0.5,
            ])
        } else {
            button.title = ""
        }
        let next: String
        if !isActive { next = steps[0].title }
        else if let i = stepIndex, i + 1 < steps.count { next = steps[i + 1].title }
        else { next = "Off" }
        button.toolTip = statusText() + "\nClick: \(next) · Right-click for options"
    }

    private func refresh() {
        tickTimer?.invalidate()
        tickTimer = nil
        updateButton()

        if isActive, endDate != nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.updateButton()
            }
            RunLoop.main.add(timer, forMode: .common)
            tickTimer = timer
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
