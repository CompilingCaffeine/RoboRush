#!/usr/bin/env python3
"""Synthesize Robo Rush's music as looping 16-bit mono WAVs.

Pure Python 3 stdlib (wave + struct + math + random) — NOT required to build or run the
game, only to regenerate the committed loops.

    python3 tools/generate_music.py .

Spec section 22 asks for chiptune, industrial percussion, retro synth bass, and fast arcade
loops. That is a 1990s cabinet's sound chip: two or three square-wave voices and a noise
channel, which is exactly what is here — a lead, a bass, and percussion built from filtered
noise and a pitched thump. No sampled instruments, because a sampled instrument next to
square-wave sound effects sounds like two different games.

Written as a tiny tracker rather than as a wall of arithmetic. A track is a tempo, a key, and
three channels of (note, length) pairs, so a melody can be read and edited as a melody. The
alternative — hand-computing phase per bar — is unreadable and unmaintainable, and would make
"the boss theme is one semitone off" a debugging session rather than a one-character fix.

Loops are seamless by construction: every channel is a whole number of beats long and every
note's envelope decays before the bar line, so there is no click at the join and no fade
needed (a fade would put an audible dip in a loop that repeats every twenty seconds).
"""

import math
import os
import random
import struct
import sys
import wave

SAMPLE_RATE = 22050

# Deterministic percussion, so regenerating does not produce a different-sounding build.
NOISE_SEED = 20260802

# Music sits under the sound effects, which peak around 0.35. Spec section 22 warns against
# fatiguing audio, and a loop the player hears for ten minutes is the easiest thing in the
# game to get wrong in that direction.
MUSIC_AMPLITUDE = 0.20

SEMITONES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_hz(name: str) -> float:
    """"A4" -> 440.0, "C#5" -> 554.4. Rests are handled by the caller, not here."""
    letter = name[0].upper()
    accidental = 0
    index = 1
    if len(name) > 1 and name[1] in "#b":
        accidental = 1 if name[1] == "#" else -1
        index = 2
    octave = int(name[index:])
    # MIDI note number, then equal temperament from A4 = 440 Hz = MIDI 69.
    midi = (octave + 1) * 12 + SEMITONES[letter] + accidental
    return 440.0 * pow(2.0, (midi - 69) / 12.0)


def square(phase: float, duty: float = 0.5) -> float:
    return 1.0 if (phase % 1.0) < duty else -1.0


def decay(progress: float, sharpness: float) -> float:
    return math.exp(-sharpness * progress)


def lead_voice(freq: float, phase: float, progress: float) -> float:
    """Narrow-duty square with a soft attack. The melody."""
    attack = min(1.0, progress * 14.0)
    return square(phase, 0.30) * attack * decay(progress, 2.2) * 0.55


def bass_voice(freq: float, phase: float, progress: float) -> float:
    """Half-duty square an octave or two down, held longer. The retro synth bass."""
    return square(phase, 0.5) * decay(progress, 1.1) * 0.75


def arp_voice(freq: float, phase: float, progress: float) -> float:
    """Very short, very narrow pulses. Fills the gaps the lead leaves without competing."""
    return square(phase, 0.14) * decay(progress, 6.0) * 0.35


def render_melodic(
    events: list[tuple[str, float]], beat_seconds: float, voice
) -> list[float]:
    """Renders one channel of (note, length-in-beats) pairs. "." is a rest.

    Phase is carried across notes rather than reset, which is what keeps a repeated note from
    clicking at its boundary.
    """
    def at(beats: float) -> int:
        return int(round(beats * beat_seconds * SAMPLE_RATE))

    total_beats = sum(length for _, length in events)
    out = [0.0] * at(total_beats)
    phase = 0.0
    elapsed = 0.0

    for name, length in events:
        # Both edges are derived from the cumulative beat position rather than from a
        # per-note rounded length. Rounding each note independently drifts by a sample or two
        # per note, which over a thirty-two beat bar puts the channels tens of samples out of
        # step and the loop point in the wrong place.
        start = at(elapsed)
        elapsed += length
        count = at(elapsed) - start
        if name == "." or count <= 0:
            continue
        freq = note_hz(name)
        for index in range(count):
            phase += freq / SAMPLE_RATE
            out[start + index] = voice(freq, phase, index / count)

    return out


def render_drums(pattern: str, beat_seconds: float, noise: random.Random) -> list[float]:
    """One character per sixteenth note: k kick, s snare, h hat, . nothing.

    Industrial percussion in the sense spec section 22 means it: the kick is a pitch-swept
    sine (a press dropping), the snare is a noise burst with a tone under it, the hat is a
    very short high noise tick. All three are machinery rather than a drum kit.
    """
    step_seconds = beat_seconds / 4.0

    def at(step: float) -> int:
        return int(round(step * step_seconds * SAMPLE_RATE))

    out = [0.0] * at(len(pattern))

    for step, symbol in enumerate(pattern):
        if symbol == ".":
            continue
        # Same reasoning as render_melodic: position from the exact step index, not from a
        # rounded step length multiplied out.
        start = at(step)
        # Hits are allowed to ring past their own step, so the tail of a kick overlaps the
        # next sixteenth instead of being cut off square.
        length = min(int(step_seconds * SAMPLE_RATE * 4), len(out) - start)
        phase = 0.0
        for index in range(length):
            progress = index / length
            if symbol == "k":
                freq = 92.0 * pow(38.0 / 92.0, progress)
                phase += freq / SAMPLE_RATE
                sample = math.sin(phase * math.tau) * decay(progress, 7.0) * 0.9
            elif symbol == "s":
                phase += 190.0 / SAMPLE_RATE
                body = square(phase, 0.5) * 0.3
                crack = noise.uniform(-1.0, 1.0) * 0.7
                sample = (body + crack) * decay(progress, 16.0)
            else:
                sample = noise.uniform(-1.0, 1.0) * decay(progress, 60.0) * 0.35
            out[start + index] += sample

    return out


## Channels are allowed to differ by a few samples, because a melodic channel rounds each
## note to whole samples while the drum channel rounds each sixteenth — the two accumulate
## differently over a bar. Anything larger than this is a miscounted pattern.
LENGTH_TOLERANCE_SAMPLES = 16


def mix(channels: list[list[float]], expected_beats: float, beat_seconds: float) -> list[float]:
    """Sums channels, having first checked they are all the length they claim to be.

    The check is the whole reason this takes a beat count. The first version of every track
    here had a bass line and a drum pattern half the length of its melody, so the back half of
    each loop played the tune over silence — which sounds like the music has stopped rather
    than like a mistake, and is invisible in the code unless something counts the beats.
    """
    expected = int(round(expected_beats * beat_seconds * SAMPLE_RATE))
    for index, channel in enumerate(channels):
        drift = abs(len(channel) - expected)
        assert drift <= LENGTH_TOLERANCE_SAMPLES, (
            f"channel {index} is {len(channel)} samples, expected about {expected} "
            f"({expected_beats} beats) — off by {drift}"
        )

    length = max(len(channel) for channel in channels)
    out = [0.0] * length
    for channel in channels:
        for index, sample in enumerate(channel):
            out[index] += sample
    return out


def write_wav(path: str, samples: list[float], amplitude: float) -> None:
    peak = max((abs(sample) for sample in samples), default=1.0) or 1.0
    scale = amplitude / peak
    frames = b"".join(
        struct.pack("<h", max(-32768, min(32767, int(sample * scale * 32767))))
        for sample in samples
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)
    print(f"wrote {path} ({len(samples) / SAMPLE_RATE:.1f} s)")


# --- The three tracks --------------------------------------------------------------
#
# One per situation the player can be in for minutes at a time: reading the menu, clearing
# rooms, and fighting the boss. All three are in A minor so that a crossfade between any two
# of them is a key change nobody notices, which is the difference between a transition and an
# interruption.


def _up_octave(name: str) -> str:
    """"D#5" -> "D#6". Rests pass through unchanged."""
    if name == ".":
        return name
    return name[:-1] + str(int(name[-1]) + 1)


def menu_track(noise: random.Random) -> list[float]:
    """Slow, sparse, unresolved. The title screen is the one place the player is not under
    pressure, and a driving loop there makes the menu feel like a countdown."""
    beat = 60.0 / 96.0

    lead = [
        ("A4", 2), ("C5", 1), ("E5", 1), ("D5", 2), (".", 2),
        ("F4", 2), ("A4", 1), ("C5", 1), ("B4", 3), (".", 1),
        ("A4", 2), ("E5", 1), ("D5", 1), ("C5", 2), (".", 2),
        ("G4", 2), ("B4", 1), ("D5", 1), ("A4", 3), (".", 1),
    ]
    bass = [
        ("A2", 4), ("F2", 4), ("A2", 4), ("G2", 4),
    ]
    # Just a pulse and an offbeat tick: percussion here is a clock, not a groove.
    # Sixteen characters is four beats, so eight repeats covers the melody's thirty-two.
    drums = "k...h...k...h..." * 8

    return mix([
        render_melodic(lead, beat, lead_voice),
        render_melodic(bass * 2, beat, bass_voice),
        render_drums(drums, beat, noise),
    ], 32, beat)


def explore_track(noise: random.Random) -> list[float]:
    """The room-clearing loop. Fast arcade, per spec section 22, and the track the player
    hears for most of a run — so it moves without ever arriving anywhere."""
    beat = 60.0 / 138.0

    lead = [
        ("A4", 1), ("A4", 0.5), ("C5", 0.5), ("E5", 1), ("D5", 1),
        ("C5", 1), ("A4", 0.5), ("B4", 0.5), ("C5", 2),
        ("F4", 1), ("F4", 0.5), ("A4", 0.5), ("C5", 1), ("B4", 1),
        ("A4", 1), ("G4", 0.5), ("A4", 0.5), ("E4", 2),
        ("A4", 1), ("C5", 0.5), ("E5", 0.5), ("G5", 1), ("E5", 1),
        ("D5", 1), ("C5", 0.5), ("B4", 0.5), ("A4", 2),
        ("G4", 1), ("B4", 0.5), ("D5", 0.5), ("F5", 1), ("D5", 1),
        ("C5", 1), ("B4", 0.5), ("A4", 0.5), ("A4", 2),
    ]
    bass = [
        ("A2", 0.5), ("A2", 0.5), ("A3", 0.5), ("A2", 0.5),
        ("A2", 0.5), ("A2", 0.5), ("E3", 0.5), ("A2", 0.5),
        ("F2", 0.5), ("F2", 0.5), ("F3", 0.5), ("F2", 0.5),
        ("C3", 0.5), ("C3", 0.5), ("G3", 0.5), ("C3", 0.5),
    ] * 2
    arp = [
        ("A5", 0.25), ("E5", 0.25), ("C5", 0.25), ("E5", 0.25),
    ] * 32
    drums = "k..hs..hk..hs.hh" * 8

    return mix([
        render_melodic(lead, beat, lead_voice),
        render_melodic(bass * 2, beat, bass_voice),
        render_melodic(arp, beat, arp_voice),
        render_drums(drums, beat, noise),
    ], 32, beat)


def boss_track(noise: random.Random) -> list[float]:
    """The Merge Conflict. Faster than the explore loop, and built on a tritone that never
    resolves — the fight is two things that do not agree, so neither does the music."""
    beat = 60.0 / 156.0

    lead = [
        ("A4", 0.5), ("D#5", 0.5), ("A4", 0.5), ("E5", 0.5),
        ("A4", 0.5), ("D#5", 0.5), ("F5", 1),
        ("G#4", 0.5), ("D5", 0.5), ("G#4", 0.5), ("D#5", 0.5),
        ("G#4", 0.5), ("D5", 0.5), ("E5", 1),
        ("A4", 0.5), ("E5", 0.5), ("A5", 0.5), ("E5", 0.5),
        ("F5", 0.5), ("E5", 0.5), ("D#5", 1),
        ("D5", 0.5), ("A4", 0.5), ("D5", 0.5), ("F4", 0.5),
        ("E4", 2),
    ]
    bass = [
        ("A2", 0.5), ("A2", 0.5), ("D#3", 0.5), ("A2", 0.5),
        ("A2", 0.5), ("A2", 0.5), ("A2", 0.5), ("A2", 0.5),
        ("G#2", 0.5), ("G#2", 0.5), ("D3", 0.5), ("G#2", 0.5),
        ("G#2", 0.5), ("G#2", 0.5), ("G#2", 0.5), ("G#2", 0.5),
    ] * 2
    drums = "ks.hks.hks.hkshh" * 8

    return mix([
        # Two passes of the melody, the second an octave up, so a fight that outlasts one
        # loop does not sound like the same four bars on repeat.
        render_melodic(lead + [(_up_octave(name), length) for name, length in lead], beat, lead_voice),
        render_melodic(bass * 2, beat, bass_voice),
        render_drums(drums, beat, noise),
    ], 32, beat)


TRACKS = {
    "audio/music/menu.wav": menu_track,
    "audio/music/explore.wav": explore_track,
    "audio/music/boss.wav": boss_track,
}


def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for relative, maker in TRACKS.items():
        noise = random.Random(NOISE_SEED)
        write_wav(os.path.join(root, relative), maker(noise), MUSIC_AMPLITUDE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
