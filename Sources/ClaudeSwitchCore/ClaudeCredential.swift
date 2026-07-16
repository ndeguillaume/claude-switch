import Foundation

/// The Keychain secret claude stores under `Claude Code-credentials`: a JSON blob
/// `{"claudeAiOauth":{"accessToken":…}}`. Right after /logout or mid-refresh, claude
/// leaves the full JSON skeleton in place but with empty token strings. Capturing or
/// restoring such a blob yields a profile that silently forces a fresh /login, so the
/// switcher must treat "no accessToken" as "no usable session".
enum ClaudeCredential {
    static func hasAccessToken(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return false }
        return token.isEmpty == false
    }
}
