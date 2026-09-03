import Foundation

/// CA-25 onboarding instrumentation (SC-C1 style, fully local — no network,
/// no upload; values live in the app container's defaults and are readable
/// via `summary()` when a beta tester reports back).
///
/// Records FIRST-time-only timestamps:
///  - firstLaunch    — the first home render of this install
///  - onboardingShown — the welcome card was composed for the user
///  - sampleOpened   — the bundled sample project was opened
///  - firstImport    — a media import completed at least once
///  - firstExport    — an export finished successfully at least once
///  - quickToolsUsed — a timeline Quick Tools action was invoked
///
/// "First export within 10 minutes" (the CA-25 target) is
/// `minutesToFirstExport` = firstExport − firstLaunch.
final class OnboardingMetrics {
    enum Event: String, CaseIterable {
        case firstLaunch = "onboarding.metrics.firstLaunch"
        case onboardingShown = "onboarding.metrics.onboardingShown"
        case sampleOpened = "onboarding.metrics.sampleOpened"
        case firstImport = "onboarding.metrics.firstImport"
        case firstExport = "onboarding.metrics.firstExport"
        case quickToolsUsed = "onboarding.metrics.quickToolsUsed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The welcome card is dismissed (sample opened or skipped); once set it
    /// never shows again on this install.
    var isDismissed: Bool {
        get { defaults.bool(forKey: "onboarding.dismissed") }
        set { defaults.set(newValue, forKey: "onboarding.dismissed") }
    }

    /// Records the event's timestamp unless one already exists (first-only).
    /// Returns whether this call was the one that recorded it.
    @discardableResult
    func record(_ event: Event, at date: Date = Date()) -> Bool {
        guard defaults.object(forKey: event.rawValue) == nil else { return false }
        defaults.set(date, forKey: event.rawValue)
        return true
    }

    func timestamp(for event: Event) -> Date? {
        defaults.object(forKey: event.rawValue) as? Date
    }

    /// Minutes from first launch to first successful export, when both exist —
    /// the "first output ≤ 10 minutes" target number for the beta metric sheet.
    var minutesToFirstExport: Double? {
        guard let start = timestamp(for: .firstLaunch),
              let end = timestamp(for: .firstExport) else { return nil }
        return end.timeIntervalSince(start) / 60
    }

    /// One-line, local-only report for beta feedback.
    var summary: String {
        let parts = Event.allCases.compactMap { event -> String? in
            guard let date = timestamp(for: event) else { return nil }
            let name = event.rawValue.components(separatedBy: ".").last ?? event.rawValue
            return "\(name)=\(Int(date.timeIntervalSince1970))"
        }
        var line = parts.joined(separator: " ")
        if let minutes = minutesToFirstExport {
            line += " minutesToFirstExport=\(String(format: "%.1f", minutes))"
        }
        return line.isEmpty ? "onboarding: no events" : "onboarding: \(line)"
    }
}
