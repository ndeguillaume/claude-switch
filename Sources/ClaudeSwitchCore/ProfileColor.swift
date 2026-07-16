import Foundation

/// Profile accent colors, stored as "#RRGGBB" in profiles.json. The palette is the
/// fallback for profiles that never chose a color, keyed by a stable hash of the
/// profile id (djb2 rather than hashValue: Swift hashes are seeded per launch, and
/// the color must not change between launches).
public enum ProfileColorHex {
    public static let palette = ["#FF9500", "#007AFF", "#AF52DE", "#FF2D55", "#30B0C7", "#5856D6"]

    public static func defaultHex(forSeed seed: String) -> String {
        var hash: UInt64 = 5381
        for scalar in seed.unicodeScalars {
            hash = hash &* 33 &+ UInt64(scalar.value)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    public static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func component(_ value: Double) -> UInt32 {
            UInt32((min(1, max(0, value)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }
}
