import XCTest
@testable import ClaudeSwitchCore

final class LocalizationTests: XCTestCase {
    private let allErrors: [SwitchError] = [
        .notLoggedIn,
        .profileUnknown("Zorg"),
        .profileNotCaptured("Zorg"),
        .credentialEmpty("Zorg"),
        .profileAlreadyExists("Zorg"),
        .invalidProfileName,
        .securityCommand("The specified item could not be found in the keychain."),
        .configUnreadable("/tmp/x.json"),
        .oauthAccountMissing,
    ]

    func testEveryErrorResolvesToALocalizedMessage() {
        for error in allErrors {
            let message = error.errorDescription
            XCTAssertNotNil(message)
            XCTAssertFalse(message!.isEmpty)
            XCTAssertFalse(message!.hasPrefix("error."), "Clé non résolue : \(message!)")
        }
    }

    func testParameterizedErrorsIncludeTheirArgument() {
        XCTAssertTrue(SwitchError.profileUnknown("Zorg").errorDescription!.contains("Zorg"))
        XCTAssertTrue(SwitchError.profileNotCaptured("Zorg").errorDescription!.contains("Zorg"))
        XCTAssertTrue(SwitchError.credentialEmpty("Zorg").errorDescription!.contains("Zorg"))
        XCTAssertTrue(SwitchError.profileAlreadyExists("Zorg").errorDescription!.contains("Zorg"))
        XCTAssertTrue(SwitchError.configUnreadable("/tmp/x.json").errorDescription!.contains("/tmp/x.json"))
    }

    func testCoreBundleShipsFrenchAndEnglish() {
        let localizations = Set(Bundle.module.localizations)
        XCTAssertTrue(localizations.contains("fr"), "fr manquant : \(localizations)")
        XCTAssertTrue(localizations.contains("en"), "en manquant : \(localizations)")
    }
}
