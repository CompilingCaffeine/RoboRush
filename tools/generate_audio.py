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


def make_migrate(noise: random.Random) -> list[float]:
    """Two-part blink: a short downward pluck, a gap, then the same pluck an octave up.

    Deliberately not a whoosh. `make_dash` is the whoosh, and a dash and a migration are
    different claims about the same robot — one is travel through the room and the other is
    the room deciding the robot was somewhere else all along. A sound that swept would say
    the first. Two discrete plucks either side of silence say the second: departure, nothing,
    arrival. The silence is most of the sound and is doing the work.
    """
    phase = [0.0]
    gap = 0.035

    def voice(t: float, progress: float) -> float:
        # Which half of the sound we are in. The middle is genuinely silent rather than
        # quiet — a fade across the gap would join the two plucks into one event.
        if 0.05 <= t < 0.05 + gap:
            return 0.0
        arriving = t >= 0.05 + gap
        base = 880.0 if arriving else 440.0
        phase[0] += base / SAMPLE_RATE
        # Each half runs its own envelope, so the second pluck attacks rather than swelling
        # out of the first one's tail.
        local = (t - (0.05 + gap)) / 0.06 if arriving else t / 0.05
        return square(phase[0], 0.35) * decay(min(local, 1.0), 6.0)

    return render(0.05 + gap + 0.06, voice)


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
    """A bolt driving shut: a rising servo, then a bright metallic latch.

    Rising, and bright where it lands, on purpose. This used to be a falling low square with a
    noise transient under a single decay — which is `make_player_hurt` described word for word,
    20ms apart in length and a fifth apart in register. It fires on the frame the doors of an
    uncleared room lock behind the player, which is the same frame the robot begins its room-entry
    invulnerability flash, and testers reported the pair as a hit they had taken.

    So the fix is a shape the hurt sound cannot have: the motor holds instead of decaying, the
    pitch climbs instead of falling, and the loudest moment is a high latch at the end rather than
    a low thump at the start. Nothing else in the library sits in the player's hurt register now,
    and neither does this.
    """
    # Where the motor stops and the bolt seats. The two halves are cut rather than crossfaded —
    # a latch is a discontinuity, and smoothing it is what would make it a thump again.
    latch_at = 0.62

    phase = [0.0]
    latch_phase = [0.0]
    smoothed = [0.0]

    def voice(_t: float, progress: float) -> float:
        if progress < latch_at:
            phase[0] += sweep(70.0, 190.0, progress) / SAMPLE_RATE
            # Held, not decayed. A servo that faded out would be one losing power rather than one
            # arriving; the short attack only keeps the very first sample from clicking.
            attack = min(progress / 0.06, 1.0)
            return square(phase[0], 0.25) * 0.5 * attack

        latch_progress = (progress - latch_at) / (1.0 - latch_at)
        latch_phase[0] += 1400.0 / SAMPLE_RATE
        smoothed[0] += (noise.uniform(-1.0, 1.0) - smoothed[0]) * 0.7
        ring = square(latch_phase[0], 0.5) * 0.45
        clack = smoothed[0] * 0.8
        return (ring + clack) * decay(latch_progress, 9.0)

    return render(0.20, voice)


def make_item_pickup(noise: random.Random) -> list[float]:
    """Four-note rising fanfare. Deliberately the longest and most musical sound in the
    game: an item is the one pickup the player should stop and read."""
    steps = [523.0, 784.0, 1047.0, 1319.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        step_progress = (progress * len(steps)) % 1.0
        return square(phase[0], 0.25) * decay(step_progress, 2.4)

    return render(0.42, voice)


def make_explosion(noise: random.Random) -> list[float]:
    """Filtered noise over a falling square. Longer tail than a hit, shorter than death."""
    phase = [0.0]
    smoothed = [0.0]

    def voice(_t: float, progress: float) -> float:
        smoothed[0] += (noise.uniform(-1.0, 1.0) - smoothed[0]) * 0.12
        phase[0] += sweep(190.0, 48.0, progress) / SAMPLE_RATE
        return (smoothed[0] * 1.4 + square(phase[0], 0.5) * 0.5) * decay(progress, 4.5)

    return render(0.30, voice)


def make_zap(noise: random.Random) -> list[float]:
    """Chain lightning: a very short crackle high above everything else in the mix, so
    three of them in a row read as three jumps rather than as one noise."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        phase[0] += sweep(2600.0, 1100.0, progress) / SAMPLE_RATE
        crackle = noise.uniform(-1.0, 1.0) * 0.5
        return (square(phase[0], 0.15) + crackle) * decay(progress, 22.0)

    return render(0.06, voice)


def make_ui_move(noise: random.Random) -> list[float]:
    """One tick as the selection moves. As short as a sound can be and still be heard: it
    fires on every keypress in a menu, which makes it the most repeated sound in the game."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        phase[0] += 1180.0 / SAMPLE_RATE
        return square(phase[0], 0.25) * decay(progress, 26.0)

    return render(0.035, voice)


def make_ui_confirm(noise: random.Random) -> list[float]:
    """Two notes up. The menu counterpart of room_clear, an octave smaller — confirming a
    setting is good news, but it is not an achievement."""
    steps = [784.0, 1175.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        step_progress = (progress * len(steps)) % 1.0
        return square(phase[0], 0.35) * decay(step_progress, 5.0)

    return render(0.12, voice)


def make_ui_back(noise: random.Random) -> list[float]:
    """Two notes down: the same gesture as confirm, reversed, so the pair reads as a pair."""
    steps = [880.0, 587.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        step_progress = (progress * len(steps)) % 1.0
        return square(phase[0], 0.35) * decay(step_progress, 6.0)

    return render(0.10, voice)


def make_purchase(noise: random.Random) -> list[float]:
    """Scrap changing hands. A bright triple blip with a metallic noise edge — close enough
    to a till to be legible, mechanical enough to belong in a maintenance robot's world."""
    steps = [1047.0, 1319.0, 1568.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        step_progress = (progress * len(steps)) % 1.0
        clink = noise.uniform(-1.0, 1.0) * 0.18 * decay(step_progress, 24.0)
        return (square(phase[0], 0.3) * 0.8 + clink) * decay(step_progress, 4.0)

    return render(0.24, voice)


def make_boss_phase(noise: random.Random) -> list[float]:
    """The Merge Conflict changing shape. Two detuned squares sliding apart, which is the
    fight's whole idea made audible: one thing becoming two that no longer agree."""
    low = [0.0]
    high = [0.0]

    def voice(_t: float, progress: float) -> float:
        low[0] += sweep(220.0, 138.0, progress) / SAMPLE_RATE
        high[0] += sweep(226.0, 330.0, progress) / SAMPLE_RATE
        envelope = min(1.0, progress * 8.0) * decay(progress, 1.6)
        grind = noise.uniform(-1.0, 1.0) * 0.16 * decay(progress, 3.0)
        return (square(low[0], 0.5) * 0.6 + square(high[0], 0.45) * 0.5 + grind) * envelope

    return render(0.70, voice)


def make_victory(noise: random.Random) -> list[float]:
    """Run won. The longest sound in the game, and the only one allowed to be."""
    steps = [523.0, 659.0, 784.0, 1047.0, 784.0, 1047.0, 1319.0]
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        index = min(int(progress * len(steps)), len(steps) - 1)
        phase[0] += steps[index] / SAMPLE_RATE
        step_progress = (progress * len(steps)) % 1.0
        # The last note rings instead of clipping short, so the fanfare has an ending.
        sharpness = 1.2 if index == len(steps) - 1 else 3.2
        return square(phase[0], 0.4) * decay(step_progress, sharpness)

    return render(1.10, voice)


def make_game_over(noise: random.Random) -> list[float]:
    """Run lost. A power-down: pitch and duty cycle both collapse, so it thins out as it
    falls rather than simply getting lower."""
    phase = [0.0]

    def voice(_t: float, progress: float) -> float:
        phase[0] += sweep(392.0, 62.0, progress) / SAMPLE_RATE
        duty = 0.5 - 0.35 * progress
        grit = noise.uniform(-1.0, 1.0) * 0.12 * decay(progress, 2.0)
        return (square(phase[0], duty) * 0.9 + grit) * decay(progress, 1.3)

    return render(0.85, voice)


SOUNDS = {
    "audio/sfx/fire.wav": (make_fire, 0.22),
    "audio/sfx/enemy_hit.wav": (make_enemy_hit, 0.26),
    "audio/sfx/enemy_death.wav": (make_enemy_death, 0.30),
    "audio/sfx/player_hurt.wav": (make_player_hurt, 0.35),
    "audio/sfx/dash.wav": (make_dash, 0.18),
    # Quieter than the dash it sits beside. A migration happens once per crossing and a dash
    # happens constantly, but the pad is a mechanic the player will use all floor and a sound
    # at dash volume every time would wear out long before the floor did.
    "audio/sfx/migrate.wav": (make_migrate, 0.15),
    "audio/sfx/room_clear.wav": (make_room_clear, 0.24),
    "audio/sfx/low_integrity.wav": (make_low_integrity, 0.22),
    "audio/sfx/pickup.wav": (make_pickup, 0.20),
    "audio/sfx/door.wav": (make_door, 0.26),
    "audio/sfx/item_pickup.wav": (make_item_pickup, 0.26),
    "audio/sfx/explosion.wav": (make_explosion, 0.30),
    "audio/sfx/zap.wav": (make_zap, 0.20),
    # Interface and moment sounds. The UI ticks are the quietest things in the game on
    # purpose: they accompany a keypress, and a keypress is not an event.
    "audio/sfx/ui_move.wav": (make_ui_move, 0.10),
    "audio/sfx/ui_confirm.wav": (make_ui_confirm, 0.16),
    "audio/sfx/ui_back.wav": (make_ui_back, 0.14),
    "audio/sfx/purchase.wav": (make_purchase, 0.24),
    "audio/sfx/boss_phase.wav": (make_boss_phase, 0.30),
    "audio/sfx/victory.wav": (make_victory, 0.28),
    "audio/sfx/game_over.wav": (make_game_over, 0.30),
}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for relative, (maker, amplitude) in SOUNDS.items():
        noise = random.Random(NOISE_SEED)
        write_wav(os.path.join(root, relative), maker(noise), amplitude)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
