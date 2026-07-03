# Test media fixtures (Phase 0.1a)

Tiny, deterministic media used by behavioral / golden / E2E tests so they do not
depend on `ffmpeg` at run time. Resolved in tests via `MediaFixtures`
(`Tests/MovieCutCoreTests/Support/MediaFixtures.swift`).

| File | Properties | Used for |
|---|---|---|
| `solid_red_320x240_2s_30fps.mp4` | h264, 320×240, 30fps, 2.0s | video import / metadata probe / timeline clip |
| `bars_320x240_3s_30fps.mp4` | h264, 320×240, 30fps, 3.0s | distinguishable second video clip |
| `moving_subject_320x240_2s_30fps.mp4` | h264, 320×240, 30fps, 2.0s | Vision motion tracking IoU verification |
| `tone_440hz_2s_mono.wav` | pcm_s16le, 44100Hz, mono, 2.0s | audio import / ducking / beat analysis |
| `swatch_blue_64x64.png` | PNG, 64×64 | image import |

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
