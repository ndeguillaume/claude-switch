import Foundation

public struct ClaudeConfigFile {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard() -> ClaudeConfigFile {
        ClaudeConfigFile(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"))
    }

    public func readOAuthAccount() throws -> Data {
        let root = try loadRoot()
        guard let oauth = root["oauthAccount"] as? [String: Any] else {
            throw SwitchError.oauthAccountMissing
        }
        return try JSONSerialization.data(withJSONObject: oauth, options: [.sortedKeys])
    }

    public func writeOAuthAccount(_ oauthAccountData: Data) throws {
        guard let oauth = (try? JSONSerialization.jsonObject(with: oauthAccountData)) as? [String: Any] else {
            throw SwitchError.oauthAccountMissing
        }
        var root = try loadRoot()
        root["oauthAccount"] = oauth
        let output = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try output.write(to: url, options: [.atomic])
    }

    public func activeEmail() throws -> String? {
        let root = try loadRoot()
        return (root["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
    }

    public static func email(fromOAuthAccountData data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any])?["emailAddress"] as? String
    }

    private func loadRoot() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else {
            throw SwitchError.configUnreadable(url.path)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            throw SwitchError.configUnreadable(url.path)
        }
        return root
    }
}
