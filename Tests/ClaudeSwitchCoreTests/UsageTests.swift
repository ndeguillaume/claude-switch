import XCTest
@testable import ClaudeSwitchCore

final class MockUsageFetcher: UsageFetcher {
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

    // MARK: - OAuthCredentials

    func testAccessTokenFromNestedBlob() {
        let blob = Data(#"{"claudeAiOauth": {"accessToken": "tok-123", "refreshToken": "r"}}"#.utf8)
        XCTAssertEqual(OAuthCredentials.accessToken(fromKeychainData: blob), "tok-123")
    }

    func testAccessTokenFromFlatBlob() {
        let blob = Data(#"{"accessToken": "tok-456"}"#.utf8)
        XCTAssertEqual(OAuthCredentials.accessToken(fromKeychainData: blob), "tok-456")
    }

    func testAccessTokenFromGarbageIsNil() {
        XCTAssertNil(OAuthCredentials.accessToken(fromKeychainData: Data("pas du json".utf8)))
        XCTAssertNil(OAuthCredentials.accessToken(fromKeychainData: Data("{}".utf8)))
    }

    // MARK: - UsageSnapshot.parse

    func testParseFiveHourWindow() throws {
        let body = Data(#"{"five_hour": {"utilization": 34.5, "resets_at": "2026-07-15T18:00:00Z"}, "seven_day": {"utilization": 12}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(body)
        XCTAssertEqual(snapshot.utilizationPercent, 34.5)
        XCTAssertEqual(
            snapshot.resetsAt,
            ISO8601DateFormatter().date(from: "2026-07-15T18:00:00Z")
        )
    }

    func testParseIntUtilizationAndFractionalSeconds() throws {
        let body = Data(#"{"five_hour": {"utilization": 80, "resets_at": "2026-07-15T18:00:00.123Z"}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(body)
        XCTAssertEqual(snapshot.utilizationPercent, 80)
        XCTAssertNotNil(snapshot.resetsAt)
    }

    func testParseMissingResetDateStillSucceeds() throws {
        let body = Data(#"{"five_hour": {"utilization": 5}}"#.utf8)
        let snapshot = try UsageSnapshot.parse(body)
        XCTAssertEqual(snapshot.utilizationPercent, 5)
        XCTAssertNil(snapshot.resetsAt)
    }

    func testParseMissingWindowThrows() {
        let body = Data(#"{"seven_day": {"utilization": 12}}"#.utf8)
        XCTAssertThrowsError(try UsageSnapshot.parse(body)) { error in
            XCTAssertEqual(error as? SwitchError, .usageResponseUnreadable)
        }
    }

    // MARK: - UsageService

    func testUsageReadsTokenFromKeychainService() async throws {
        let keychain = InMemoryKeychainClient()
        try keychain.upsert(
            service: "ClaudeSwitch.profile.abc",
            item: KeychainItem(account: "n", data: Data(#"{"claudeAiOauth": {"accessToken": "tok-perso"}}"#.utf8))
        )
        let fetcher = MockUsageFetcher()
        fetcher.snapshot = UsageSnapshot(utilizationPercent: 42, resetsAt: nil)
        let service = UsageService(keychain: keychain, fetcher: fetcher)

        let result = await service.usage(tokenService: "ClaudeSwitch.profile.abc")

        XCTAssertEqual(try result.get().utilizationPercent, 42)
        XCTAssertEqual(fetcher.receivedTokens, ["tok-perso"])
    }

    func testUsageWithoutKeychainItemFails() async {
        let service = UsageService(keychain: InMemoryKeychainClient(), fetcher: MockUsageFetcher())

        let result = await service.usage(tokenService: "ClaudeSwitch.profile.absent")

        guard case .failure(let error) = result else { return XCTFail("succès inattendu") }
        XCTAssertEqual(error as? SwitchError, .usageTokenMissing)
    }

    func testUsageFetcherErrorIsPropagated() async throws {
        let keychain = InMemoryKeychainClient()
        try keychain.upsert(
            service: "s",
            item: KeychainItem(account: "n", data: Data(#"{"accessToken": "tok"}"#.utf8))
        )
        let fetcher = MockUsageFetcher()
        fetcher.error = SwitchError.usageRequestFailed(401)
        let service = UsageService(keychain: keychain, fetcher: fetcher)

        let result = await service.usage(tokenService: "s")

        guard case .failure(let error) = result else { return XCTFail("succès inattendu") }
        XCTAssertEqual(error as? SwitchError, .usageRequestFailed(401))
    }
}
