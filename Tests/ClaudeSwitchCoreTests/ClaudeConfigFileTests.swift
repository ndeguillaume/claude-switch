import XCTest
@testable import ClaudeSwitchCore

final class ClaudeConfigFileTests: XCTestCase {
    private var directory: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        directory = try makeTempDirectory()
        configURL = directory.appendingPathComponent(".claude.json")
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testReadOAuthAccountAndEmail() throws {
        try writeConfigFixture(to: configURL, email: "perso@example.com")
        let config = ClaudeConfigFile(url: configURL)

        let data = try config.readOAuthAccount()
        XCTAssertEqual(ClaudeConfigFile.email(fromOAuthAccountData: data), "perso@example.com")
        XCTAssertEqual(try config.activeEmail(), "perso@example.com")
    }

    func testWriteOAuthAccountPreservesOtherKeys() throws {
        try writeConfigFixture(to: configURL, email: "perso@example.com")
        let config = ClaudeConfigFile(url: configURL)

        let proAccount = try JSONSerialization.data(withJSONObject: [
            "accountUuid": "uuid-pro",
            "emailAddress": "pro@example.com",
        ])
        try config.writeOAuthAccount(proAccount)

        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        XCTAssertEqual(root["numStartups"] as? Int, 42)
        XCTAssertEqual(root["hasCompletedOnboarding"] as? Bool, true)
        XCTAssertNotNil(root["projects"])
        XCTAssertEqual(try config.activeEmail(), "pro@example.com")
    }

    func testMissingOAuthAccountThrows() throws {
        try JSONSerialization.data(withJSONObject: ["numStartups": 1]).write(to: configURL)
        let config = ClaudeConfigFile(url: configURL)

        XCTAssertThrowsError(try config.readOAuthAccount()) { error in
            XCTAssertEqual(error as? SwitchError, .oauthAccountMissing)
        }
    }

    func testMissingFileThrows() {
        let config = ClaudeConfigFile(url: configURL)
        XCTAssertThrowsError(try config.readOAuthAccount()) { error in
            XCTAssertEqual(error as? SwitchError, .configUnreadable(configURL.path))
        }
    }
}
