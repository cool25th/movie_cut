import MovieCutCore
import SwiftUI

/// CA-20 stage 2-A (W4): the Mac UI's role actions — assignment from the
/// clip inspector, preset-registry upsert, and the lane-dominance math the
/// timeline's role lane tint reads. All mutations funnel through the Core
/// commands (`AddTimelineRoleCommand`, `SetClipRoleCommand`), so registry
/// integrity and undo snapshots are the commands' contract, not this
/// layer's.
extension EditorViewModel {
    /// The project's role registry, registry order preserved.
    var timelineRoles: [TimelineRole] {
        currentProject.roles
    }

    /// The role a lane's tint shows: the most frequent role among the
    /// track's TAGGED clips. Ties break by registry order (deterministic —
    /// a coin-flip tint that changes per render is the BUG-ACC-04 class).
    func dominantRole(for track: Track) -> TimelineRole? {
        let counts = track.clips.reduce(into: [UUID: Int]()) { acc, clip in
            guard let roleId = clip.roleId else { return }
            acc[roleId, default: 0] += 1
        }
        guard !counts.isEmpty else { return nil }
        let registryOrder = Dictionary(uniqueKeysWithValues: currentProject.roles.enumerated().map { ($1.id, $0) })
        var best: (id: UUID, count: Int, order: Int)?
        for (roleId, count) in counts {
            guard let order = registryOrder[roleId] else { continue }
            if let current = best {
                if count > current.count || (count == current.count && order < current.order) {
                    best = (roleId, count, order)
                }
            } else {
                best = (roleId, count, order)
            }
        }
        guard let best else { return nil }
        return currentProject.roles.first { $0.id == best.id }
    }

    /// Parses "#RRGGBB" into a Color (black on any malformed input — the
    /// presets are Core data, a bad tint must never crash the timeline).
    static func roleColor(fromHex hex: String) -> Color {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        var value: UInt64 = 0
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6,
              digits.allSatisfy({ $0.isHexDigit }),
              Scanner(string: digits).scanHexInt64(&value) else {
            return .black
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }

    /// Upserts a preset role into the registry (name match reuses the
    /// existing entry — re-adding "Music" must not error or duplicate) and
    /// returns the registry entry to reference.
    private func ensureRole(_ preset: TimelineRole) async throws -> TimelineRole {
        if let existing = currentProject.roles.first(where: { $0.name == preset.name }) {
            return existing
        }
        try await session.dispatch(AddTimelineRoleCommand(role: preset))
        try await refreshFromSession()
        return currentProject.roles.first { $0.name == preset.name } ?? preset
    }

    /// Tags the given clips with a preset role (registry upsert first).
    func assignRole(_ preset: TimelineRole, to clipIds: [UUID]) async {
        guard !clipIds.isEmpty else { return }
        do {
            let role = try await ensureRole(preset)
            try await session.dispatch(SetClipRoleCommand(clipIds: clipIds, roleId: role.id))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = String(
                format: NSLocalizedString("Tagged %d clips as %@", comment: ""),
                clipIds.count, role.name
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Clears the role tag from the given clips.
    func clearRole(from clipIds: [UUID]) async {
        guard !clipIds.isEmpty else { return }
        do {
            try await session.dispatch(SetClipRoleCommand(clipIds: clipIds, roleId: nil))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = NSLocalizedString("Cleared role tags", comment: "")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// The selected clips' shared role, or nil when none or mixed — drives
    /// the inspector section's current value.
    var selectedClipsRole: TimelineRole? {
        let tagged = Set(
            currentProject.timeline.tracks
                .flatMap(\.clips)
                .filter { selectedClipIds.contains($0.id) }
                .compactMap(\.roleId)
        )
        guard tagged.count == 1, let id = tagged.first else { return nil }
        return currentProject.roles.first { $0.id == id }
    }

    /// Convenience for the inspector section: act on the selection.
    func assignRoleToSelection(_ preset: TimelineRole) async {
        await assignRole(preset, to: Array(selectedClipIds))
    }

    func clearRoleOnSelection() async {
        await clearRole(from: Array(selectedClipIds))
    }
}
