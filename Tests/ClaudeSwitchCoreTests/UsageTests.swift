import XCTest
@testable import ClaudeSwitchCore

private final class MockUsageFetcher: UsageFetcher {
    var snapshot: UsageSnapshot?
    var error: Error?
    private(set) var receivedTokens: [String] = []

    func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        receivedTokens.append(accessToken)
        if let error { throw error }
        return snapshot!
    }
}

final class UsageTests: XCTestCase {

    // MARK: - UsageSnapshot.parse

    func testParseSessionAndWeekly() throws {
        let body = Data(#"""
        {"five_hour": {"utilization": 34.5, "resets_at": "2026-07-16T18:00:00Z"},
         "seven_day": {"utilization": 12}}
        """#.utf8)
        let snapshot = try UsageSnapshot.parse(body)
        XCTAssertEqual(snapshot.session.utilizationPercent, 34.5)
        XCTAssertEqual(snapshot.session.resetsAt, ISO8601DateFormatter().date(from: "2026-07-16T18:00:00Z"))
        XCTAssertEqual(snapshot.weekly?.utilizationPercent, 12)
        XCTAssertNil(snapshot.weekly?.resetsAt)
    }

    func testParseIntUtilizationAndFractionalSeconds() throws {
        let body = Data(#"{"five_hour": {"utilization": 80, "resets_at": "2026-07-16T18:00:00.123Z"}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(body)
        XCTAssertEqual(snapshot.session.utilizationPercent, 80)
        XCTAssertNotNil(snapshot.session.resetsAt)
        XCTAssertNil(snapshot.weekly)
    }

    func testParseMissingResetDateStillSucceeds() throws {
        let snapshot = try UsageSnapshot.parse(Data(#"{"five_hour": {"utilization": 5}}"#.utf8))
        XCTAssertEqual(snapshot.session.utilizationPercent, 5)
        XCTAssertNil(snapshot.session.resetsAt)
    }

    func testParseMissingSessionWindowThrows() {
        XCTAssertThrowsError(try UsageSnapshot.parse(Data(#"{"seven_day": {"utilization": 12}}"#.utf8))) { error in
            XCTAssertEqual(error as? SwitchError, .usageResponseUnreadable)
        }
    }

    func testParseGarbageThrows() {
        XCTAssertThrowsError(try UsageSnapshot.parse(Data("not json".utf8))) { error in
            XCTAssertEqual(error as? SwitchError, .usageResponseUnreadable)
        }
    }

    // MARK: - UsageService

    private func keychain(service: String, token: String) throws -> InMemoryKeychainClient {
        let keychain = InMemoryKeychainClient()
        try keychain.upsert(
            service: service,
            item: KeychainItem(account: "n", data: Data(#"{"claudeAiOauth":{"accessToken":"\#(token)"}}"#.utf8))
        )
        return keychain
    }

    func testUsageReadsTokenFromKeychainService() async throws {
        let keychain = try keychain(service: "ClaudeSwitch.profile.abc", token: "tok-perso")
        let fetcher = MockUsageFetcher()
        fetcher.snapshot = UsageSnapshot(session: UsageWindow(utilizationPercent: 42, resetsAt: nil), weekly: nil)
        let service = UsageService(keychain: keychain, fetcher: fetcher)

        let result = await service.usage(tokenService: "ClaudeSwitch.profile.abc")

        XCTAssertEqual(try result.get().session.utilizationPercent, 42)
        XCTAssertEqual(fetcher.receivedTokens, ["tok-perso"])
    }

    func testUsageWithoutKeychainItemFails() async {
        let service = UsageService(keychain: InMemoryKeychainClient(), fetcher: MockUsageFetcher())
        let result = await service.usage(tokenService: "absent")
        guard case .failure(let error) = result else { return XCTFail("succès inattendu") }
        XCTAssertEqual(error as? SwitchError, .usageTokenMissing)
    }

    func testUsageWithEmptyTokenFails() async throws {
        let keychain = InMemoryKeychainClient()
        try keychain.upsert(
            service: "s",
            item: KeychainItem(account: "n", data: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8))
        )
        let service = UsageService(keychain: keychain, fetcher: MockUsageFetcher())
        let result = await service.usage(tokenService: "s")
        guard case .failure(let error) = result else { return XCTFail("succès inattendu") }
        XCTAssertEqual(error as? SwitchError, .usageTokenMissing)
    }

    func testExpiredTokenErrorIsPropagated() async throws {
        let keychain = try keychain(service: "s", token: "tok")
        let fetcher = MockUsageFetcher()
        fetcher.error = SwitchError.usageTokenExpired
        let service = UsageService(keychain: keychain, fetcher: fetcher)

        let result = await service.usage(tokenService: "s")

        guard case .failure(let error) = result else { return XCTFail("succès inattendu") }
        XCTAssertEqual(error as? SwitchError, .usageTokenExpired)
    }

    func testRateLimitErrorEquatableAcrossRetryAfter() {
        XCTAssertEqual(SwitchError.usageRateLimited(retryAfterSeconds: 120), .usageRateLimited(retryAfterSeconds: 120))
        XCTAssertNotEqual(SwitchError.usageRateLimited(retryAfterSeconds: 120), .usageRateLimited(retryAfterSeconds: nil))
    }

    // MARK: - SessionReset.stabilized

    private let base = Date(timeIntervalSinceReferenceDate: 800_000_040) // multiple de 60 : déjà pile à la minute

    func testNilNewClearsTheDate() {
        XCTAssertNil(SessionReset.stabilized(new: nil, previous: base))
    }

    func testFirstValueIsRoundedToTheMinute() {
        XCTAssertEqual(SessionReset.stabilized(new: base.addingTimeInterval(29), previous: nil), base)
        XCTAssertEqual(SessionReset.stabilized(new: base.addingTimeInterval(31), previous: nil), base.addingTimeInterval(60))
    }

    func testDriftWithinToleranceKeepsThePreviousValue() {
        XCTAssertEqual(SessionReset.stabilized(new: base.addingTimeInterval(45), previous: base), base)
        XCTAssertEqual(SessionReset.stabilized(new: base.addingTimeInterval(-45), previous: base), base)
        XCTAssertEqual(SessionReset.stabilized(new: base.addingTimeInterval(90), previous: base), base)
    }

    func testNewSessionWindowAdoptsTheNewValue() {
        let nextWindow = base.addingTimeInterval(5 * 3600 + 12)
        XCTAssertEqual(SessionReset.stabilized(new: nextWindow, previous: base), base.addingTimeInterval(5 * 3600))
    }
}
