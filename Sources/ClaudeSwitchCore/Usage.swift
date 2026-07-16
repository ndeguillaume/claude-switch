import Foundation

/// One rate-limit window from the OAuth usage endpoint: how much of the quota is
/// consumed and when it resets.
public struct UsageWindow: Equatable {
    public let utilizationPercent: Double
    public let resetsAt: Date?

    public init(utilizationPercent: Double, resetsAt: Date?) {
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
    }
}

/// The usage response, reduced to what the menu shows: the current 5-hour session
/// window (the primary interest) and the rolling 7-day window.
public struct UsageSnapshot: Equatable {
    public let session: UsageWindow
    public let weekly: UsageWindow?

    public init(session: UsageWindow, weekly: UsageWindow?) {
        self.session = session
        self.weekly = weekly
    }

    public static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SwitchError.usageResponseUnreadable
        }
        guard let session = window(root["five_hour"]) else {
            throw SwitchError.usageResponseUnreadable
        }
        return UsageSnapshot(session: session, weekly: window(root["seven_day"]))
    }

    private static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? NSNumber
        else { return nil }
        let resetsAt = (dict["resets_at"] as? String).flatMap(parseISODate)
        return UsageWindow(utilizationPercent: utilization.doubleValue, resetsAt: resetsAt)
    }

    private static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

/// The usage endpoint recomputes `resets_at` on every call, so the value drifts by
/// a few seconds between fetches; displayed as minutes it flaps between e.g. 13:59
/// and 14:00. Keep the previously shown time while the fresh value stays within
/// tolerance, and round newly adopted values to the minute.
public enum SessionReset {
    public static func stabilized(new: Date?, previous: Date?, toleranceSeconds: TimeInterval = 90) -> Date? {
        guard let new else { return nil }
        if let previous, abs(new.timeIntervalSince(previous)) <= toleranceSeconds {
            return previous
        }
        return roundedToMinute(new)
    }

    static func roundedToMinute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded() * 60)
    }
}

public protocol UsageFetcher {
    func fetchUsage(accessToken: String) async throws -> UsageSnapshot
}

/// GET api.anthropic.com/api/oauth/usage with the OAuth access token, the same call
/// the CLI's /usage makes. `anthropic-beta: oauth-2025-04-20` gates the OAuth surface.
public final class AnthropicUsageFetcher: UsageFetcher {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SwitchError.usageResponseUnreadable
        }
        switch http.statusCode {
        case 200:
            return try UsageSnapshot.parse(data)
        case 401:
            throw SwitchError.usageTokenExpired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
            throw SwitchError.usageRateLimited(retryAfterSeconds: retryAfter)
        default:
            // A revoked/expired token can also surface as a body marker on a non-401.
            if let body = String(data: data, encoding: .utf8), body.contains("token_expired") {
                throw SwitchError.usageTokenExpired
            }
            throw SwitchError.usageRequestFailed(http.statusCode)
        }
    }
}

/// Fetches usage for whichever Keychain item holds the token: the live
/// `Claude Code-credentials` for the active account (kept fresh by the CLI), or a
/// profile's snapshot copy for an inactive one (whose token may have expired).
public final class UsageService {
    private let keychain: KeychainClient
    private let fetcher: UsageFetcher

    public init(keychain: KeychainClient, fetcher: UsageFetcher) {
        self.keychain = keychain
        self.fetcher = fetcher
    }

    public func usage(tokenService: String) async -> Result<UsageSnapshot, Error> {
        do {
            guard let item = try keychain.read(service: tokenService),
                  let token = ClaudeCredential.accessToken(item.data)
            else {
                return .failure(SwitchError.usageTokenMissing)
            }
            return .success(try await fetcher.fetchUsage(accessToken: token))
        } catch {
            return .failure(error)
        }
    }
}
