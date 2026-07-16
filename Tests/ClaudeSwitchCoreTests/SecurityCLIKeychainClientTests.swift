import XCTest
@testable import ClaudeSwitchCore

final class SecurityCLIKeychainClientTests: XCTestCase {
    // MARK: - decodeSecret(_:)

    func testDecodeSecretKeepsJSONVerbatim() {
        let json = "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-abc\"}}"
        XCTAssertEqual(SecurityCLIKeychainClient.decodeSecret(json), Data(json.utf8))
    }

    func testDecodeSecretDecodesHexOutput() {
        // "hi" hex-encoded, as security prints non-printable secrets
        XCTAssertEqual(SecurityCLIKeychainClient.decodeSecret("6869"), Data("hi".utf8))
    }

    func testDecodeSecretKeepsNonHexPlainText() {
        XCTAssertEqual(SecurityCLIKeychainClient.decodeSecret("plain-text"), Data("plain-text".utf8))
    }

    func testDecodeSecretEmptyYieldsEmptyData() {
        XCTAssertEqual(SecurityCLIKeychainClient.decodeSecret(""), Data())
    }

    // MARK: - isNotFound

    func testIsNotFoundMatchesSecurityErrorOutput() {
        let result = SecurityCLIKeychainClient.CommandResult(
            status: 44,
            stdout: "",
            stderr: "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain."
        )
        XCTAssertTrue(SecurityCLIKeychainClient.isNotFound(result))
    }

    func testIsNotFoundRejectsOtherFailures() {
        let denied = SecurityCLIKeychainClient.CommandResult(
            status: 128,
            stdout: "",
            stderr: "security: SecKeychainItemCopyContent: User interaction is not allowed."
        )
        XCTAssertFalse(SecurityCLIKeychainClient.isNotFound(denied))
        let success = SecurityCLIKeychainClient.CommandResult(status: 0, stdout: "x", stderr: "")
        XCTAssertFalse(SecurityCLIKeychainClient.isNotFound(success))
    }
}
