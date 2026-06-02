import Combine
import Foundation

/// Minimal export engine interface used by `ExportProgress`.
public protocol ExportEngine: Sendable {
    /// Exports using the supplied settings and returns the written file URL.
    func export(settings: ExportSettings) async throws -> URL
}

/// Observable export progress state.
public final class ExportProgress: ObservableObject, @unchecked Sendable {
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

    private let lock = NSLock()
    private var isCancelled = false
    private var exportTask: Task<URL, Error>?
    private var progressTask: Task<Void, Never>?

    /// Creates an export progress tracker.
    public init(progress: Double = 0, state: ExportState = .idle) {
        self.progress = min(max(progress, 0), 1)
        self.state = state
    }

    deinit {
        exportTask?.cancel()
        progressTask?.cancel()
    }

    /// Starts an export and periodically advances progress until the engine completes.
    public func start(exportEngine: any ExportEngine, settings: ExportSettings) async throws -> URL {
        setCancelled(false)
        progressTask?.cancel()
        progress = 0
        state = .exporting

        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard !self.cancelled else { return }

                await self.advanceProgress()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        do {
            try Task.checkCancellation()
            guard !cancelled else {
                throw CancellationError()
            }

            let task = Task {
                try Task.checkCancellation()
                return try await exportEngine.export(settings: settings)
            }
            exportTask = task

            let url = try await task.value

            try Task.checkCancellation()
            guard !cancelled else {
                throw CancellationError()
            }

            exportTask = nil
            progressTask?.cancel()
            progressTask = nil
            progress = 1
            state = .completed
            return url
        } catch is CancellationError {
            exportTask?.cancel()
            exportTask = nil
            progressTask?.cancel()
            progressTask = nil
            state = .cancelled
            throw CancellationError()
        } catch {
            exportTask = nil
            progressTask?.cancel()
            progressTask = nil
            state = .failed(error)
            throw error
        }
    }

    /// Cancels the tracked export.
    public func cancel() {
        setCancelled(true)
        exportTask?.cancel()
        exportTask = nil
        progressTask?.cancel()
        progressTask = nil
        state = .cancelled
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func setCancelled(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = value
    }

    private func advanceProgress() async {
        guard !cancelled, stateIsExporting else { return }
        progress = min(progress + 0.02, 0.95)
    }

    private var stateIsExporting: Bool {
        if case .exporting = state {
            return true
        }
        return false
    }
}
