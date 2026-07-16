import Foundation

public enum SwitchError: LocalizedError, Equatable {
    case notLoggedIn
    case profileUnknown(String)
    case profileNotCaptured(String)
    case credentialEmpty(String)
    case profileAlreadyExists(String)
    case invalidProfileName
    case securityCommand(String)
    case configUnreadable(String)
    case oauthAccountMissing

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return localized("error.notLoggedIn")
        case .profileUnknown(let name):
            return localized("error.profileUnknown", name)
        case .profileNotCaptured(let name):
            return localized("error.profileNotCaptured", name)
        case .credentialEmpty(let name):
            return localized("error.credentialEmpty", name)
        case .profileAlreadyExists(let name):
            return localized("error.profileAlreadyExists", name)
        case .invalidProfileName:
            return localized("error.invalidProfileName")
        case .securityCommand(let message):
            return localized("error.securityCommand", message)
        case .configUnreadable(let path):
            return localized("error.configUnreadable", path)
        case .oauthAccountMissing:
            return localized("error.oauthAccountMissing")
        }
    }
}
