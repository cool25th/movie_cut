import MovieCutCore
import SwiftUI

/// CA-20 stage 2-A (W4): the clip inspector's Role section — tags the
/// selected clips with a role (preset upsert included) or clears the tag.
/// Shown for every clip kind: role tagging is metadata, not per-kind
/// editing.
struct InspectorRoleSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            MovieCutIconTitle(
                title: NSLocalizedString("Role", comment: ""),
                systemImage: "tag"
            )

            // The current value reads through the VIEW MODEL (not the
            // passed clip) so a batch selection shows the shared role —
            // nil renders as "Mixed"/"None" depending on whether any tag
            // exists.
            Menu {
                Button(NSLocalizedString("None", comment: "")) {
                    Task { await viewModel.clearRoleOnSelection() }
                }
                Divider()
                ForEach(availableRoles) { role in
                    Button(role.name) {
                        Task { await viewModel.assignRoleToSelection(role) }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(currentRoleColor)
                    Text(currentRoleLabel)
                        .foregroundStyle(MovieCutTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(MovieCutTheme.mutedText)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("inspector.roleMenu")

            if viewModel.showRoleLanes {
                Text(NSLocalizedString("Role lanes are shown on the timeline.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Role", comment: ""))
    }

    /// Registry roles first (registry order), then any presets not yet
    /// registered — picking an absent preset upserts it via the command.
    private var availableRoles: [TimelineRole] {
        let registered = viewModel.timelineRoles
        let names = Set(registered.map(\.name))
        return registered + TimelineRole.presets.filter { !names.contains($0.name) }
    }

    private var selectedClipsRole: TimelineRole? {
        viewModel.selectedClipsRole
    }

    private var currentRoleLabel: String {
        if let role = selectedClipsRole {
            return role.name
        }
        let anyTagged = !selectedClipIdsWithRole.isEmpty
        return anyTagged
            ? NSLocalizedString("Mixed", comment: "")
            : NSLocalizedString("None", comment: "")
    }

    private var currentRoleColor: Color {
        selectedClipsRole.map { EditorViewModel.roleColor(fromHex: $0.colorHex) }
            ?? MovieCutTheme.mutedText.opacity(0.6)
    }

    private var selectedClipIdsWithRole: Set<UUID> {
        Set(
            viewModel.currentProject.timeline.tracks
                .flatMap(\.clips)
                .filter { viewModel.selectedClipIds.contains($0.id) && $0.roleId != nil }
                .map(\.id)
        )
    }
}
