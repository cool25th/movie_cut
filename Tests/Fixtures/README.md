# Test media fixtures (Phase 0.1a)

Tiny, deterministic media used by behavioral / golden / E2E tests so they do not
depend on `ffmpeg` at run time. Resolved in tests via `MediaFixtures`
(`Tests/MovieCutCoreTests/Support/MediaFixtures.swift`).

| File | Properties | Used for |
|---|---|---|
| `solid_red_320x240_2s_30fps.mp4` | h264, 320×240, 30fps, 2.0s | video import / metadata probe / timeline clip |
| `solid_red_tone_320x240_2s_30fps.mp4` | h264+aac, 320×240, 30fps, 44100Hz mono, 2.0s | extract-audio E2E |
| `bars_320x240_3s_30fps.mp4` | h264, 320×240, 30fps, 3.0s | distinguishable second video clip |
| `moving_subject_320x240_2s_30fps.mp4` | h264, 320×240, 30fps, 2.0s | Vision motion tracking IoU verification |
| `tone_440hz_2s_mono.wav` | pcm_s16le, 44100Hz, mono, 2.0s | audio import / ducking / beat analysis |
| `swatch_blue_64x64.png` | PNG, 64×64 | image import |
| `cg_codable_parity.moviecut` | project JSON with mask + brushPoints, text clip + shadowOffset, card document | CGPoint/CGSize persistence parity — locks the on-disk array form (`[x, y]`) produced by CoreGraphics' native Codable across conformance changes |
| `timeline_accessibility_bootstrap.moviecut` | project JSON, no card document, fixed track UUIDs: video `Video 1`, video `Video 2`, audio `Audio 1`, zero clips | `MOVIECUT_BOOTSTRAP_PROJECT` source for `TimelineAccessibilityLabelUITests`. Two video tracks so the non-first video track reaches the generic track-header accessibility label; fixed UUIDs let the test address one specific lane instead of relying on ordering |
| `timeline_localization_bootstrap.moviecut` | project JSON, no card document, fixed track UUIDs: video `Video 1` (1 clip), video `Video 2` (empty), audio `Audio 1` (1 clip), text `Text 1` (1 clip), one standard + one beat marker, no media assets | `MOVIECUT_BOOTSTRAP_PROJECT` source for `LocalizedAccessibilityLabelUITests`. Clips are present but reference no asset, which is enough to publish clip, trim-handle, and marker accessibility labels — the elements requirement 1 cites — without baking machine-specific media paths into the fixture. All strings are ASCII so any Hangul the sweep finds comes from the app's localization, not from project data |

## Regenerating

Only when intentionally changing the fixtures:

```bash
bash scripts/make_fixtures.sh
```

Property check:

```bash
ffprobe -v error -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels \
  -show_entries format=duration -of default=noprint_wrappers=1 Tests/Fixtures/solid_red_320x240_2s_30fps.mp4
```
