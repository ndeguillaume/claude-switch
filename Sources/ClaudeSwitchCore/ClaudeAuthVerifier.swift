import Foundation

public struct ClaudeAuthStatus: Equatable, Decodable {
    public let loggedIn: Bool
    public let email: String?

    public init(loggedIn: Bool, email: String?) {
        self.loggedIn = loggedIn
        self.email = email
    }

    public static func parse(_ data: Data) -> ClaudeAuthStatus? {
        try? JSONDecoder().decode(ClaudeAuthStatus.self, from: data)
    }
}

public enum AuthVerification: Equatable {
    case verified
    case notLoggedIn
    case wrongAccount(expected: String, actual: String)
    /// The claude CLI is missing or its output unreadable: nothing can be concluded
    /// about the switch itself, so callers should not report this as a failure.
    case unavailable
}

public protocol ClaudeCLIRunning {
    /// Raw stdout of `claude auth status --json`, or nil when the CLI is unavailable.
    func authStatusJSON() -> Data?
}

/// Post-switch check, same as CCSwitcher's step 4: ask the claude CLI itself
/// whether it sees a logged-in account matching the profile just activated.
/// `auth status` is a local read (no network, no token refresh), so this only
/// validates that claude can read the restored keychain item and ~/.claude.json.
public struct ClaudeAuthVerifier {
    private let cli: ClaudeCLIRunning

    public init(cli: ClaudeCLIRunning) {
        self.cli = cli
    }

    public func verify(expectedEmail: String?) -> AuthVerification {
        guard let output = cli.authStatusJSON(),
              let status = ClaudeAuthStatus.parse(output)
        else {
            return .unavailable
        }
        guard status.loggedIn else { return .notLoggedIn }
        guard let expectedEmail, expectedEmail.isEmpty == false,
              let actual = status.email
        else {
            // claude only reports an email for claude.ai OAuth sessions; without
            // both sides of the comparison, loggedIn is the strongest signal left.
            return .verified
        }
        return actual.caseInsensitiveCompare(expectedEmail) == .orderedSame
            ? .verified
            : .wrongAccount(expected: expectedEmail, actual: actual)
    }
}

public struct ClaudeCLIProcessRunner: ClaudeCLIRunning {
    private let binaryURL: URL?

    public init(binaryURL: URL? = Self.locateClaudeBinary()) {
        self.binaryURL = binaryURL
    }

    /// Install locations of the claude CLI, most common first
    /// (same curated list as CCSwitcher's binary discovery).
    public static func locateClaudeBinary(fileManager: FileManager = .default) -> URL? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".npm-global/bin/claude"),
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    public func authStatusJSON() -> Data? {
        guard let binaryURL else { return nil }
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["auth", "status", "--json"]
        // npm-style installs are node scripts: node must be reachable from the
        // binary's own directory, which a GUI app's minimal PATH doesn't cover.
        var environment = ProcessInfo.processInfo.environment
        let binDir = binaryURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        environment["PATH"] = "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // `auth status` is local and sub-second; the watchdog only guards
        // against a wedged CLI keeping the background task alive forever.
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return data.isEmpty ? nil : data
    }
}
