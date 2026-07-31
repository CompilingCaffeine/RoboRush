#!/usr/bin/env python3
"""Synthesize Robo Rush placeholder sound effects as 16-bit mono WAVs.

Pure Python 3 stdlib (wave + struct + random) — NOT required to build or run the
game, only to regenerate the committed placeholder WAVs.

    python3 tools/generate_placeholder_audio.py .

Style target is spec section 22: chiptune, short, readable, never fatiguing.
Everything here is square waves and noise, the two voices a 1990s arcade cabinet
would actually have had. Amplitudes are kept low (<= 0.35) deliberately — mixing
headroom is easier to add than to claw back, and section 22 explicitly warns
against loud effects.
"""

import math
import os
import random
import struct
import sys
import wave

SAMPLE_RATE = 22050

# Deterministic noise so regenerating does not produce a different-sounding build.
NOISE_SEED = 20260731


def square(phase: float, duty: float = 0.5) -> float:
    return 1.0 if (phase % 1.0) < duty else -1.0


def sweep(start: float, end: float, progress: float) -> float:
    """Exponential frequency sweep — linear sweeps sound wrong to the ear."""
    return start * pow(end / start, progress)


def render(duration: float, voice) -> list[float]:
    """voice(t, progress) -> sample in roughly [-1, 1]."""
    count = int(SAMPLE_RATE * duration)
    return [voice(i / SAMPLE_RATE, i / count) for i in range(count)]


def decay(progress: float, sharpness: float = 5.0) -> float:
    return math.exp(-sharpness * progress)


def write_wav(path: str, samples: list[float], amplitude: float) -> None:
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = amplitude / peak
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(s * scale * 32767)))) for s in samples
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    print(f"wrote {path} ({len(samples) / SAMPLE_RATE * 1000:.0f} ms)")


def make_fire(noise: random.Random) -> list[float]:
    """Rivet Blaster: tight downward chirp. Fires 4x/sec, so it must not fatigue."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        freq = sweep(900.0, 260.0, progress)
        phase[0] += freq / SAMPLE_RATE
        return square(phase[0], 0.35) * decay(progress, 6.0)

    return render(0.07, voice)


def make_enemy_hit(noise: random.Random) -> list[float]:
    """Short bright click plus a noise transient — reads as 'connected'."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        phase[0] += 1500.0 / SAMPLE_RATE
        tone = square(phase[0]) * 0.6
        crack = noise.uniform(-1.0, 1.0) * 0.8 * decay(progress, 30.0)
        return (tone + crack) * decay(progress, 16.0)

    return render(0.05, voice)


def make_enemy_death(noise: random.Random) -> list[float]:
    """Descending arpeggio with a noise tail: something broke apart."""
    steps = [620.0, 460.0, 330.0, 210.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        freq = steps[min(int(progress * len(steps)), len(steps) - 1)]
        phase[0] += freq / SAMPLE_RATE
        tone = square(phase[0], 0.4) * 0.7
        debris = noise.uniform(-1.0, 1.0) * 0.35 * decay(progress, 4.0)
        return (tone + debris) * decay(progress, 2.6)

    return render(0.26, voice)


def make_player_hurt(noise: random.Random) -> list[float]:
    """Low, ugly, unmistakable. The one sound the player must never miss."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        freq = sweep(330.0, 85.0, progress)
        phase[0] += freq / SAMPLE_RATE
        tone = square(phase[0], 0.5) * 0.8
        grit = noise.uniform(-1.0, 1.0) * 0.3 * decay(progress, 8.0)
        return (tone + grit) * decay(progress, 3.0)

    return render(0.20, voice)


def make_dash(noise: random.Random) -> list[float]:
    """Upward whoosh: filtered noise plus a rising tone."""
    phase = [0.0]
    smoothed = [0.0]

    def voice(_t: float, progress: float) -> float:
        # A one-pole lowpass turns white noise into something closer to air.
        smoothed[0] += (noise.uniform(-1.0, 1.0) - smoothed[0]) * 0.35
        phase[0] += sweep(220.0, 700.0, progress) / SAMPLE_RATE
        envelope = math.sin(math.pi * progress)
        return (smoothed[0] * 1.2 + square(phase[0], 0.2) * 0.35) * envelope

    return render(0.12, voice)


def make_room_clear(noise: random.Random) -> list[float]:
    """Rising major arpeggio: the only unambiguously good news in the game."""
    steps = [523.0, 659.0, 784.0, 1047.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        # Re-attack each step so the arpeggio reads as four distinct notes.
        step_progress = (progress * len(steps)) % 1.0
        return square(phase[0], 0.5) * decay(step_progress, 3.0)

    return render(0.36, voice)


def make_low_integrity(noise: random.Random) -> list[float]:
    """Two-tone warning beep for the last integrity point."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        freq = 760.0 if progress < 0.5 else 560.0
        phase[0] += freq / SAMPLE_RATE
        step_progress = (progress * 2.0) % 1.0
        return square(phase[0], 0.5) * decay(step_progress, 4.0)

    return render(0.22, voice)


def make_pickup(noise: random.Random) -> list[float]:
    """Bright two-step blip. Fires often, so it is short and sits high out of the way."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        freq = 880.0 if progress < 0.45 else 1320.0
        phase[0] += freq / SAMPLE_RATE
        step_progress = (progress * 2.2) % 1.0
        return square(phase[0], 0.3) * decay(step_progress, 5.0)

    return render(0.08, voice)


def make_door(noise: random.Random) -> list[float]:
    """Heavy servo thunk: low square slide plus a mechanical noise transient."""
    phase = [0.0]
    smoothed = [0.0]

    def voice(_t: float, progress: float) -> float:
        phase[0] += sweep(150.0, 62.0, progress) / SAMPLE_RATE
        smoothed[0] += (noise.uniform(-1.0, 1.0) - smoothed[0]) * 0.2
        clunk = smoothed[0] * 0.5 * decay(progress, 14.0)
        return (square(phase[0], 0.5) * 0.8 + clunk) * decay(progress, 3.2)

    return render(0.18, voice)


SOUNDS = {
    "audio/sfx/fire.wav": (make_fire, 0.22),
    "audio/sfx/enemy_hit.wav": (make_enemy_hit, 0.26),
    "audio/sfx/enemy_death.wav": (make_enemy_death, 0.30),
    "audio/sfx/player_hurt.wav": (make_player_hurt, 0.35),
    "audio/sfx/dash.wav": (make_dash, 0.18),
    "audio/sfx/room_clear.wav": (make_room_clear, 0.24),
    "audio/sfx/low_integrity.wav": (make_low_integrity, 0.22),
    "audio/sfx/pickup.wav": (make_pickup, 0.20),
    "audio/sfx/door.wav": (make_door, 0.26),
}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for relative, (maker, amplitude) in SOUNDS.items():
        noise = random.Random(NOISE_SEED)
        write_wav(os.path.join(root, relative), maker(noise), amplitude)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
