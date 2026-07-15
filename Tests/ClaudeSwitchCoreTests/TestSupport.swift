import Foundation

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeSwitchTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeConfigFixture(to url: URL, email: String) throws {
    let root: [String: Any] = [
        "numStartups": 42,
        "hasCompletedOnboarding": true,
        "projects": ["/tmp/foo": ["allowedTools": []]],
        "oauthAccount": [
            "accountUuid": "uuid-\(email)",
            "emailAddress": email,
            "organizationName": "Org de \(email)",
        ],
    ]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    try data.write(to: url)
}
