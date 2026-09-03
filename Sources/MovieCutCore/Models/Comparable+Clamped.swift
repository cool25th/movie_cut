import Foundation

/// The single shared clamp pair — replaces the twelve per-file private
/// `clamp` helpers that had accumulated across Models/Analysis/Rendering
/// (audit 2026-09-03). Internal: Core-internal dedup only; widen the surface
/// when an app caller actually needs it.
extension Comparable {
    /// Clamps the value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension BinaryFloatingPoint where Self: Comparable {
    /// NaN/infinity-safe clamp: a non-finite value falls back to `fallback`
    /// instead of propagating (the guards the color/curve/HSL clamps carried
    /// for values decoded from untrusted input).
    func clamped(to range: ClosedRange<Self>, fallback: Self) -> Self {
        guard isFinite else { return fallback }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
