import AppKit
import ServiceManagement
import ClaudeSwitchCore

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .module, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var switcher: AccountSwitcher?
    private var usageService: UsageService?
    private var initError: String?
    private var settingsWindow: NSWindow?
    private var launchAtLoginCheckbox: NSButton?
    private var usageCache: [String: String] = [:]
    private var usageNextRefresh = Date.distantPast
    private var isFetchingUsage = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let supportDirectory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ClaudeSwitch")
            let store = try ProfileStore(directory: supportDirectory)
            let keychain = SecurityCLIKeychainClient()
            switcher = AccountSwitcher(
                keychain: keychain,
                config: .standard(),
                store: store
            )
            usageService = UsageService(keychain: keychain, fetcher: AnthropicUsageFetcher())
        } catch {
            initError = error.localizedDescription
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "person.crop.circle.badge.checkmark",
            accessibilityDescription: "Claude Switch"
        )
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        refreshButtonTitle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let initError {
            menu.addItem(disabledItem(title: initError))
            menu.addItem(.separator())
            menu.addItem(quitItem())
            return
        }
        guard let switcher else { return }

        let profiles = switcher.profiles
        let activeName = switcher.activeProfileName()
        menu.addItem(disabledItem(title: L("menu.activeAccount", activeName ?? L("menu.activeAccount.unknown"))))
        menu.addItem(.separator())

        if profiles.isEmpty {
            menu.addItem(disabledItem(title: L("menu.noProfiles")))
        } else {
            for profile in profiles {
                let title = profile.isCaptured
                    ? "\(profile.name)\(profile.email.map { "  (\($0))" } ?? "")"
                    : L("menu.profileNotCaptured", profile.name)
                let isActive = profile.name == activeName
                let item = NSMenuItem(title: title, action: #selector(switchProfile(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = profile.name
                item.isEnabled = profile.isCaptured && !isActive
                item.state = isActive ? .on : .off
                if profile.isCaptured, #available(macOS 14.4, *) {
                    item.subtitle = usageCache[profile.name] ?? L("menu.usage.loading")
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let addItem = NSMenuItem(title: L("menu.addProfile"), action: #selector(addProfile), keyEquivalent: "n")
        addItem.target = self
        menu.addItem(addItem)

        if !profiles.isEmpty {
            menu.addItem(profileSubmenu(title: L("menu.captureInto"), profiles: profiles, action: #selector(captureProfile(_:))))
            menu.addItem(profileSubmenu(title: L("menu.rename"), profiles: profiles, action: #selector(renameProfile(_:))))
            menu.addItem(profileSubmenu(title: L("menu.delete"), profiles: profiles, action: #selector(deleteProfile(_:))))
        }

        if profiles.contains(where: \.isCaptured) {
            let refreshItem = NSMenuItem(title: L("menu.refreshUsage"), action: #selector(refreshUsageNow), keyEquivalent: "r")
            refreshItem.target = self
            menu.addItem(refreshItem)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(quitItem())
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshUsage()
    }

    // MARK: - Usage

    @objc private func refreshUsageNow() {
        // Force an immediate fetch, but never while one is running: repeated clicks
        // would fire a burst of requests and rate-limit the account.
        guard !isFetchingUsage else { return }
        usageNextRefresh = .distantPast
        refreshUsage()
    }

    private struct UsageOutcome {
        let name: String
        let line: String
        let backoffSeconds: TimeInterval?
    }

    private func refreshUsage() {
        guard let switcher, let usageService else { return }
        guard !isFetchingUsage, Date() >= usageNextRefresh else { return }

        let targets: [(name: String, service: String)] = switcher.profiles
            .filter(\.isCaptured)
            .compactMap { profile in
                switcher.usageTokenService(forProfileNamed: profile.name).map { (profile.name, $0) }
            }
        guard targets.isEmpty == false else { return }

        isFetchingUsage = true
        usageNextRefresh = Date().addingTimeInterval(60)

        Task {
            var outcomes: [UsageOutcome] = []
            for target in targets {
                let result = await usageService.usage(tokenService: target.service)
                outcomes.append(Self.outcome(for: result, name: target.name))
            }
            let results = outcomes
            await MainActor.run {
                self.isFetchingUsage = false
                for outcome in results {
                    self.usageCache[outcome.name] = outcome.line
                }
                if let backoff = results.compactMap(\.backoffSeconds).max() {
                    self.usageNextRefresh = Date().addingTimeInterval(backoff)
                }
                if let menu = self.statusItem.menu {
                    self.applyUsageSubtitles(to: menu)
                }
            }
        }
    }

    private static func outcome(for result: Result<UsageSnapshot, Error>, name: String) -> UsageOutcome {
        switch result {
        case .success(let snapshot):
            return UsageOutcome(name: name, line: usageLine(for: snapshot), backoffSeconds: nil)
        case .failure(let error):
            switch error as? SwitchError {
            case .usageTokenExpired, .usageTokenMissing:
                return UsageOutcome(name: name, line: L("menu.usage.expired"), backoffSeconds: nil)
            case .usageRateLimited(let retryAfter):
                return UsageOutcome(name: name, line: L("menu.usage.rateLimited"), backoffSeconds: TimeInterval(retryAfter ?? 300))
            default:
                return UsageOutcome(name: name, line: L("menu.usage.unavailable"), backoffSeconds: nil)
            }
        }
    }

    private static func usageLine(for snapshot: UsageSnapshot) -> String {
        let percent = Int(snapshot.session.utilizationPercent.rounded())
        guard let resetsAt = snapshot.session.resetsAt else {
            return L("menu.usage.noReset", percent)
        }
        let time = DateFormatter.localizedString(from: resetsAt, dateStyle: .none, timeStyle: .short)
        return L("menu.usage", percent, time)
    }

    private func applyUsageSubtitles(to menu: NSMenu) {
        guard #available(macOS 14.4, *) else { return }
        for item in menu.items {
            guard let name = item.representedObject as? String,
                  item.action == #selector(switchProfile(_:)),
                  let line = usageCache[name]
            else { continue }
            item.subtitle = line
        }
    }

    // MARK: - Profiles

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let switcher, let name = sender.representedObject as? String else { return }
        if name == switcher.activeProfileName() { return }
        if claudeIsRunning() && !ask(
            title: L("alert.sessionsRunning.title"),
            message: L("alert.sessionsRunning.message"),
            confirmTitle: L("alert.sessionsRunning.confirm")
        ) {
            return
        }
        guard run({ try switcher.activate(name) }) else { return }
        verifySwitch(to: name)
    }

    // Same check as CCSwitcher after a switch: ask the claude CLI (local read,
    // no network) whether it sees the account we just restored. Catches an
    // unreadable keychain item or a mismatched ~/.claude.json immediately,
    // instead of at the user's next claude command.
    private func verifySwitch(to name: String) {
        guard let switcher else { return }
        let expectedEmail = switcher.profiles.first { $0.name == name }?.email
        let verifier = ClaudeAuthVerifier(cli: ClaudeCLIProcessRunner())
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = verifier.verify(expectedEmail: expectedEmail)
            DispatchQueue.main.async {
                switch result {
                case .verified:
                    break
                case .unavailable:
                    NSLog("ClaudeSwitch: claude CLI unavailable, switch to %@ not verified", name)
                case .notLoggedIn:
                    self?.showError(L("alert.verify.notLoggedIn", name))
                case .wrongAccount(let expected, let actual):
                    self?.showError(L("alert.verify.wrongAccount", expected, actual, name))
                }
            }
        }
    }

    @objc private func addProfile() {
        guard let switcher else { return }
        guard let name = promptForName(title: L("alert.newProfileName")) else { return }
        let added = run { try switcher.addProfile(named: name) }
        guard added else { return }
        if ask(
            title: L("alert.profileCreated.title", name),
            message: L("alert.profileCreated.message"),
            confirmTitle: L("alert.profileCreated.confirm"),
            cancelTitle: L("alert.profileCreated.later")
        ) {
            run { try switcher.captureActiveAccount(into: name) }
        }
    }

    @objc private func captureProfile(_ sender: NSMenuItem) {
        guard let switcher, let name = sender.representedObject as? String else { return }
        run { try switcher.captureActiveAccount(into: name) }
    }

    @objc private func renameProfile(_ sender: NSMenuItem) {
        guard let switcher, let name = sender.representedObject as? String else { return }
        guard let newName = promptForName(title: L("alert.renameProfile", name), initial: name) else { return }
        run { try switcher.renameProfile(name, to: newName) }
    }

    @objc private func deleteProfile(_ sender: NSMenuItem) {
        guard let switcher, let name = sender.representedObject as? String else { return }
        guard ask(
            title: L("alert.deleteProfile.title", name),
            message: L("alert.deleteProfile.message"),
            confirmTitle: L("alert.deleteProfile.confirm")
        ) else { return }
        run { try switcher.deleteProfile(name) }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        launchAtLoginCheckbox?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let checkbox = NSButton(
            checkboxWithTitle: L("settings.launchAtLogin"),
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        checkbox.sizeToFit()
        checkbox.setFrameOrigin(NSPoint(x: 20, y: 48))
        launchAtLoginCheckbox = checkbox

        let versionLabel = NSTextField(labelWithString: L("settings.version", Self.appVersion))
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.sizeToFit()
        versionLabel.setFrameOrigin(NSPoint(x: 20, y: 16))

        let contentSize = NSSize(
            width: max(320, checkbox.frame.maxX + 20, versionLabel.frame.maxX + 20),
            height: checkbox.frame.maxY + 20
        )
        let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
        content.addSubview(checkbox)
        content.addSubview(versionLabel)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L("settings.title")
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = sender.state == .on ? .off : .on
            showError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            refreshButtonTitle()
            // A switch or capture changes which token backs each profile; drop the
            // cached usage so the next menu open refetches instead of showing stale %.
            usageCache.removeAll()
            usageNextRefresh = .distantPast
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func refreshButtonTitle() {
        let name = switcher?.activeProfileName()
        statusItem.button?.title = name.map { " \($0)" } ?? ""
    }

    private func claudeIsRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func promptForName(title: String, initial: String = "") -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: L("alert.ok"))
        alert.addButton(withTitle: L("alert.cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func ask(title: String, message: String, confirmTitle: String, cancelTitle: String? = nil) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: cancelTitle ?? L("alert.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Claude Switch"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func profileSubmenu(title: String, profiles: [Profile], action: Selector) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for profile in profiles {
            let item = NSMenuItem(title: profile.name, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = profile.name
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func disabledItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.target = NSApp
        return item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
