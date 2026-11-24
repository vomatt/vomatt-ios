import Foundation

/// The turn of the ballot stamp marking the viewer's option, in degrees (the web's `BallotMotion`). A press lands at
/// any angle; a vote already cast is drawn at one taken from its option's id, the same on every platform.
public enum StampAngle {
    /// `unit` in [0, 1) picks an angle anywhere in the full circle.
    public static func angle(_ unit: Double) -> Double { unit * 360 }

    /// The web's `seededUnit`: a 32-bit `hash * 31 + code` over the seed's UTF-16 code units, one per code point.
    public static func seeded(_ seed: String) -> Double {
        var hash: UInt32 = 0
        for scalar in seed.unicodeScalars {
            hash = hash &* 31 &+ UInt32(String(scalar).utf16.first ?? 0)
        }
        return angle(Double(hash % 1000) / 1000)
    }
}
