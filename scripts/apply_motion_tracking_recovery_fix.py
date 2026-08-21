from pathlib import Path
import re

provider_path = Path("Sources/MovieCutCore/Analysis/MotionTrackingProvider.swift")
provider = provider_path.read_text()

old_doc = '    /// Evaluates a Vision or local-redetection candidate for `timestamp`.\n'
new_doc = '''    /// Evaluates a candidate for `timestamp`.
    ///
    /// Normal Vision observations must remain motion-consistent with the trusted
    /// trajectory. During recovery the provider may instead supply an
    /// appearance-verified redetection; that stronger evidence is allowed to
    /// re-anchor tracking even when the old trajectory prediction has drifted.
'''
if old_doc not in provider:
    raise SystemExit("provider evaluate doc anchor not found")
provider = provider.replace(old_doc, new_doc, 1)

old_signature = '''        timestamp: TimeInterval,
        candidateRect: CGRect?,
        confidence: Float?
    ) -> Decision {'''
new_signature = '''        timestamp: TimeInterval,
        candidateRect: CGRect?,
        confidence: Float?,
        appearanceVerified: Bool = false
    ) -> Decision {'''
if old_signature not in provider:
    raise SystemExit("provider evaluate signature anchor not found")
provider = provider.replace(old_signature, new_signature, 1)

old_gate = '''        if hasVelocityEstimate {
            let predictionIoU = Self.intersectionOverUnion(candidate, predicted)'''
new_gate = '''        let canReanchorFromAppearance = wasRecovering && appearanceVerified
        if hasVelocityEstimate && !canReanchorFromAppearance {
            let predictionIoU = Self.intersectionOverUnion(candidate, predicted)'''
if old_gate not in provider:
    raise SystemExit("trajectory gate anchor not found")
provider = provider.replace(old_gate, new_gate, 1)

old_call = '''            let decision = planner.evaluate(
                timestamp: timestamp,
                candidateRect: candidateRect,
                confidence: candidateConfidence
            )'''
new_call = '''            let decision = planner.evaluate(
                timestamp: timestamp,
                candidateRect: candidateRect,
                confidence: candidateConfidence,
                appearanceVerified: usedTemplateRedetection
            )'''
if old_call not in provider:
    raise SystemExit("provider evaluate call anchor not found")
provider = provider.replace(old_call, new_call, 1)
provider_path.write_text(provider)

matcher_path = Path("Sources/MovieCutCore/Analysis/MotionTrackingTemplateMatcher.swift")
matcher = matcher_path.read_text()
replacement = r'''    func bestMatch(in image: CGImage, around predictedRect: CGRect) -> Match? {
        guard let frame = Self.grayscale(image, width: frameWidth, height: frameHeight),
              templatePixels.count == templateWidth * templateHeight,
              templateWidth <= frameWidth,
              templateHeight <= frameHeight
        else {
            return nil
        }

        let predictedPixelRect = Self.pixelRect(
            for: predictedRect,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            forcedWidth: templateWidth,
            forcedHeight: templateHeight
        )
        let maxX = frameWidth - templateWidth
        let maxY = frameHeight - templateHeight
        let normalization = Double(255 * templatePixels.count)

        func score(atX x: Int, y: Int) -> Double {
            var absoluteDifference = 0
            for templateY in 0..<templateHeight {
                let templateBase = templateY * templateWidth
                let frameBase = (y + templateY) * frameWidth + x
                for templateX in 0..<templateWidth {
                    absoluteDifference += abs(
                        Int(templatePixels[templateBase + templateX]) -
                            Int(frame[frameBase + templateX])
                    )
                }
            }
            return 1 - (Double(absoluteDifference) / normalization)
        }

        func scan(
            minX: Int,
            maxX: Int,
            minY: Int,
            maxY: Int,
            step: Int
        ) -> (score: Double, x: Int, y: Int)? {
            guard minX <= maxX, minY <= maxY else { return nil }
            var bestScore = -Double.infinity
            var bestX = minX
            var bestY = minY
            var y = minY
            while y <= maxY {
                var x = minX
                while x <= maxX {
                    let candidateScore = score(atX: x, y: y)
                    if candidateScore > bestScore {
                        bestScore = candidateScore
                        bestX = x
                        bestY = y
                    }
                    x += step
                }
                y += step
            }
            return (bestScore, bestX, bestY)
        }

        let radiusX = max(Int((CGFloat(frameWidth) * 0.30).rounded()), templateWidth / 2)
        let radiusY = max(Int((CGFloat(frameHeight) * 0.20).rounded()), templateHeight / 2)
        let localMinX = max(0, predictedPixelRect.x - radiusX)
        let localMaxX = min(maxX, predictedPixelRect.x + radiusX)
        let localMinY = max(0, predictedPixelRect.y - radiusY)
        let localMaxY = min(maxY, predictedPixelRect.y + radiusY)

        if let local = scan(
            minX: localMinX,
            maxX: localMaxX,
            minY: localMinY,
            maxY: localMaxY,
            step: 2
        ), local.score >= minimumScore {
            return Match(
                rect: Self.normalizedDisplayRect(
                    x: local.x,
                    y: local.y,
                    width: templateWidth,
                    height: templateHeight,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight
                ),
                score: local.score
            )
        }

        // Full occlusion can make the motion prediction stale. Search the
        // already-downsampled frame coarsely, then refine the best candidate.
        guard let coarse = scan(minX: 0, maxX: maxX, minY: 0, maxY: maxY, step: 4) else {
            return nil
        }
        let refineRadius = 4
        let refined = scan(
            minX: max(0, coarse.x - refineRadius),
            maxX: min(maxX, coarse.x + refineRadius),
            minY: max(0, coarse.y - refineRadius),
            maxY: min(maxY, coarse.y + refineRadius),
            step: 1
        ) ?? coarse

        guard refined.score >= minimumScore else { return nil }
        return Match(
            rect: Self.normalizedDisplayRect(
                x: refined.x,
                y: refined.y,
                width: templateWidth,
                height: templateHeight,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            ),
            score: refined.score
        )
    }

'''
pattern = re.compile(
    r'    func bestMatch\(in image: CGImage, around predictedRect: CGRect\) -> Match\? \{.*?\n    \}\n\n(?=    private static func downsampledDimensions)',
    re.S,
)
matcher, count = pattern.subn(replacement, matcher, count=1)
if count != 1:
    raise SystemExit(f"matcher bestMatch replacement count={count}")
matcher_path.write_text(matcher)

tests_path = Path("Tests/MovieCutCoreTests/MotionTrackingProviderTests.swift")
tests = tests_path.read_text()
anchor = '''    @Test("confident but motion-inconsistent candidate is not emitted as trusted")
    func inconsistentCandidateReseeds() {'''
inserted = '''    @Test("appearance-verified recovery can re-anchor outside a stale trajectory")
    func appearanceVerifiedRecoveryCanReanchor() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)
        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )
        _ = planner.evaluate(timestamp: 0.2, candidateRect: nil, confidence: nil)

        let unverified = planner.evaluate(
            timestamp: 0.8,
            candidateRect: CGRect(x: 0.55, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95
        )
        guard case .reseed(_, let reason) = unverified else {
            Issue.record("trajectory-distant unverified candidate should stay rejected")
            return
        }
        #expect(reason == .motionInconsistent)

        let verified = planner.evaluate(
            timestamp: 0.8,
            candidateRect: CGRect(x: 0.55, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95,
            appearanceVerified: true
        )
        guard case .accept(let result, let reacquired) = verified else {
            Issue.record("appearance-verified candidate should re-anchor recovery")
            return
        }
        #expect(reacquired)
        #expect(abs(result.rect.minX - 0.55) < 0.0001)
        #expect(!planner.isRecovering)
    }

''' + anchor
if anchor not in tests:
    raise SystemExit("test insertion anchor not found")
tests = tests.replace(anchor, inserted, 1)
tests_path.write_text(tests)
