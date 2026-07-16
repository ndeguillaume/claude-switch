import Foundation

/// Resolves the user's saved menu bar module order against the modules this build
/// knows: saved order wins, stale keys drop out, and modules the saved order has
/// never seen append in their default position — adding a module in a future
/// version never loses the user's ordering.
public enum MenuBarModuleOrder {
    public static func resolve(saved: [String], known: [String]) -> [String] {
        let kept = saved.filter(known.contains)
        return kept + known.filter { !kept.contains($0) }
    }
}
