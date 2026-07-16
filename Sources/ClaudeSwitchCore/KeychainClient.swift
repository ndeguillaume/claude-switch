import Foundation

public struct KeychainItem: Equatable {
    public let account: String
    public let data: Data

    public init(account: String, data: Data) {
        self.account = account
        self.data = data
    }
}

public protocol KeychainClient {
    func read(service: String) throws -> KeychainItem?
    func upsert(service: String, item: KeychainItem) throws
    func delete(service: String) throws
}

/// Talks to the Keychain through /usr/bin/security, the same Apple-signed binary the
/// claude CLI shells out to. Items written this way carry an ACL that trusts `security`,
/// whose code signature never changes — unlike this app's ad hoc signature, which changes
/// on every rebuild and made Security.framework access re-prompt endlessly.
///
/// Every operation pins the account to the current macOS user, exactly as the claude CLI
/// does when it reads/writes `Claude Code-credentials`. Reading or writing the live item
/// under any other account would leave claude unable to find it, forcing a fresh /login.
public final class SecurityCLIKeychainClient: KeychainClient {
    struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String

        var failureMessage: String {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "exit \(status)" : message
        }
    }

    private let account: String

    public init(account: String = NSUserName()) {
        self.account = account
    }

    public func read(service: String) throws -> KeychainItem? {
        guard let secret = try find(service: service) else { return nil }
        return KeychainItem(account: account, data: Self.decodeSecret(secret))
    }

    public func upsert(service: String, item: KeychainItem) throws {
        try delete(service: service)
        // Recreating the item (instead of updating in place) resets its ACL to one that
        // trusts /usr/bin/security, so both this app and the claude CLI read it silently.
        // -U covers the case where the preceding delete matched nothing.
        let result = run([
            "add-generic-password",
            "-s", service,
            "-a", account,
            "-w", String(decoding: item.data, as: UTF8.self),
            "-U",
        ])
        guard result.status == 0 else {
            throw SwitchError.securityCommand(result.failureMessage)
        }
    }

    public func delete(service: String) throws {
        let result = run(["delete-generic-password", "-s", service, "-a", account])
        guard result.status == 0 || Self.isNotFound(result) else {
            throw SwitchError.securityCommand(result.failureMessage)
        }
    }

    // MARK: - security(1) invocation

    private func find(service: String) throws -> String? {
        let result = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        if Self.isNotFound(result) { return nil }
        guard result.status == 0 else {
            throw SwitchError.securityCommand(result.failureMessage)
        }
        var output = result.stdout
        if output.hasSuffix("\n") { output.removeLast() }
        return output
    }

    private func run(_ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    static func isNotFound(_ result: CommandResult) -> Bool {
        result.status != 0 && result.stderr.contains("could not be found")
    }

    // MARK: - Output parsing

    /// `security find-generic-password -w` prints the secret verbatim when it is
    /// printable, and hex-encoded otherwise. Claude tokens are JSON, so the plain
    /// form is the normal case; the hex fallback keeps reads correct regardless.
    static func decodeSecret(_ raw: String) -> Data {
        if raw.hasPrefix("{") { return Data(raw.utf8) }
        if raw.count % 2 == 0, raw.isEmpty == false,
           raw.range(of: "^[0-9A-Fa-f]+$", options: .regularExpression) != nil,
           let decoded = Data(hexEncoded: raw) {
            return decoded
        }
        return Data(raw.utf8)
    }
}

private extension Data {
    init?(hexEncoded string: String) {
        var data = Data(capacity: string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
