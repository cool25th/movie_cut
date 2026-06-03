@preconcurrency import AVFoundation
import Combine
import Foundation

/// Minimal export engine interface kept for clients that still abstract export execution.
public protocol ExportEngine: Sendable {
    /// Exports using the supplied settings and returns the written file URL.
    func export(settings: ExportSettings) async throws -> URL
}

/// Observable export progress state backed by an `AVAssetExportSession`.
@MainActor
public final class ExportProgress: ObservableObject, Sendable {
    /// Export lifecycle state.
    public enum ExportState: Sendable {
        case idle
        case exporting
        case completed
        case cancelled
        case failed(Error)
    }

    /// Progress from 0.0 to 1.0.
    @Published public private(set) var progress: Double

    /// Current export state.
    @Published public private(set) var state: ExportState

    private var exportSession: AVAssetExportSession?
    private var progressTask: Task<Void, Never>?

    /// Creates an export progress tracker.
    public init(progress: Double = 0, state: ExportState = .idle) {
        self.progress = Self.clamped(progress)
        self.state = state
    }

    deinit {
        progressTask?.cancel()
    }

    /// Starts observing an export session's real progress.
    public func start(session: AVAssetExportSession) {
        progressTask?.cancel()
        exportSession = session
        progress = Self.clamped(Double(session.progress))
        state = .exporting

        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.update(from: session) == false else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    /// Cancels the tracked export session.
    public func cancel() {
        progressTask?.cancel()
        progressTask = nil
        exportSession?.cancelExport()
        exportSession = nil
        state = .cancelled
    }

    @discardableResult
    private func update(from session: AVAssetExportSession) -> Bool {
        progress = Self.clamped(Double(session.progress))

        switch session.status {
        case .completed:
            progress = 1
            state = .completed
            stopTracking()
            return true
        case .failed:
            state = .failed(session.error ?? ExportProgressError.failedWithoutError)
            stopTracking()
            return true
        case .cancelled:
            state = .cancelled
            stopTracking()
            return true
        default:
            return false
        }
    }

    private func stopTracking() {
        progressTask?.cancel()
        progressTask = nil
        exportSession = nil
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private enum ExportProgressError: LocalizedError, Sendable {
    case failedWithoutError

    var errorDescription: String? {
        switch self {
        case .failedWithoutError:
            return "The export failed without an AVAssetExportSession error."
        }
    }
}
