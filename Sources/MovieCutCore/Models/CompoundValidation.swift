import Foundation

/// Errors raised by compound-clip structural validation (Requirement 7).
///
/// Inc 1 forbids nesting and requires every container reference to resolve.
/// These are surfaced at **load time** (after decode + migration) so a corrupt
/// or hand-edited file produces an explicit, localizable error instead of a
/// half-rendered timeline or a silent drop. Creation-time rejection happens
/// inside `CreateCompoundClipCommand` via `EditorCommandError.invalidCommand`.
public enum CompoundValidationError: Error, LocalizedError, Sendable, Equatable {
    /// A clip carried a `compoundId`, but no matching `CompoundDefinition`
    /// exists in `Project.compounds`. The file is inconsistent.
    case danglingCompoundReference(clipId: UUID, compoundId: UUID)

    /// A child clip inside a compound definition itself carries a `compoundId`.
    /// Inc 1 forbids nesting (Requirement 7.3 is explicitly deferred), and the
    /// flatten pass is non-recursive, so this is a hard error rather than a
    /// silent truncation.
    case nestedCompoundForbidden(parentCompoundId: UUID, childClipId: UUID)

    public var errorDescription: String? {
        switch self {
        case let .danglingCompoundReference(clipId, compoundId):
            return """
            This project is damaged: a clip (\(clipId)) references a compound \
            clip (\(compoundId)) that no longer exists in the project.
            """
        case let .nestedCompoundForbidden(parentCompoundId, childClipId):
            return """
            This project is damaged: a compound clip (\(parentCompoundId)) \
            contains another compound clip (\(childClipId)). Nested compound \
            clips are not supported.
            """
        }
    }
}

extension Project {
    /// Validates the compound-clip structure of this project, enforcing the
    /// Inc 1 invariants:
    ///
    /// 1. **No dangling references** — every clip (container or otherwise) that
    ///    carries a `compoundId` must resolve to an entry in `compounds`.
    /// 2. **No nesting** — no clip listed as a child of a compound may itself
    ///    carry a `compoundId`.
    ///
    /// Called at load time by `ProjectStore.load` *after* decode and schema
    /// migration, so a structurally broken file is rejected explicitly rather
    /// than rendered half-flat. Creation-time enforcement lives in
    /// `CreateCompoundClipCommand` and `validateCompoundChild`.
    ///
    /// - Throws: `CompoundValidationError` on the first violation found.
    public func validateCompounds() throws {
        let knownCompoundIds = Set(compounds.map(\.id))

        // 1. No dangling references: every container clip must point at a real
        //    definition. This also catches a stray compoundId on a plain clip.
        for track in timeline.tracks {
            for clip in track.clips {
                if let compoundId = clip.compoundId, !knownCompoundIds.contains(compoundId) {
                    throw CompoundValidationError.danglingCompoundReference(
                        clipId: clip.id,
                        compoundId: compoundId
                    )
                }
            }
        }

        // 2. No nesting: children inside a compound definition may not be
        //    containers themselves. The flatten pass is single-level by
        //    construction, so this guard is structural, not advisory.
        for compound in compounds {
            for child in compound.childClips {
                if child.compoundId != nil {
                    throw CompoundValidationError.nestedCompoundForbidden(
                        parentCompoundId: compound.id,
                        childClipId: child.id
                    )
                }
            }
        }
    }
}
