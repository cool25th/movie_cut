#!/usr/bin/env python3
"""Generate MovieCut's bundled SFX WAV files.

The sounds are intentionally synthetic, compact, and deterministic so they can
be regenerated without storing source project files.
"""

from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


SAMPLE_RATE = 44_100
OUTPUT_DIR = Path(__file__).resolve().parents[1] / "App" / "MovieCutMac" / "Resources" / "SFX"
RNG = np.random.default_rng(20260604)


def time_axis(duration: float) -> np.ndarray:
    return np.arange(int(SAMPLE_RATE * duration), dtype=np.float64) / SAMPLE_RATE


def fade(signal: np.ndarray, fade_in: float = 0.006, fade_out: float = 0.03) -> np.ndarray:
    out = signal.copy()
    in_count = min(len(out), int(SAMPLE_RATE * fade_in))
    out_count = min(len(out), int(SAMPLE_RATE * fade_out))
    if in_count > 0:
        out[:in_count] *= np.linspace(0.0, 1.0, in_count)
    if out_count > 0:
        out[-out_count:] *= np.linspace(1.0, 0.0, out_count)
    return out


def normalize(signal: np.ndarray, peak: float = 0.92) -> np.ndarray:
    max_amp = float(np.max(np.abs(signal))) if len(signal) else 0.0
    if max_amp <= 1e-9:
        return signal
    return np.clip(signal / max_amp * peak, -1.0, 1.0)


def write_wav(path: Path, signal: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (normalize(signal) * np.iinfo(np.int16).max).astype(np.int16)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        wav_file.writeframes(pcm.tobytes())


def frequency_glide(duration: float, start_hz: float, end_hz: float) -> np.ndarray:
    t = time_axis(duration)
    progress = np.linspace(0.0, 1.0, len(t))
    return start_hz * (end_hz / start_hz) ** progress


def sine_from_frequency(frequency: np.ndarray) -> np.ndarray:
    phase = 2.0 * np.pi * np.cumsum(frequency) / SAMPLE_RATE
    return np.sin(phase)


def one_pole_lowpass(signal: np.ndarray, cutoff_hz: float) -> np.ndarray:
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    out = np.zeros_like(signal)
    for index, value in enumerate(signal):
        out[index] = out[index - 1] + alpha * (value - out[index - 1]) if index else alpha * value
    return out


def bandpass_noise_sweep(duration: float, start_hz: float, end_hz: float, q: float, energy: float) -> np.ndarray:
    noise = RNG.normal(0.0, 1.0, int(SAMPLE_RATE * duration))
    frequencies = frequency_glide(duration, start_hz, end_hz)
    out = np.zeros_like(noise)
    x1 = x2 = y1 = y2 = 0.0

    for index, sample in enumerate(noise):
        omega = 2.0 * math.pi * frequencies[index] / SAMPLE_RATE
        alpha = math.sin(omega) / (2.0 * q)
        cos_omega = math.cos(omega)
        a0 = 1.0 + alpha
        b0 = alpha / a0
        b1 = 0.0
        b2 = -alpha / a0
        a1 = -2.0 * cos_omega / a0
        a2 = (1.0 - alpha) / a0

        y0 = b0 * sample + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[index] = y0
        x2 = x1
        x1 = sample
        y2 = y1
        y1 = y0

    t = time_axis(duration)
    envelope = np.sin(np.pi * np.linspace(0.0, 1.0, len(out))) ** energy
    airy = one_pole_lowpass(RNG.normal(0.0, 0.35, len(out)), cutoff_hz=end_hz * 0.7)
    return fade((out * 0.9 + airy * 0.1) * envelope, fade_in=0.02, fade_out=0.08)


def impulse_click(duration: float, impulses: list[tuple[float, float]], tone_hz: float, noise_decay: float) -> np.ndarray:
    t = time_axis(duration)
    signal = np.zeros_like(t)
    for position, amplitude in impulses:
        index = min(len(signal) - 1, int(position * SAMPLE_RATE))
        signal[index] += amplitude

    noise = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t / noise_decay)
    ring = np.sin(2.0 * np.pi * tone_hz * t) * np.exp(-t / (noise_decay * 1.4))
    signal += noise * 0.34 + ring * 0.24
    return fade(np.tanh(signal * 1.7), fade_in=0.001, fade_out=0.08)


def sine_burst(duration: float, start_hz: float, end_hz: float, decay: float, body: float) -> np.ndarray:
    t = time_axis(duration)
    tone = sine_from_frequency(frequency_glide(duration, start_hz, end_hz))
    attack = np.minimum(1.0, t / 0.004)
    envelope = attack * np.exp(-t / decay)
    air = RNG.normal(0.0, 0.025, len(t)) * np.exp(-t / (decay * 0.7))
    return fade((tone * body + air) * envelope, fade_in=0.001, fade_out=0.08)


def harmonic_ding(duration: float, base_hz: float, harmonics: list[tuple[float, float, float]]) -> np.ndarray:
    t = time_axis(duration)
    signal = np.zeros_like(t)
    for multiplier, amplitude, decay in harmonics:
        frequency = base_hz * multiplier
        detune = 1.0 + 0.0015 * math.sin(multiplier)
        signal += amplitude * np.sin(2.0 * np.pi * frequency * detune * t) * np.exp(-t / decay)

    attack = np.minimum(1.0, t / 0.01)
    shimmer = one_pole_lowpass(RNG.normal(0.0, 0.01, len(t)), cutoff_hz=7_000.0) * np.exp(-t / 0.5)
    return fade((signal + shimmer) * attack, fade_in=0.002, fade_out=0.15)


def low_boom(duration: float, start_hz: float, end_hz: float, noise_amount: float, snap: float) -> np.ndarray:
    t = time_axis(duration)
    fundamental = sine_from_frequency(frequency_glide(duration, start_hz, end_hz))
    sub = sine_from_frequency(frequency_glide(duration, start_hz * 0.5, end_hz * 0.5))
    rumble = one_pole_lowpass(RNG.normal(0.0, 1.0, len(t)), cutoff_hz=180.0)
    crack = RNG.normal(0.0, 1.0, len(t)) * np.exp(-t / 0.035) * snap
    envelope = np.exp(-t / 0.55)
    signal = (fundamental * 0.62 + sub * 0.38 + rumble * noise_amount) * envelope + crack
    return fade(np.tanh(signal * 1.2), fade_in=0.001, fade_out=0.18)


def tone_event(t: np.ndarray, start: float, frequency: float, duration: float, amplitude: float) -> np.ndarray:
    local = t - start
    active = (local >= 0.0) & (local <= duration)
    event = np.zeros_like(t)
    local_active = local[active]
    attack = np.minimum(1.0, local_active / 0.008)
    envelope = attack * np.exp(-local_active / (duration * 0.42))
    event[active] = amplitude * np.sin(2.0 * np.pi * frequency * local_active) * envelope
    event[active] += amplitude * 0.28 * np.sin(2.0 * np.pi * frequency * 2.0 * local_active) * envelope
    return event


def notification(duration: float, events: list[tuple[float, float, float, float]]) -> np.ndarray:
    t = time_axis(duration)
    signal = np.zeros_like(t)
    for start, frequency, event_duration, amplitude in events:
        signal += tone_event(t, start, frequency, event_duration, amplitude)
    return fade(signal, fade_in=0.002, fade_out=0.12)


def generate() -> dict[str, np.ndarray]:
    return {
        "whoosh_soft.wav": bandpass_noise_sweep(1.15, 180.0, 1_850.0, q=0.75, energy=1.35) * 0.84,
        "whoosh_fast.wav": bandpass_noise_sweep(0.62, 430.0, 4_600.0, q=0.95, energy=0.82),
        "click_mouse.wav": impulse_click(0.50, [(0.000, 1.0)], tone_hz=2_900.0, noise_decay=0.018),
        "click_camera.wav": impulse_click(0.64, [(0.000, 1.0), (0.075, 0.72)], tone_hz=1_650.0, noise_decay=0.042),
        "pop_bubble.wav": sine_burst(0.55, 620.0, 185.0, decay=0.075, body=0.95),
        "pop_soft.wav": sine_burst(0.50, 310.0, 135.0, decay=0.060, body=0.75),
        "ding_bright.wav": harmonic_ding(
            1.22,
            1_046.5,
            [(1.0, 1.0, 0.48), (2.0, 0.34, 0.32), (3.0, 0.16, 0.20)],
        ),
        "ding_bell.wav": harmonic_ding(
            1.78,
            783.99,
            [(1.0, 0.95, 0.85), (1.5, 0.44, 0.72), (2.01, 0.30, 0.55), (2.98, 0.16, 0.38)],
        ),
        "boom_deep.wav": low_boom(1.62, 82.0, 34.0, noise_amount=0.15, snap=0.08),
        "boom_impact.wav": low_boom(1.12, 118.0, 42.0, noise_amount=0.26, snap=0.32),
        "notification_message.wav": notification(
            0.92,
            [(0.02, 659.25, 0.32, 0.75), (0.31, 880.00, 0.42, 0.82)],
        ),
        "notification_alert.wav": notification(
            1.18,
            [(0.01, 880.00, 0.28, 0.82), (0.27, 1_174.66, 0.32, 0.90), (0.59, 987.77, 0.40, 0.72)],
        ),
    }


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for file_name, signal in generate().items():
        output_path = OUTPUT_DIR / file_name
        write_wav(output_path, signal)
        print(f"Wrote {output_path.relative_to(Path.cwd())}")


if __name__ == "__main__":
    main()
