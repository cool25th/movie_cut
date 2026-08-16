import Foundation
import Testing
@testable import MovieCutCore

@Suite("Compound Navigation & Nested Editing Tests (Inc 2)")
struct CompoundNavigationTests {
    @Test("TimelineBreadcrumb correctly reflects root and compound trail")
    func breadcrumbsTrail() {
        let root = TimelineBreadcrumb.root(projectName: "My Project")
        #expect(root.isRoot == true)
        #expect(root.title == "My Project")

        let compoundId = UUID()
        let compoundCrumb = TimelineBreadcrumb.compound(id: compoundId, name: "Intro Sequence")
        #expect(compoundCrumb.isRoot == false)
        #expect(compoundCrumb.title == "Intro Sequence")
        #expect(compoundCrumb.context == .compound(id: compoundId, name: "Intro Sequence"))
    }

    @Test("CompoundTimelineConverter builds virtual timeline and extracts child clips")
    func virtualTimelineConversion() {
        let child1 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let child2 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 4, duration: 3)
        )
        let audioChild = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 7),
            timelineRange: TimeRange(start: 0, duration: 7)
        )

        let compound = CompoundDefinition(
            name: "Nested Unit",
            childClips: [child1, child2, audioChild]
        )

        let virtualTimeline = CompoundTimelineConverter.makeVirtualTimeline(from: compound, frameRate: Rational(numerator: 30, denominator: 1))
        #expect(virtualTimeline.tracks.count == 2)
        #expect(virtualTimeline.tracks.first?.kind == .video)
        #expect(virtualTimeline.tracks.first?.clips.count == 2)
        #expect(virtualTimeline.tracks.last?.kind == .audio)
        #expect(virtualTimeline.tracks.last?.clips.count == 1)

        let extracted = CompoundTimelineConverter.extractChildClips(from: virtualTimeline)
        #expect(extracted.count == 3)
    }

    @Test("UpdateCompoundChildrenCommand updates definition, container duration and supports undo")
    func updateCompoundChildrenCommand() throws {
        let compoundId = UUID()
        let child1 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 0, duration: 3)
        )
        let initialCompound = CompoundDefinition(
            id: compoundId,
            name: "Comp 1",
            childClips: [child1]
        )

        let containerClip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 2, duration: 3),
            compoundId: compoundId
        )
        let track = Track(kind: .video, name: "Video Track", clips: [containerClip])
        var project = Project(
            name: "Test Project",
            timeline: Timeline(tracks: [track]),
            compounds: [initialCompound]
        )

        let updatedChild1 = Clip(
            id: child1.id,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        let newChild2 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 5, duration: 2)
        )
        let newChildren = [updatedChild1, newChild2]

        let command = UpdateCompoundChildrenCommand(
            compoundId: compoundId,
            newChildClips: newChildren,
            oldChildClips: [child1]
        )

        try command.apply(to: &project)
        #expect(project.compounds.first?.childClips.count == 2)

        // Container clip duration should expand to 7 (5 + 2)
        let updatedContainer = project.timeline.tracks.first?.clips.first
        #expect(updatedContainer?.sourceRange.duration == 7.0)
        #expect(updatedContainer?.timelineRange.duration == 7.0)

        // Test undo (invert)
        let invertCmd = command.invert(from: project)
        try invertCmd.apply(to: &project)
        #expect(project.compounds.first?.childClips.count == 1)
        #expect(project.timeline.tracks.first?.clips.first?.sourceRange.duration == 3.0)
    }
}
