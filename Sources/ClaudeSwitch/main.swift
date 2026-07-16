import AppKit
import SwiftUI
import ServiceManagement
import ClaudeSwitchCore

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, bundle: .module, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let panelModel = PanelModel()
    private var switcher: AccountSwitcher?
    private var usageService: UsageService?
    private var initError: String?
    private var settingsController: SettingsWindowController?
    private var launchAtLoginCheckbox: NSButton?
    private var modulesListController: MenuBarModulesListController?
    private var sessionPercentCache: [String: Int] = [:]
    private var sessionResetCache: [String: Date] = [:]
    private var weeklyPercentCache: [String: Int] = [:]
    private var weeklyResetCache: [String: Date] = [:]
    private var usageErrorCache: [String: String] = [:]
    private var usageStaleCache: [String: String] = [:]
    private var usageNextRefresh = Date.distantPast
    private var isFetchingUsage = false
    private var menuBarUsageTimer: Timer?

    private static let showSessionUsageKey = "menuBar.showSessionUsage"
    private static let showSessionResetKey = "menuBar.showSessionReset"
    private static let moduleOrderKey = "menuBar.moduleOrder"
    private static let moduleKeys = [showSessionUsageKey, showSessionResetKey]

    private var showSessionUsageInMenuBar: Bool {
        UserDefaults.standard.bool(forKey: Self.showSessionUsageKey)
    }

    private var showSessionResetInMenuBar: Bool {
        UserDefaults.standard.bool(forKey: Self.showSessionResetKey)
    }

    private var menuBarModulesEnabled: Bool {
        showSessionUsageInMenuBar || showSessionResetInMenuBar
    }

    private var orderedModuleKeys: [String] {
        MenuBarModuleOrder.resolve(
            saved: UserDefaults.standard.stringArray(forKey: Self.moduleOrderKey) ?? [],
            known: Self.moduleKeys
        )
    }

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
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let hosting = NSHostingController(rootView: PanelView(model: panelModel, actions: panelActions()))
        hosting.sizingOptions = .preferredContentSize
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting

        panelModel.initError = initError
        syncModel()
        refreshButtonTitle()
        applyMenuBarModules()
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if popover.isShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        syncModel()
        refreshUsage()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePanel() {
        popover.performClose(nil)
    }

    private func panelActions() -> PanelActions {
        PanelActions(
            switchTo: { [weak self] name in self?.switchProfile(named: name) },
            capture: { [weak self] name in self?.captureProfile(named: name) },
            edit: { [weak self] name in self?.editProfile(named: name) },
            delete: { [weak self] name in self?.deleteProfile(named: name) },
            addProfile: { [weak self] in self?.addProfile() },
            refresh: { [weak self] in self?.refreshUsageNow() },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) }
        )
    }

    // Rows are ordered here, once: active profile first, the rest in store order.
    // Every page renders model.rows as-is, so all tabs share the same order.
    private func syncModel() {
        guard let switcher else { return }
        let activeName = switcher.activeProfileName()
        let profiles = switcher.profiles.filter { $0.name == activeName }
            + switcher.profiles.filter { $0.name != activeName }
        panelModel.rows = profiles.map { profile in
            ProfileRow(
                id: profile.id,
                name: profile.name,
                email: profile.email,
                colorHex: profile.colorHex,
                isActive: profile.name == activeName,
                isCaptured: profile.isCaptured,
                usage: usageDisplay(for: profile)
            )
        }
    }

    private func usageDisplay(for profile: Profile) -> UsageDisplay {
        guard profile.isCaptured else { return .notCaptured }
        if let message = usageErrorCache[profile.name] {
            return .unavailable(message)
        }
        guard let percent = sessionPercentCache[profile.name] else { return .loading }
        let session = WindowDisplay(percent: percent, resetsAt: sessionResetCache[profile.name])
        let weekly = weeklyPercentCache[profile.name].map {
            WindowDisplay(percent: $0, resetsAt: weeklyResetCache[profile.name])
        }
        return .ready(session: session, weekly: weekly, staleReason: usageStaleCache[profile.name])
    }

    // MARK: - Usage

    private func refreshUsageNow() {
        // Force an immediate fetch, but never while one is running: repeated clicks
        // would fire a burst of requests and rate-limit the account.
        guard !isFetchingUsage else { return }
        usageNextRefresh = .distantPast
        refreshUsage()
    }

    private struct UsageOutcome {
        let name: String
        let snapshot: UsageSnapshot?
        let errorLine: String?
        let backoffSeconds: TimeInterval?
        // Transient failures (rate limit, network blip) resolve on their own, so cached
        // values stay displayed; persistent ones (expired token) need the user to act.
        let isTransient: Bool
    }

    // The menu bar modules need usage without the panel ever being opened, so they
    // run their own clock instead of relying on the panel showing.
    private func applyMenuBarModules() {
        if menuBarModulesEnabled {
            if menuBarUsageTimer == nil {
                menuBarUsageTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                    self?.refreshUsage()
                }
                menuBarUsageTimer?.tolerance = 30
            }
            refreshUsage()
        } else {
            menuBarUsageTimer?.invalidate()
            menuBarUsageTimer = nil
        }
        refreshButtonTitle()
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
        panelModel.isRefreshing = true
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
                self.panelModel.isRefreshing = false
                for outcome in results {
                    self.store(outcome)
                }
                self.refreshButtonTitle()
                if let backoff = results.compactMap(\.backoffSeconds).max() {
                    self.usageNextRefresh = Date().addingTimeInterval(backoff)
                }
                self.syncModel()
            }
        }
    }

    private static func outcome(for result: Result<UsageSnapshot, Error>, name: String) -> UsageOutcome {
        switch result {
        case .success(let snapshot):
            return UsageOutcome(name: name, snapshot: snapshot, errorLine: nil, backoffSeconds: nil, isTransient: false)
        case .failure(let error):
            switch error as? SwitchError {
            case .usageTokenExpired, .usageTokenMissing:
                return UsageOutcome(name: name, snapshot: nil, errorLine: L("menu.usage.expired"), backoffSeconds: nil, isTransient: false)
            case .usageRateLimited(let retryAfter):
                return UsageOutcome(name: name, snapshot: nil, errorLine: L("menu.usage.rateLimited"), backoffSeconds: TimeInterval(retryAfter ?? 300), isTransient: true)
            default:
                return UsageOutcome(name: name, snapshot: nil, errorLine: L("menu.usage.unavailable"), backoffSeconds: nil, isTransient: true)
            }
        }
    }

    // The reset times are stabilized against the cached values before anything is
    // displayed, so the panel and the menu bar always show the same time.
    private func store(_ outcome: UsageOutcome) {
        guard let snapshot = outcome.snapshot else {
            if outcome.isTransient, sessionPercentCache[outcome.name] != nil {
                usageStaleCache[outcome.name] = outcome.errorLine
            } else {
                usageErrorCache[outcome.name] = outcome.errorLine
                usageStaleCache[outcome.name] = nil
                sessionPercentCache[outcome.name] = nil
                sessionResetCache[outcome.name] = nil
                weeklyPercentCache[outcome.name] = nil
                weeklyResetCache[outcome.name] = nil
            }
            return
        }
        usageErrorCache[outcome.name] = nil
        usageStaleCache[outcome.name] = nil
        sessionPercentCache[outcome.name] = Int(snapshot.session.utilizationPercent.rounded())
        sessionResetCache[outcome.name] = SessionReset.stabilized(
            new: snapshot.session.resetsAt,
            previous: sessionResetCache[outcome.name]
        )
        if let weekly = snapshot.weekly {
            weeklyPercentCache[outcome.name] = Int(weekly.utilizationPercent.rounded())
            weeklyResetCache[outcome.name] = SessionReset.stabilized(
                new: weekly.resetsAt,
                previous: weeklyResetCache[outcome.name]
            )
        } else {
            weeklyPercentCache[outcome.name] = nil
            weeklyResetCache[outcome.name] = nil
        }
    }

    // MARK: - Profiles

    private func switchProfile(named name: String) {
        guard let switcher else { return }
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

    private func addProfile() {
        guard let switcher else { return }
        let defaultHex = ProfileColorHex.palette[switcher.profiles.count % ProfileColorHex.palette.count]
        guard let form = promptForProfile(title: L("alert.newProfileName"), initialColorHex: defaultHex) else { return }
        let added = run { try switcher.addProfile(named: form.name, colorHex: form.colorHex) }
        guard added else { return }
        if ask(
            title: L("alert.profileCreated.title", form.name),
            message: L("alert.profileCreated.message"),
            confirmTitle: L("alert.profileCreated.confirm"),
            cancelTitle: L("alert.profileCreated.later")
        ) {
            run { try switcher.captureActiveAccount(into: form.name) }
        }
    }

    // Capturing overwrites the profile's previous snapshot with whatever account the
    // CLI is currently logged into; too consequential to run on a stray click.
    private func captureProfile(named name: String) {
        guard let switcher else { return }
        guard ask(
            title: L("alert.capture.title", name),
            message: L("alert.capture.message"),
            confirmTitle: L("alert.capture.confirm")
        ) else { return }
        run { try switcher.captureActiveAccount(into: name) }
    }

    private func editProfile(named name: String) {
        guard let switcher, let profile = switcher.profiles.first(where: { $0.name == name }) else { return }
        let currentHex = profile.colorHex ?? ProfileColorHex.defaultHex(forSeed: profile.id)
        guard let form = promptForProfile(
            title: L("alert.editProfile", name),
            initialName: name,
            initialColorHex: currentHex
        ) else { return }
        run {
            try switcher.renameProfile(name, to: form.name)
            try switcher.setProfileColor(named: form.name, colorHex: form.colorHex)
        }
    }

    private func deleteProfile(named name: String) {
        guard let switcher else { return }
        guard ask(
            title: L("alert.deleteProfile.title", name),
            message: L("alert.deleteProfile.message"),
            confirmTitle: L("alert.deleteProfile.confirm")
        ) else { return }
        run { try switcher.deleteProfile(name) }
    }

    // MARK: - Settings

    private func openSettings() {
        closePanel()
        if settingsController == nil {
            settingsController = SettingsWindowController(
                title: L("settings.title"),
                panes: [
                    .init(identifier: "general", label: L("settings.tab.general"), symbolName: "gearshape", view: makeGeneralPane()),
                    .init(identifier: "about", label: L("settings.tab.about"), symbolName: "info.circle", view: makeAboutPane()),
                ]
            )
        }
        launchAtLoginCheckbox?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.window.makeKeyAndOrderFront(nil)
    }

    private func makeGeneralPane() -> NSView {
        let titles = [
            Self.showSessionUsageKey: L("settings.menuBar.sessionUsage"),
            Self.showSessionResetKey: L("settings.menuBar.sessionReset"),
        ]
        let controller = MenuBarModulesListController(
            modules: orderedModuleKeys.map { .init(key: $0, title: titles[$0] ?? $0) },
            isEnabled: { UserDefaults.standard.bool(forKey: $0) },
            setEnabled: { [weak self] key, enabled in
                UserDefaults.standard.set(enabled, forKey: key)
                self?.applyMenuBarModules()
            },
            orderChanged: { [weak self] keys in
                UserDefaults.standard.set(keys, forKey: Self.moduleOrderKey)
                self?.refreshButtonTitle()
            }
        )
        modulesListController = controller

        let modulesList = controller.makeView()
        modulesList.translatesAutoresizingMaskIntoConstraints = false
        modulesList.widthAnchor.constraint(equalToConstant: 370).isActive = true
        modulesList.heightAnchor.constraint(equalToConstant: controller.preferredHeight).isActive = true

        let launchCheckbox = NSButton(
            checkboxWithTitle: L("settings.launchAtLogin"),
            target: self,
            action: #selector(toggleLaunchAtLogin(_:))
        )
        launchAtLoginCheckbox = launchCheckbox

        let stack = NSStackView(views: [
            sectionLabel(L("settings.section.menuBar")),
            modulesList,
            sectionLabel(L("settings.section.startup")),
            launchCheckbox,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: modulesList)
        return pane(containing: stack, centered: false)
    }

    private func makeAboutPane() -> NSView {
        let nameLabel = NSTextField(labelWithString: "Claude Switch")
        nameLabel.font = .boldSystemFont(ofSize: 14)

        let versionLabel = NSTextField(labelWithString: L("settings.version", Self.appVersion))
        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [nameLabel, versionLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        return pane(containing: stack, centered: true)
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    // Pins the stack to all four edges so the container reports a definite
    // fittingSize, which the settings window reads to size itself per pane.
    // Centered panes get extra vertical breathing room.
    private func pane(containing stack: NSStackView, centered: Bool) -> NSView {
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        let vertical: CGFloat = centered ? 28 : 20
        var constraints = [
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: vertical),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vertical),
        ]
        if centered {
            constraints += [
                stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 40),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -40),
                container.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            ]
        } else {
            constraints += [
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }

    // The Claude spark glyph, generated by Scripts/generate_menubar_icon.swift.
    // Template image: the system recolors it for light/dark menu bars.
    private static func menuBarIcon() -> NSImage {
        if let icon = Bundle.module.image(forResource: "MenuBarIcon") {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            return icon
        }
        return NSImage(
            systemSymbolName: "person.crop.circle.badge.checkmark",
            accessibilityDescription: "Claude Switch"
        )!
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
            // A switch or capture changes which token backs each profile; drop the
            // cached usage so the next refresh refetches instead of showing stale %.
            sessionPercentCache.removeAll()
            sessionResetCache.removeAll()
            weeklyPercentCache.removeAll()
            weeklyResetCache.removeAll()
            usageErrorCache.removeAll()
            usageStaleCache.removeAll()
            usageNextRefresh = .distantPast
            syncModel()
            refreshButtonTitle()
            if menuBarModulesEnabled || popover.isShown {
                refreshUsage()
            }
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    private func refreshButtonTitle() {
        guard let name = switcher?.activeProfileName() else {
            statusItem.button?.title = ""
            return
        }
        var title = " \(name)"
        for key in orderedModuleKeys where UserDefaults.standard.bool(forKey: key) {
            switch key {
            case Self.showSessionUsageKey:
                if let percent = sessionPercentCache[name] {
                    title += L("menuBar.sessionUsage", percent)
                }
            case Self.showSessionResetKey:
                if let resetsAt = sessionResetCache[name] {
                    let time = DateFormatter.localizedString(from: resetsAt, dateStyle: .none, timeStyle: .short)
                    title += L("menuBar.sessionReset", time)
                }
            default:
                break
            }
        }
        statusItem.button?.title = title
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

    private struct ProfileForm {
        let name: String
        let colorHex: String
    }

    private func promptForProfile(title: String, initialName: String = "", initialColorHex: String) -> ProfileForm? {
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title

        let field = NSTextField(frame: NSRect(x: 0, y: 34, width: 220, height: 24))
        field.stringValue = initialName

        // .minimal opens the native swatch picker in a popover, which stays usable
        // inside the alert's modal session (the full NSColorPanel would not).
        let colorWell = NSColorWell(style: .minimal)
        if let rgb = ProfileColorHex.rgb(from: initialColorHex) {
            colorWell.color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
        let colorLabel = NSTextField(labelWithString: L("alert.profileColor"))
        colorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        colorLabel.textColor = .secondaryLabelColor
        colorLabel.sizeToFit()
        colorLabel.setFrameOrigin(NSPoint(x: 0, y: 7))
        colorWell.frame = NSRect(x: colorLabel.frame.maxX + 8, y: 2, width: 44, height: 24)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 58))
        container.addSubview(field)
        container.addSubview(colorLabel)
        container.addSubview(colorWell)
        alert.accessoryView = container

        alert.addButton(withTitle: L("alert.ok"))
        alert.addButton(withTitle: L("alert.cancel"))
        alert.window.initialFirstResponder = field
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        NSColorPanel.shared.close()
        guard confirmed else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let color = colorWell.color.usingColorSpace(.sRGB) ?? colorWell.color
        return ProfileForm(
            name: name,
            colorHex: ProfileColorHex.hex(
                red: color.redComponent,
                green: color.greenComponent,
                blue: color.blueComponent
            )
        )
    }

    private func ask(title: String, message: String, confirmTitle: String, cancelTitle: String? = nil) -> Bool {
        closePanel()
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
        closePanel()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Claude Switch"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
