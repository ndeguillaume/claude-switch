import Foundation

public struct UsageSnapshot: Equatable {
    public let utilizationPercent: Double
    public let resetsAt: Date?

    public init(utilizationPercent: Double, resetsAt: Date?) {
        self.utilizationPercent = utilizationPercent
        self.resetsAt = resetsAt
    }

    public static func parse(_ data: Data) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SwitchError.usageResponseUnreadable
        }
        for key in ["five_hour", "fiveHour", "session"] {
            guard let window = root[key] as? [String: Any],
                  let utilization = window["utilization"] as? NSNumber
            else { continue }
            let resetsAt = (window["resets_at"] as? String).flatMap(parseISODate)
                ?? (window["resetsAt"] as? String).flatMap(parseISODate)
            return UsageSnapshot(utilizationPercent: utilization.doubleValue, resetsAt: resetsAt)
        }
        throw SwitchError.usageResponseUnreadable
    }

    private static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

public enum OAuthCredentials {
    public static func accessToken(fromKeychainData data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let nested = root["claudeAiOauth"] as? [String: Any],
           let token = nested["accessToken"] as? String {
            return token
        }
        return root["accessToken"] as? String
    }
}

public protocol UsageFetcher {
    func fetchUsage(accessToken: String) async throws -> UsageSnapshot
}

public final class AnthropicUsageFetcher: UsageFetcher {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init() {}

    public func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SwitchError.usageResponseUnreadable
        }
        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap { Int($0) }
            throw SwitchError.usageRateLimited(retryAfterSeconds: retryAfter)
        }
        guard http.statusCode == 200 else {
            throw SwitchError.usageRequestFailed(http.statusCode)
        }
        return try UsageSnapshot.parse(data)
    }
}

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
                  let token = OAuthCredentials.accessToken(fromKeychainData: item.data)
            else {
                return .failure(SwitchError.usageTokenMissing)
            }
            return .success(try await fetcher.fetchUsage(accessToken: token))
        } catch {
            return .failure(error)
        }
    }
}
