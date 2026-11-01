/// A tiny, fast, seedable pseudo-random generator (SplitMix64, Steele/Lea/Flood 2014).
///
/// Hand-rolled on purpose (plan section 12, ADR 0009): the core has zero dependencies, and the
/// standard library's generators are not seedable. The output for a given seed is the same on
/// every platform, which the planner's deterministic tie-breaks rely on (AC-4.6).
public struct SplitMix64: RandomNumberGenerator, Sendable, Hashable {
    /// The golden-ratio increment added to the state on every step.
    public static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15

    public private(set) var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    /// The next 64 random bits.
    public mutating func next() -> UInt64 {
        state = state &+ SplitMix64.gamma
        return SplitMix64.mix(state)
    }

    /// The SplitMix64 output function: a bijective avalanche mix of `value`.
    public static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniformly chosen index in `0..<count` (rejection sampling, so no modulo bias).
    /// - Precondition: `count > 0`.
    public mutating func nextIndex(below count: Int) -> Int {
        precondition(count > 0, "nextIndex(below:) needs a positive count")
        let bound = UInt64(count)
        // Largest multiple of `bound` that fits; values at or above it are redrawn.
        let limit = UInt64.max - (UInt64.max % bound)
        while true {
            let value = next()
            if value < limit {
                return Int(value % bound)
            }
        }
    }
}
