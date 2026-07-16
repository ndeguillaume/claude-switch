import XCTest
@testable import ClaudeSwitchCore

final class ClaudeCredentialTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testAcceptsCredentialWithAccessToken() {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"sk-ant-ort01-def"}}"#
        XCTAssertTrue(ClaudeCredential.hasAccessToken(data(json)))
    }

    func testRejectsEmptyAccessToken() {
        // The exact shape claude leaves behind mid-refresh / after /logout.
        let json = #"{"claudeAiOauth":{"accessToken":"","refreshToken":"","expiresAt":0,"scopes":[]}}"#
        XCTAssertFalse(ClaudeCredential.hasAccessToken(data(json)))
    }

    func testRejectsMissingAccessToken() {
        let json = #"{"claudeAiOauth":{"refreshToken":"sk-ant-ort01-def"}}"#
        XCTAssertFalse(ClaudeCredential.hasAccessToken(data(json)))
    }

    func testRejectsMissingOAuthBlock() {
        XCTAssertFalse(ClaudeCredential.hasAccessToken(data(#"{"other":1}"#)))
    }

    func testRejectsNonJSON() {
        XCTAssertFalse(ClaudeCredential.hasAccessToken(Data()))
        XCTAssertFalse(ClaudeCredential.hasAccessToken(data("not json")))
    }
}
