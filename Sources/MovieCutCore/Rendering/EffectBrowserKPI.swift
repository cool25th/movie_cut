import Foundation

/// G-28 — the effect browser's KPI measurement: search success rate and
/// reuse rate. The plan explicitly replaces count-based KPIs ("개수 KPI
/// 폐지") with these behavioral metrics.
///
/// - **Search success rate**: of all searches performed, how many led to
///   an effect application? (A search that finds nothing is a failure —
///   either the query is bad or the tag coverage is incomplete.)
/// - **Reuse rate**: of all effect applications, how many applied an
///   effect the same project had already used before? (High reuse =
///   the browser surfaces what users actually want again.)
public struct EffectBrowserKPI: Codable, Sendable, Equatable {
    public var totalSearches: Int
    public var searchesLeadingToApply: Int
    public var totalApplies: Int
    public var reApplies: Int

    public init(
        totalSearches: Int = 0,
        searchesLeadingToApply: Int = 0,
        totalApplies: Int = 0,
        reApplies: Int = 0
    ) {
        self.totalSearches = totalSearches
        self.searchesLeadingToApply = searchesLeadingToApply
        self.totalApplies = totalApplies
        self.reApplies = reApplies
    }

    /// 0…1 — the fraction of searches that resulted in an apply.
    public var searchSuccessRate: Double {
        guard totalSearches > 0 else { return 0 }
        return Double(searchesLeadingToApply) / Double(totalSearches)
    }

    /// 0…1 — the fraction of applies that re-used a previously applied effect.
    public var reuseRate: Double {
        guard totalApplies > 0 else { return 0 }
        return Double(reApplies) / Double(totalApplies)
    }

    /// The plan's KPI targets as a single predicate.
    public func meetsTargets(minSearchSuccess: Double = 0.6, minReuse: Double = 0.2) -> Bool {
        searchSuccessRate >= minSearchSuccess && reuseRate >= minReuse
    }

    /// Records a search query. Call once per search action.
    public mutating func recordSearch() {
        totalSearches += 1
    }

    /// Records that the current search led to an apply.
    public mutating func recordSearchLedToApply() {
        searchesLeadingToApply += 1
    }

    /// Records an effect application. `isReApply` is true when the
    /// project already had this effect type applied.
    public mutating func recordApply(isReApply: Bool) {
        totalApplies += 1
        if isReApply {
            reApplies += 1
        }
    }

    /// A human-readable summary line.
    public var summary: String {
        String(
            format: "searches=%d success=%.0f%% applies=%d reuse=%.0f%%",
            totalSearches, searchSuccessRate * 100, totalApplies, reuseRate * 100
        )
    }
}
