#!/usr/bin/env python3
"""Synthesizes the spellcasting sounds into assets/audio/ (deterministic, numpy only).

    python3 tools/gen_audio.py

* syl_ah / syl_bra / syl_ca / syl_da: the four chanted syllables (A/B/X/Y). Formant
  synthesis of a sung "a" on a different note each (A3 C4 D4 E4, so incantations are tiny
  melodies), with the consonant of each syllable: breathy onset, voiced b + rolled r,
  aspirated k, voiced d. A faint bell an octave up and a short room make them magical.
* spell_push / spell_pit / spell_mend / spell_raise: one success sound per spell effect.
* fizzle: a failed incantation / spell.
"""
import math
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(7)


def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def resonator(x, freq, bw):
    """2-pole resonator; freq/bw may be arrays (time-varying formants)."""
    n = len(x)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    bw = np.broadcast_to(np.asarray(bw, dtype=float), (n,))
    r = np.exp(-math.pi * bw / SR)
    a1 = 2.0 * r * np.cos(2.0 * math.pi * freq / SR)
    a2 = -r * r
    # Unity gain at the centre frequency, so time-varying formants keep a steady level.
    w = 2.0 * math.pi * freq / SR
    g = np.abs(1.0 - a1 * np.exp(-1j * w) - a2 * np.exp(-2j * w))
    y = np.zeros(n)
    y1 = y2 = 0.0
    for i in range(n):
        v = g[i] * x[i] + a1[i] * y1 + a2[i] * y2
        y[i] = v
        y2 = y1
        y1 = v
    return y


def lowpass(x, cutoff):
    a = math.exp(-2.0 * math.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def env_adsr(n, attack, release, total):
    t = np.arange(n) / SR
    e = np.minimum(t / max(attack, 1e-4), 1.0)
    rel_start = total - release
    e *= np.clip(1.0 - (t - rel_start) / release, 0.0, 1.0)
    return e


def glottal(f0, dur, vibrato=0.012):
    """Band-limited glottal-ish pulse train with vibrato and a little jitter."""
    t = t_axis(dur)
    f = f0 * (1.0 + vibrato * np.sin(2 * math.pi * 5.3 * t) * np.minimum(t / 0.12, 1.0))
    f *= 1.0 + 0.004 * lowpass(rng.standard_normal(len(t)), 30.0) * 8
    phase = 2 * math.pi * np.cumsum(f) / SR
    out = np.zeros(len(t))
    k = 1
    while k * f0 < 5000:
        out += np.sin(k * phase) / (k ** 1.15)
        k += 1
    return out


VOWEL_A = [(760, 90), (1180, 110), (2600, 170), (3350, 250)]


def vocal_tract(src, formants):
    """Cascade of formant resonators; formants = list of (freq, bw), each may be an array."""
    y = src
    for f, b in formants:
        y = resonator(y, f, b)
        y /= max(np.max(np.abs(y)), 1e-9)
    return y


def ramp(n, start, end, t0, t1):
    """Per-sample value going from start to end between t0 and t1 seconds."""
    t = np.arange(n) / SR
    k = np.clip((t - t0) / max(t1 - t0, 1e-4), 0.0, 1.0)
    k = k * k * (3 - 2 * k)
    return start + (end - start) * k


def room(x, mix=0.18):
    """Tiny feedback-comb room, enough to make a dry voice sit in a space."""
    y = np.copy(x)
    for delay_ms, gain in [(29.7, 0.5), (37.1, 0.45), (41.1, 0.4)]:
        d = int(delay_ms * SR / 1000)
        buf = np.zeros(len(x) + d * 8)
        buf[: len(x)] = x
        for i in range(d, len(buf)):
            buf[i] += gain * buf[i - d]
        y = y + mix * buf[: len(x)] / 3.0
    return y


def bell(freq, dur, decay=4.0):
    t = t_axis(dur)
    s = np.zeros(len(t))
    for ratio, amp in [(1.0, 1.0), (2.0, 0.35), (2.76, 0.25), (5.4, 0.1)]:
        s += amp * np.sin(2 * math.pi * freq * ratio * t) * np.exp(-t * decay * (1 + ratio * 0.4))
    return s * np.minimum(t / 0.004, 1.0)


def noise(n):
    return rng.standard_normal(n)


def brown(n, cutoff):
    """Deep rumble: white noise through three one-pole lowpasses (18 dB/oct)."""
    return lowpass(lowpass(lowpass(noise(n), cutoff), cutoff), cutoff * 2.0)


def normalize(x, peak=0.7):
    return x / max(np.max(np.abs(x)), 1e-9) * peak


def syllable(kind, f0):
    dur = 0.42
    n = int(dur * SR)
    voice = glottal(f0, dur)
    # Formant trajectories start from the consonant and glide into "a".
    if kind == "ah":
        onset = 0.0
        forms = VOWEL_A
    elif kind == "bra":
        onset = 0.03
        f1 = ramp(n, 300, 760, 0.03, 0.13)
        f2 = ramp(n, 1250, 1180, 0.05, 0.14)
        f3 = ramp(n, 1700, 2600, 0.05, 0.14)
        forms = [(f1, 90), (f2, 110), (f3, 170), (3350, 250)]
    elif kind == "ca":
        onset = 0.055
        f2 = ramp(n, 1700, 1180, 0.055, 0.12)
        forms = [(ramp(n, 500, 760, 0.055, 0.1), 90), (f2, 110), (2600, 170), (3350, 250)]
    else:  # "da"
        onset = 0.02
        f2 = ramp(n, 1750, 1180, 0.02, 0.09)
        forms = [(ramp(n, 350, 760, 0.02, 0.08), 90), (f2, 110), (2700, 170), (3350, 250)]
    t = np.arange(n) / SR
    v_env = np.clip((t - onset) / 0.025, 0.0, 1.0) * np.clip((dur - t) / 0.2, 0.0, 1.0) ** 1.5
    if kind == "bra":
        # Rolled r: three quick tongue taps modulating the voice.
        trill = np.where((t > 0.035) & (t < 0.11), 0.55 + 0.45 * np.cos(2 * math.pi * 30 * (t - 0.035)), 1.0)
        v_env *= trill
    sig = vocal_tract(voice, forms) * v_env

    if kind == "ah":
        # Breathy onset.
        breath = vocal_tract(noise(n), VOWEL_A) * np.clip(1.0 - t / 0.06, 0.0, 1.0) * 0.35
        sig += breath
    elif kind == "bra":
        # Voice bar (closed lips) then the lip release pop.
        bar = resonator(voice, 250, 80) * np.clip(1.0 - np.abs(t - 0.015) / 0.015, 0.0, 1.0) * 0.25
        pop = lowpass(noise(n), 1800) * np.exp(-np.maximum(t - 0.03, 0) * 220) * (t >= 0.03) * 3.0
        sig += bar + pop
    elif kind == "ca":
        burst = resonator(noise(n), 2200, 600) * np.exp(-np.maximum(t - 0.012, 0) * 180) * (t >= 0.012) * 1.6
        asp = vocal_tract(noise(n), VOWEL_A) * np.clip((t - 0.02) / 0.01, 0, 1) * np.clip(1 - (t - 0.03) / 0.03, 0, 1) * 0.5
        sig += burst + asp
    else:
        bar = resonator(voice, 260, 80) * np.clip(1.0 - t / 0.02, 0.0, 1.0) * 0.25
        burst = resonator(noise(n), 4000, 900) * np.exp(-np.maximum(t - 0.016, 0) * 300) * (t >= 0.016) * 1.4
        sig += bar + burst

    sig = normalize(sig, 0.8)
    shimmer = bell(f0 * 4, dur, 6.0) * 0.07
    out = room(sig + shimmer)
    out *= np.clip((dur - t) / 0.03, 0, 1)
    # Same loudness for every syllable (vowel RMS), consonant peaks softly limited.
    mid = out[int(0.1 * SR): int(0.25 * SR)]
    out = out / max(float(np.sqrt(np.mean(mid ** 2))), 1e-9) * 0.25
    return np.tanh(out * 1.3) / 1.3


def spell_push():
    dur = 0.7
    n = int(dur * SR)
    t = t_axis(dur)
    sweep = resonator(noise(n), ramp(n, 500, 3200, 0.0, 0.35), 500) * np.exp(-t * 5.0) * np.minimum(t / 0.03, 1)
    f = ramp(n, 330, 990, 0.0, 0.18)
    zap = np.sin(2 * math.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * math.pi * np.cumsum(f) / SR)
    zap *= np.exp(-t * 7.0) * np.minimum(t / 0.005, 1)
    thump = np.sin(2 * math.pi * np.cumsum(ramp(n, 140, 55, 0, 0.12)) / SR) * np.exp(-t * 18)
    return normalize(room(0.9 * normalize(sweep) + 0.45 * zap + 0.6 * thump, 0.25), 0.75)


def spell_pit():
    dur = 1.0
    n = int(dur * SR)
    t = t_axis(dur)
    crack = lowpass(noise(n), 3000) * np.exp(-t * 60) * 1.2 + resonator(noise(n), 900, 400) * np.exp(-np.maximum(t - 0.06, 0) * 40) * (t > 0.06)
    rumble = brown(n, 120) * np.minimum(t / 0.05, 1) * np.exp(-t * 2.4)
    drop = np.sin(2 * math.pi * np.cumsum(ramp(n, 180, 45, 0.0, 0.6)) / SR) * np.exp(-t * 3.0) * 0.7
    debris = resonator(noise(n), 2400, 900) * (rng.random(n) < 0.002) * 6 * np.exp(-t * 3)
    return normalize(normalize(crack) * 0.8 + normalize(rumble) + drop + debris * 0.4, 0.8)


def spell_mend():
    dur = 1.1
    n = int(dur * SR)
    t = t_axis(dur)
    rumble = brown(n, 160) * np.clip(t / 0.35, 0, 1) * np.exp(-np.maximum(t - 0.35, 0) * 6)
    rise = np.sin(2 * math.pi * np.cumsum(ramp(n, 60, 140, 0.0, 0.35)) / SR) * np.clip(t / 0.3, 0, 1) * np.exp(-np.maximum(t - 0.35, 0) * 8) * 0.6
    chime = np.zeros(n)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        start = int((0.3 + k * 0.06) * SR)
        b = bell(f, dur - start / SR, 3.0)
        chime[start:start + len(b)] += b * 0.5
    return normalize(room(normalize(rumble) * 0.7 + rise + chime, 0.3), 0.75)


def spell_raise():
    dur = 1.0
    n = int(dur * SR)
    t = t_axis(dur)
    rumble = brown(n, 90) * np.clip(t / 0.08, 0, 1) * np.exp(-t * 2.2)
    heave = np.sin(2 * math.pi * np.cumsum(ramp(n, 45, 95, 0.0, 0.4)) / SR) * np.exp(-t * 3.0)
    grind = resonator(noise(n), ramp(n, 300, 700, 0, 0.45), 250) * np.exp(-t * 4.0) * 0.5
    thud = np.sin(2 * math.pi * 70 * t) * np.exp(-np.maximum(t - 0.42, 0) * 14) * (t > 0.42) * 0.9
    return normalize(normalize(rumble) + heave + normalize(grind) * 0.4 + thud, 0.8)


def fizzle():
    dur = 0.45
    n = int(dur * SR)
    t = t_axis(dur)
    puff = resonator(noise(n), ramp(n, 2600, 700, 0, 0.3), 700) * np.exp(-t * 9) * np.minimum(t / 0.01, 1)
    down = np.sin(2 * math.pi * np.cumsum(ramp(n, 620, 180, 0, 0.3)) / SR) * np.exp(-t * 8) * 0.35
    return normalize(normalize(puff) + down, 0.5)


def write(name, data):
    path = os.path.join(OUT, name + ".wav")
    pcm = np.clip(data, -1, 1)
    pcm = (pcm * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    for name, kind, f0 in [("syl_ah", "ah", 220.0), ("syl_bra", "bra", 261.63), ("syl_ca", "ca", 293.66), ("syl_da", "da", 329.63)]:
        write(name, syllable(kind, f0))
    write("spell_push", spell_push())
    write("spell_pit", spell_pit())
    write("spell_mend", spell_mend())
    write("spell_raise", spell_raise())
    write("fizzle", fizzle())
