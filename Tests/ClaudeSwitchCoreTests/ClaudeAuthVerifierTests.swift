import XCTest
@testable import ClaudeSwitchCore

private struct StubCLI: ClaudeCLIRunning {
    let output: Data?
    func authStatusJSON() -> Data? { output }
}

final class ClaudeAuthVerifierTests: XCTestCase {
    // Real `claude auth status --json` output shape (2.1.211).
    private let loggedInJSON = Data("""
    {
      "loggedIn": true,
      "authMethod": "claude.ai",
      "apiProvider": "firstParty",
      "email": "nicolas@betomorrow.com",
      "orgId": "ee854252-0000-0000-0000-000000000000",
      "orgName": "BeTomorrow",
      "subscriptionType": "team"
    }
    """.utf8)

    private func verifier(returning output: Data?) -> ClaudeAuthVerifier {
        ClaudeAuthVerifier(cli: StubCLI(output: output))
    }

    func testVerifiedWhenEmailMatches() {
        XCTAssertEqual(
            verifier(returning: loggedInJSON).verify(expectedEmail: "nicolas@betomorrow.com"),
            .verified
        )
    }

    func testEmailComparisonIsCaseInsensitive() {
        XCTAssertEqual(
            verifier(returning: loggedInJSON).verify(expectedEmail: "Nicolas@BeTomorrow.com"),
            .verified
        )
    }

    func testWrongAccountWhenEmailDiffers() {
        XCTAssertEqual(
            verifier(returning: loggedInJSON).verify(expectedEmail: "perso@gmail.com"),
            .wrongAccount(expected: "perso@gmail.com", actual: "nicolas@betomorrow.com")
        )
    }

    func testNotLoggedIn() {
        let json = Data(#"{"loggedIn": false, "authMethod": "none"}"#.utf8)
        XCTAssertEqual(verifier(returning: json).verify(expectedEmail: "perso@gmail.com"), .notLoggedIn)
    }

    func testVerifiedWhenClaudeReportsNoEmail() {
        // Non-claude.ai auth (API key…): loggedIn is the only usable signal.
        let json = Data(#"{"loggedIn": true, "authMethod": "api_key"}"#.utf8)
        XCTAssertEqual(verifier(returning: json).verify(expectedEmail: "perso@gmail.com"), .verified)
    }

    func testVerifiedWhenNoExpectedEmail() {
        XCTAssertEqual(verifier(returning: loggedInJSON).verify(expectedEmail: nil), .verified)
        XCTAssertEqual(verifier(returning: loggedInJSON).verify(expectedEmail: ""), .verified)
    }

    func testUnavailableWhenCLIMissing() {
        XCTAssertEqual(verifier(returning: nil).verify(expectedEmail: "perso@gmail.com"), .unavailable)
    }

    func testUnavailableWhenOutputUnreadable() {
        let garbage = Data("not json".utf8)
        XCTAssertEqual(verifier(returning: garbage).verify(expectedEmail: "perso@gmail.com"), .unavailable)
    }

    func testParseRejectsPayloadWithoutLoggedIn() {
        XCTAssertNil(ClaudeAuthStatus.parse(Data(#"{"email": "x@y.z"}"#.utf8)))
    }
}
