import AVFoundation
import Foundation
import MovieCutCore
import Observation

@MainActor
@Observable
final class PlaybackEngine {
    var player: AVPlayer
    var isPlaying: Bool
    var currentTime: TimeInterval
    var duration: TimeInterval
    var playerItem: AVPlayerItem?
    var playbackRate: Float

    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var playbackTimerTask: Task<Void, Never>?

    init() {
        self.player = AVPlayer()
        self.isPlaying = false
        self.currentTime = 0
        self.duration = 0
        self.playerItem = nil
        self.playbackRate = 1
    }

    func load(asset: MediaAsset) {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil

        let avAsset = AVURLAsset(url: asset.originalURL)
        let item = AVPlayerItem(asset: avAsset)

        playerItem = item
        currentTime = 0
        duration = asset.duration ?? 0
        player.replaceCurrentItem(with: item)
        observeStatus(for: item)
    }

    func clear() {
        pause()
        statusObservation?.invalidate()
        statusObservation = nil
        player.replaceCurrentItem(with: nil)
        playerItem = nil
        currentTime = 0
        duration = 0
        playbackRate = 1
    }

    func play() {
        guard playerItem != nil else { return }
        if duration > 0, currentTime >= duration {
            seek(to: 0)
        }
        player.rate = playbackRate
        isPlaying = true
        startPlaybackTimer()
    }

    func pause() {
        player.pause()
        isPlaying = false
        stopPlaybackTimer()
        updateCurrentTimeFromPlayer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func setRate(_ rate: Float) {
        playbackRate = min(max(rate, 0.25), 4.0)
        if isPlaying {
            player.rate = playbackRate
        }
    }

    func seek(to time: TimeInterval) {
        let targetTime: TimeInterval
        if duration > 0 {
            targetTime = min(max(0, time), duration)
        } else {
            targetTime = max(0, time)
        }

        currentTime = targetTime
        let cmTime = CMTime(seconds: targetTime, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func startPlaybackTimer() {
        guard playbackTimerTask == nil else { return }

        playbackTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.updateCurrentTimeFromPlayer()
                try? await Task.sleep(nanoseconds: 33_333_333)
            }
        }
    }

    func stopPlaybackTimer() {
        playbackTimerTask?.cancel()
        playbackTimerTask = nil
    }

    private func observeStatus(for item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handlePlayerItemStatusChanged()
            }
        }
    }

    private func handlePlayerItemStatusChanged() {
        guard let playerItem else {
            duration = 0
            return
        }

        switch playerItem.status {
        case .readyToPlay:
            updateDuration(from: playerItem)
        case .failed, .unknown:
            break
        @unknown default:
            break
        }
    }

    private func updateDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            duration = seconds
        }
    }

    private func updateCurrentTimeFromPlayer() {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }

        currentTime = seconds
        if isPlaying, duration > 0, seconds >= duration {
            pause()
        }
    }
}
