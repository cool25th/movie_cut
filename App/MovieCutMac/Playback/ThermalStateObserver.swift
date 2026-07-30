import Foundation
import MovieCutCore

/// Observes the system thermal state and reports transitions, so PlaybackEngine
/// can auto-downgrade to proxy preview under serious/critical pressure. (S7)
///
/// Wraps `ProcessInfo.processInfo.thermalState` + the
/// `ProcessInfo.thermalStateDidChangeNotification` so the rest of the app talks
/// to a `ThermalState` value (Core, testable) rather than the framework enum.
@MainActor
final class ThermalStateObserver {
    /// Called on the main actor whenever the thermal state changes, with the
    /// new value.
    var onChange: ((ThermalState) -> Void)?

    // nonisolated(unsafe): only touched on the main actor (start) and freed in
    // deinit (NotificationCenter.removeObserver is thread-safe).
    private nonisolated(unsafe) var observer: NSObjectProtocol?

    /// The current thermal state, mapped from `ProcessInfo`.
    var current: ThermalState {
        Self.map(ProcessInfo.processInfo.thermalState)
    }

    /// Maps the framework thermal-state enum to the Core `ThermalState`.
    static func map(_ raw: ProcessInfo.ThermalState) -> ThermalState {
        switch raw {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    init() {}

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts listening for thermal-state changes. Safe to call once.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.onChange?(self.current) }
        }
    }
}
