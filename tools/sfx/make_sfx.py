#!/usr/bin/env python3
"""Synthesizes Burn Rate's sound effects, ambiences, stingers and music.

    python3 tools/sfx/make_sfx.py [--out assets/audio] [--only name,name] [--wav dir] [--list]

Everything is built here from oscillators, noise, filters and envelopes (no
samples), with a fixed random seed from each sound's name, so the files can
be made again exactly. The building blocks follow Hull Bloom's and Tiptoe's
synthesizers, with scipy's filters for speed and a small subtractive synth
(band-limited saws and squares, supersaws, resonant filter sweeps, FM bells)
for the music.

Sound effects are mono at 44.1 kHz, peak-normalised to about -3 dBFS and
encoded to Ogg Vorbis with ffmpeg (-q:a 4) in <out>/sfx. Names ending in
_loop loop seamlessly: every oscillator runs a whole number of cycles, noise
is shaped in the frequency domain, filters run over two copies and keep the
second, and events wrap round the end; they are encoded at -q:a 6, which
keeps the encoder's noise from leaving a tick at the seam. Ambiences (amb_*)
are quiet room tones per zone, also loops.

The music goes to <out>/music, stereo:

  run_*    the run's track, 128 BPM in A minor, sixteen bars (30 s), as six
           stems that loop together: pad, drums, bass, arp, lead and hype.
           The game layers them as the pilot's Burn rises.
  party_*  Last One Flying, 136 BPM in D minor, as three stems: base
           (drums and bass), lead and hype, added as pilots go out.
  title    the title screen, 100 BPM, one stereo loop.

Stems share one gain, so they keep their balance however they're layered;
the whole mix is set to a loudness (LUFS) with its peak under -1 dBFS.

Needs numpy, scipy and ffmpeg (with libvorbis).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np
from scipy import signal

SR = 44100
TAU = 2 * np.pi
PEAK = 10 ** (-3 / 20)


# ---------------------------------------------------------------------------
# Basics

def secs(seconds):
    return int(round(seconds * SR))


def timeline(seconds):
    return np.arange(secs(seconds)) / SR


def rng_for(name):
    """A random generator seeded from the sound's name, so every sound is repeatable."""
    return np.random.default_rng(zlib.crc32(name.encode()))


def norm(x):
    m = np.abs(x).max()
    return x / m if m > 0 else x


def rms(x):
    return float(np.sqrt(np.mean(np.square(x)))) + 1e-12


def env_ar(t, attack, tau, start=0.0):
    """Linear attack then exponential decay, silent before start."""
    u = t - start
    rise = np.clip(u / attack, 0, 1) if attack > 0 else 1.0
    return rise * np.exp(-np.maximum(u - attack, 0) / tau) * (u >= 0)


def gate(t, length, attack=0.003, release=0.05):
    """On for `length` seconds with short ramps, then a release."""
    up = np.clip(t / attack, 0, 1) if attack > 0 else np.ones_like(t)
    down = np.clip(1 - (t - length) / release, 0, 1)
    return up * np.where(t < length, 1.0, down)


def curve(t, times, values):
    """Piecewise-linear breakpoint curve."""
    return np.interp(t, times, values)


def bump(t, start, length, power=1.0):
    """A raised-sine swell from start to start + length, zero outside it."""
    p = np.clip((t - start) / length, 0, 1)
    return np.sin(np.pi * p) ** power


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def cyc(f, length):
    """f rounded to a whole number of cycles in `length` seconds, so a loop of it is seamless."""
    return max(1, round(f * length)) / length


def fold(x, n):
    """Wraps x into length n (anything past the end adds in at the start)."""
    m = x.shape[-1]
    if m <= n:
        return x
    out = np.zeros(x.shape[:-1] + (n,))
    for i in range(0, m, n):
        part = x[..., i:i + n]
        out[..., :part.shape[-1]] += part
    return out


def place(buf, x, at, wrap=False, gain=1.0):
    """Mixes x (mono or stereo) into buf (mono or stereo) at time `at`; with wrap, whatever
    runs past the end comes round to the start."""
    i = secs(at)
    n = buf.shape[-1]
    if buf.ndim == 2 and x.ndim == 1:
        x = np.stack([x, x])
    elif buf.ndim == 1 and x.ndim == 2:
        x = x.mean(axis=0)
    x = x * gain
    if wrap:
        x = fold(x, n)
        i %= n
        m = x.shape[-1]
        first = min(m, n - i)
        buf[..., i:i + first] += x[..., :first]
        if m > first:
            buf[..., :m - first] += x[..., first:]
    else:
        if i >= n:
            return buf
        j = min(n, i + x.shape[-1])
        buf[..., i:j] += x[..., :j - i]
    return buf


def stereo(x, pan=0.0):
    """A mono sound placed left (-1) to right (1), constant power."""
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)]) * np.sqrt(2)


# ---------------------------------------------------------------------------
# Filters

def biquad(kind, f, q=0.707, gain_db=0.0):
    """RBJ-cookbook biquad coefficients: lp, hp, bp (0 dB peak) or peak (an EQ bell)."""
    f = float(np.clip(f, 10.0, SR * 0.45))
    w = TAU * f / SR
    cw, sw = np.cos(w), np.sin(w)
    alpha = sw / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:
        g = 10 ** (gain_db / 40)
        b = [1 + alpha * g, -2 * cw, 1 - alpha * g]
        a = [1 + alpha / g, -2 * cw, 1 - alpha / g]
    return np.array(b) / a[0], np.array(a) / a[0]


def filt(x, kind, f, q=0.707, loop=False, order=1, gain_db=0.0):
    """A static filter along the last axis. With loop, it runs over two copies and keeps the
    second, so the result loops as seamlessly as the input."""
    b, a = biquad(kind, f, q, gain_db)
    for _ in range(order):
        if loop:
            n = x.shape[-1]
            x = signal.lfilter(b, a, np.concatenate([x, x], axis=-1), axis=-1)[..., n:]
        else:
            x = signal.lfilter(b, a, x, axis=-1)
    return x


def lp(x, f, q=0.707, loop=False, order=1):
    return filt(x, "lp", f, q, loop, order)


def hp(x, f, q=0.707, loop=False, order=1):
    return filt(x, "hp", f, q, loop, order)


def bp(x, f, q=1.0, loop=False, order=1):
    return filt(x, "bp", f, q, loop, order)


def eq(x, f, gain_db, q=1.0, loop=False):
    return filt(x, "peak", f, q, loop, 1, gain_db)


def sweep(x, fc, q=0.707, kind="lp", block=32):
    """A filter whose cutoff moves (fc per sample), worked in short blocks. Stereo works too."""
    if x.ndim == 2:
        return np.stack([sweep(c, fc, q, kind, block) for c in x])
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    y = np.empty_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        b, a = biquad(kind, fc[i], q)
        y[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return y


def lp_mag(f, fc, order=2):
    return 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp_mag(f, fc, order=2):
    return 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order))


def bp_mag(f, fc, q):
    """A resonant peak's magnitude at f: 1 at fc, falling away with the bandwidth fc / q."""
    return 1 / np.sqrt(1 + (q * (f / fc - fc / np.maximum(f, 1e-3))) ** 2)


def loop_noise(rng, n, shape):
    """Noise of length n shaped in the frequency domain by shape(freqs); periodic, so it loops."""
    spectrum = np.fft.rfft(rng.standard_normal(n)) * shape(np.fft.rfftfreq(n, 1 / SR))
    y = np.fft.irfft(spectrum, n)
    return y / (y.std() + 1e-12)


def noise(rng, n):
    return rng.standard_normal(n)


# ---------------------------------------------------------------------------
# Oscillators (band-limited with polyBLEP)

def _phase(freq, n, ph0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    inc = f / SR
    ph = ph0 + np.concatenate(([0.0], np.cumsum(inc[:-1])))
    return ph, inc


def _blep(t, dt):
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1
    m = t > 1 - dt
    x = (t[m] - 1) / dt[m]
    y[m] = x * x + x + x + 1
    return y


def saw(freq, n, ph0=0.0):
    ph, dt = _phase(freq, n, ph0)
    t = ph % 1.0
    return 2 * t - 1 - _blep(t, dt)


def square(freq, n, ph0=0.0, pw=0.5):
    ph, dt = _phase(freq, n, ph0)
    t1 = ph % 1.0
    t2 = (ph + pw) % 1.0
    return (2 * t1 - 1 - _blep(t1, dt)) - (2 * t2 - 1 - _blep(t2, dt))


def sine(freq, n, ph0=0.0):
    ph, _ = _phase(freq, n, ph0)
    return np.sin(TAU * ph)


def tri(freq, n, ph0=0.0):
    ph, _ = _phase(freq, n, ph0)
    return 4 * np.abs(ph % 1.0 - 0.5) - 1


def supersaw(freq, n, rng, voices=7, spread=0.18, width=1.0):
    """Detuned saws (spread in semitones either side) panned across the stereo field."""
    left = np.zeros(n)
    right = np.zeros(n)
    for k, o in enumerate(np.linspace(-1, 1, voices)):
        v = saw(np.asarray(freq) * 2 ** (o * spread / 12), n, rng.uniform())
        w = 1.0 if abs(o) < 1e-6 else 0.75
        pan = 0.5 + 0.5 * o * width
        left += w * v * np.cos(pan * np.pi / 2)
        right += w * v * np.sin(pan * np.pi / 2)
    return np.stack([left, right]) * np.sqrt(2) / np.sqrt(voices)


def fm_bell(freq, length, ratio=3.5, index=3.0, tau=0.6, itau=0.25):
    """An FM bell or chime: a sine carrier with a decaying modulator."""
    t = timeline(length)
    mod = index * np.exp(-t / itau) * np.sin(TAU * freq * ratio * t)
    return np.sin(TAU * freq * t + mod) * env_ar(t, 0.001, tau)


# ---------------------------------------------------------------------------
# Effects

def drive(x, amount):
    """Soft saturation that keeps the peak at most 1."""
    return np.tanh(amount * x) / np.tanh(amount)


def reverb_ir(rng, seconds, bright=5000.0, predelay=0.012):
    """A stereo room: two decorrelated decaying noises whose highs die first."""
    t = timeline(seconds)
    tau = seconds / 6.9
    chans = []
    for _ in range(2):
        lo = lp(rng.standard_normal(len(t)), bright) * np.exp(-t / tau)
        hi = hp(rng.standard_normal(len(t)), bright) * np.exp(-t / (tau / 3))
        ir = (lo + 0.35 * hi) * np.clip((t - predelay) / 0.004, 0, 1)
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return np.stack(chans)


def reverb(x, rng, seconds=1.2, wet=0.2, bright=5000.0, loop=False):
    """The dry sound plus `wet` of a stereo room (returns stereo)."""
    xs = x if x.ndim == 2 else np.stack([x, x])
    ir = reverb_ir(rng, seconds, bright)
    n = xs.shape[-1]
    out = np.empty_like(xs)
    for c in range(2):
        if loop:
            k = fold(ir[c], n)
            k = np.pad(k, (0, n - len(k)))
            out[c] = xs[c] + wet * np.fft.irfft(np.fft.rfft(xs[c]) * np.fft.rfft(k), n)
        else:
            out[c] = xs[c] + wet * signal.fftconvolve(xs[c], ir[c])[:n]
    return out


def echo(x, time, feedback=0.4, wet=0.3, taps=6, pingpong=True, loop=True, tone=4000.0):
    """Repeats every `time` seconds, each quieter and darker; ping-pong bounces them left and
    right. With loop the repeats wrap round."""
    xs = x if x.ndim == 2 else np.stack([x, x])
    n = xs.shape[-1]
    out = xs.copy()
    d = secs(time)
    tap = xs.copy()
    for k in range(1, taps + 1):
        tap = lp(tap, tone, loop=loop)
        g = wet * feedback ** (k - 1)
        moved = np.roll(tap, k * d, axis=-1) if loop else np.pad(tap, ((0, 0), (k * d, 0)))[..., :n]
        if pingpong:
            side = k % 2
            out[side] += g * moved.mean(axis=0) * 1.2
            out[1 - side] += g * moved.mean(axis=0) * 0.3
        else:
            out += g * moved
    return out


def duck_curve(n, hits, depth=0.6, release=0.2):
    """Sidechain pumping: 1, dipping by `depth` at each hit (seconds) and coming back over
    `release`. Hits wrap round the loop."""
    curve_ = np.ones(n)
    shape_t = timeline(release)
    shape = depth * np.clip(shape_t / 0.004, 0, 1) * (1 - shape_t / release) ** 2
    dips = np.zeros(n)
    for h in hits:
        place(dips, shape, h, wrap=True)
    return np.clip(curve_ - dips, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Drums

def kick(rng, f_hi=170.0, f_lo=52.0, tau=0.15, punch=0.03, click=0.5, length=0.5):
    t = timeline(length)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / punch)
    body = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / tau) * np.clip(t / 0.0015, 0, 1)
    tick = hp(rng.standard_normal(len(t)) * env_ar(t, 0.0003, 0.004), 1800) * click
    tick += click * 0.6 * np.sin(TAU * 1200 * t) * env_ar(t, 0.0002, 0.006)
    return drive(body + tick, 1.6)


def clap(rng, length=0.35, f=1300.0):
    t = timeline(length)
    n = rng.standard_normal(len(t))
    bursts = sum(env_ar(t, 0.0005, 0.006, s) for s in (0.0, 0.011, 0.021))
    tail = env_ar(t, 0.0005, 0.09, 0.03)
    x = bp(n * (bursts + 0.8 * tail), f, 0.9) + 0.4 * hp(n * tail, 3500)
    return norm(x)


def snare(rng, length=0.3, tone=190.0, snap=0.12):
    t = timeline(length)
    body = (np.sin(TAU * tone * t) + 0.5 * np.sin(TAU * tone * 1.73 * t)) * env_ar(t, 0.001, 0.05)
    n = rng.standard_normal(len(t))
    rattle = hp(bp(n, 4200, 0.7), 1500) * env_ar(t, 0.0008, snap)
    return norm(0.7 * body + rattle)


def hat(rng, length=0.06, decay=0.025, bright=8000.0):
    """A hi-hat: the 808's six square waves plus noise, high-passed and short."""
    t = timeline(length)
    metal = sum(square(f, len(t), rng.uniform()) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0))
    x = hp(bp(metal, 10000, 0.8) + 0.8 * rng.standard_normal(len(t)), bright, order=2)
    return norm(x * env_ar(t, 0.0004, decay))


def crash(rng, length=2.2, decay=0.6):
    t = timeline(length)
    metal = sum(square(f * rng.uniform(0.98, 1.02), len(t), rng.uniform())
                for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0, 1131.0, 1471.0))
    x = hp(0.5 * bp(metal, 7000, 0.6) + rng.standard_normal(len(t)), 3500, order=2)
    x = lp(x, 12000)
    return norm(x * (env_ar(t, 0.001, decay) * 0.7 + 0.3 * env_ar(t, 0.001, 0.08)))


def shaker(rng, length=0.07):
    t = timeline(length)
    x = bp(rng.standard_normal(len(t)), 6500, 1.2) * env_ar(t, 0.012, 0.02)
    return norm(x)


def tom(rng, f=130.0, length=0.35):
    t = timeline(length)
    fr = f * (0.75 + 0.25 * np.exp(-t / 0.05))
    x = np.sin(TAU * np.cumsum(fr) / SR) * env_ar(t, 0.001, 0.16)
    x += 0.2 * hp(rng.standard_normal(len(t)), 2000) * env_ar(t, 0.0005, 0.01)
    return norm(drive(x, 1.4))


# ---------------------------------------------------------------------------
# Synth voices

def bass_note(rng, f, length, vel=1.0, bright=1.0):
    """A punchy synth bass: a saw and a square with a sub, through a resonant low-pass that
    snaps open on each note."""
    t = timeline(length + 0.06)
    n = len(t)
    x = saw(f, n) + 0.45 * square(f * 1.004, n, 0.25) + 0.7 * sine(f * 0.5, n)
    fc = 120 + bright * (300 + 1500 * vel) * np.exp(-t / 0.07)
    x = sweep(x, fc, 1.6)
    return drive(x * gate(t, length, 0.002, 0.04) * (0.6 + 0.4 * vel), 1.8)


def reese_note(rng, f, length, vel=1.0):
    """A growling reese bass: two detuned saws beating, with a sub, a filter that breathes."""
    t = timeline(length + 0.06)
    n = len(t)
    x = saw(f * 1.006, n, rng.uniform()) + saw(f * 0.994, n, rng.uniform()) + 0.8 * sine(f * 0.5, n)
    fc = 260 + 900 * vel * np.exp(-t / 0.12) + 200 * (0.5 + 0.5 * np.sin(TAU * 3.0 * t))
    x = sweep(x, fc, 1.3)
    return drive(x * gate(t, length, 0.003, 0.04), 2.2)


def pluck(rng, f, length=0.2, vel=1.0, decay=0.22):
    """A bright pluck for arpeggios."""
    t = timeline(length + decay * 2)
    n = len(t)
    x = 0.7 * saw(f, n, rng.uniform()) + 0.5 * square(f * 1.003, n, rng.uniform(), 0.3)
    fc = 350 + 6500 * vel * np.exp(-t / 0.08)
    x = sweep(x, fc, 1.1)
    return x * env_ar(t, 0.002, decay) * vel


def lead_note(rng, f, length, vel=1.0, vib=0.18):
    """The lead: a supersaw over a square an octave down, with vibrato that grows on held notes."""
    t = timeline(length + 0.15)
    n = len(t)
    depth = vib * np.clip((t - 0.16) / 0.25, 0, 1)
    fr = f * 2 ** (depth * np.sin(TAU * 5.6 * t) / 12)
    x = supersaw(fr, n, rng, 5, 0.14)
    x += 0.35 * stereo(square(fr * 0.5, n, rng.uniform(), 0.4))
    fc = 3400 + 4000 * np.exp(-t / 0.12)
    x = sweep(x, fc, 0.9)
    env = gate(t, length, 0.006, 0.12) * (0.82 + 0.18 * np.exp(-t / 0.08))
    return x * env * vel


def pad_chord(rng, notes, length, bright=2000.0):
    """A soft, wide chord: detuned saws through a gentle low-pass, slow in and out."""
    t = timeline(length + 0.8)
    n = len(t)
    x = np.zeros((2, n))
    for m in notes:
        x += supersaw(mtof(m), n, rng, 5, 0.22)
    x = lp(x, bright, 0.6, order=2)
    return x * gate(t, length, 0.25, 0.7) / len(notes)


def stab(rng, notes, length=0.16, bright=1.0):
    """A short supersaw chord stab, its filter snapping shut."""
    t = timeline(length + 0.25)
    n = len(t)
    x = np.zeros((2, n))
    for m in notes:
        x += supersaw(mtof(m), n, rng, 5, 0.2)
    fc = 600 + bright * 5500 * np.exp(-t / 0.09)
    x = sweep(x, fc, 1.0)
    return x * env_ar(t, 0.002, 0.13) / len(notes)


def brass(rng, notes, length, bright=1.0):
    """A synth brass chord for fanfares: saws whose filter swells open."""
    t = timeline(length + 0.4)
    n = len(t)
    x = np.zeros((2, n))
    for m in notes:
        x += supersaw(mtof(m), n, rng, 5, 0.12)
    fc = 500 + bright * 4000 * np.clip(t / 0.12, 0, 1) * (0.6 + 0.4 * np.exp(-t / 0.4))
    x = sweep(x, fc, 1.2)
    return x * gate(t, length, 0.02, 0.3) / len(notes)


# ---------------------------------------------------------------------------
# Sound-effect building blocks

def thump(rng, t, start, f_hi=120.0, f_lo=45.0, tau=0.12, slap=0.5):
    """Something heavy landing: a falling low thud and a dull slap."""
    u = np.maximum(t - start, 0)
    fr = f_lo + (f_hi - f_lo) * np.exp(-u / 0.03)
    body = np.sin(TAU * np.cumsum(fr) / SR) * env_ar(t, 0.002, tau, start)
    hit = lp(rng.standard_normal(len(t)) * env_ar(t, 0.0005, 0.015, start), 1800)
    return body + slap * hit / (np.abs(hit).max() + 1e-12)


def modes(t, freqs, amps, taus, start=0.0):
    """Struck resonances: decaying sines that start at zero phase (no click)."""
    u = np.maximum(t - start, 0)
    out = np.zeros_like(t)
    for f, a, tau in zip(freqs, amps, taus):
        out += a * np.sin(TAU * f * u) * np.exp(-u / tau)
    return out * (t >= start)


def metal_hit(rng, t, start, base=420.0, size=1.0, ring=0.25):
    """A struck steel panel: inharmonic modes and a bright crack."""
    ratios = np.array([1.0, 1.58, 2.31, 2.97, 3.84, 5.12, 6.7])
    freqs = base * ratios * rng.uniform(0.96, 1.04, len(ratios))
    amps = rng.uniform(0.4, 1.0, len(ratios)) / np.arange(1, len(ratios) + 1) ** 0.4
    taus = ring * size * rng.uniform(0.5, 1.0, len(ratios)) / np.sqrt(ratios)
    crack = hp(rng.standard_normal(len(t)) * env_ar(t, 0.0003, 0.006, start), 2500)
    return modes(t, freqs, amps, taus, start) + 0.6 * crack


def whoosh(rng, length, f0, f1, q=2.0, power=1.5, peak_at=0.5):
    """Air rushing past: noise through a band that sweeps from f0 to f1, in a swell that
    peaks at `peak_at` of the way through."""
    t = timeline(length)
    p = t / length
    fc = f0 * (f1 / f0) ** p
    x = sweep(rng.standard_normal(len(t)), fc, q, "bp")
    shape = np.where(p < peak_at, (p / peak_at), (1 - p) / (1 - peak_at))
    return norm(x * np.clip(shape, 0, 1) ** power)


def zap(rng, length, f=120.0, crackle=1.0):
    """Electricity: a buzzing, torn-up square with random sparks."""
    t = timeline(length)
    n = len(t)
    buzz = np.tanh(3 * square(f * (1 + 0.02 * np.sin(TAU * 7 * t)), n, rng.uniform(), 0.3))
    sparks = np.zeros(n)
    for _ in range(int(60 * length * crackle)):
        at = rng.uniform(0, length)
        s = timeline(rng.uniform(0.002, 0.012))
        place(sparks, rng.uniform(0.3, 1.0) * rng.standard_normal(len(s)) * np.exp(-s / 0.003), at)
    sparks = hp(sparks, 2500)
    return norm(0.6 * hp(buzz, 150) + crackle * sparks)


def sparkle(rng, length, notes, every=0.035, tau=0.12, level=1.0):
    """A run of little chimes up through `notes`."""
    out = np.zeros(secs(length) + secs(0.6))
    for i, m in enumerate(notes):
        place(out, level * fm_bell(mtof(m), 0.6, 2.0, 1.4, tau, 0.05), i * every)
    return out[:secs(length) + secs(0.6)]


def grunt(rng, f0a, f0b, length, vowel=(640, 1190, 2390), breath=0.3, end_f=0.0):
    """A short non-verbal grunt ("oof", "uh"): a glottal buzz with a falling pitch through a
    vowel's formants, a puff of breath, and an optional "f" at the end."""
    t = timeline(length)
    n = len(t)
    f0 = f0a + (f0b - f0a) * np.clip(t / length, 0, 1) ** 0.7
    f0 = f0 * (1 + 0.02 * np.sin(TAU * 9 * t))
    src = saw(f0, n, rng.uniform())
    src = lp(src, 3000)
    x = sum(w * bp(src, F, F / bw) for F, bw, w in zip(vowel, (90, 120, 180), (1.0, 0.6, 0.25)))
    x = norm(x) * env_ar(t, 0.012, length * 0.35)
    air = bp(rng.standard_normal(n), vowel[1], 1.0) * env_ar(t, 0.01, length * 0.3) * breath
    out = x + air
    if end_f:
        fz = hp(rng.standard_normal(n), 2500) * bump(t, length * 0.45, length * 0.55) * end_f
        out = out + fz
    return norm(out)


# ---------------------------------------------------------------------------
# The pilot: burners, feet and falls

BURNER_LEN = 2.0


def roar_noise(rng, n, peak, q, low, high, tilt=0.5):
    return loop_noise(rng, n, lambda f: hp_mag(f, low) * lp_mag(f, high, 2) * (0.25 + bp_mag(f, peak, q))
                      / np.maximum(f, 30) ** tilt)


def flutter(rng, n, rate, depth):
    """A loopable random flutter around 1, wandering about `rate` times a second."""
    w = loop_noise(rng, n, lambda f: lp_mag(f, rate, 2))
    return 1 + depth * w


def crackles(rng, n, rate, f_lo=1500, f_hi=6000, tau=0.002):
    """Pops scattered round a loop, for burners that spit."""
    out = np.zeros(n)
    s = timeline(0.03)
    for _ in range(int(rate * n / SR)):
        f = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        pop = np.sin(TAU * f * s) * np.exp(-s / tau) + 0.7 * rng.standard_normal(len(s)) * np.exp(-s / (tau * 0.6))
        place(out, rng.uniform(0.2, 1.0) * pop, rng.uniform(0, n / SR), wrap=True)
    return out


def burner_k1_loop(rng):
    """K-1 Steady: a full, even roar with a gentle flutter."""
    n = secs(BURNER_LEN)
    roar = roar_noise(rng, n, 650, 0.8, 70, 6000)
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 35) * lp_mag(f, 180, 2))
    hiss = loop_noise(rng, n, lambda f: bp_mag(f, 5200, 1.2))
    x = roar * flutter(rng, n, 24, 0.25) + 0.5 * rumble + 0.12 * hiss
    return x


def burner_k2_loop(rng):
    """K-2 Kick: two burners beating against each other, harsher and spitting."""
    n = secs(BURNER_LEN)
    a = roar_noise(rng, n, 900, 0.9, 80, 8000, 0.35) * flutter(rng, n, 31, 0.35)
    b = roar_noise(rng, n, 1250, 1.1, 80, 8000, 0.35) * flutter(rng, n, 37, 0.35)
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 40) * lp_mag(f, 220, 2))
    x = a + b + 0.6 * rumble
    x = np.tanh(1.8 * x / np.abs(x).max() * 2.0)
    x += 0.5 * crackles(rng, n, 26)
    return x


def burner_k3_loop(rng):
    """K-3 Glide: a soft, airy hiss with little rumble."""
    n = secs(BURNER_LEN)
    air = roar_noise(rng, n, 2200, 0.5, 250, 9000, 0.25) * flutter(rng, n, 8, 0.12)
    body = roar_noise(rng, n, 500, 0.7, 90, 2500, 0.4)
    return air + 0.35 * body


def burner_k4_loop(rng):
    """K-4 Pulse: between kicks, only a pilot light's hiss and a low putter."""
    n = secs(BURNER_LEN)
    hiss = roar_noise(rng, n, 2600, 0.8, 400, 8000, 0.2)
    put = loop_noise(rng, n, lambda f: hp_mag(f, 50) * lp_mag(f, 400, 2))
    t = np.arange(n) / SR
    putter = put * (0.5 + 0.5 * np.sin(TAU * cyc(11, BURNER_LEN) * t)) ** 3
    return 0.5 * hiss + putter


def burner_k5_loop(rng):
    """K-5 Switch: the K-1's roar with a turbine's whine in it."""
    n = secs(BURNER_LEN)
    t = np.arange(n) / SR
    roar = roar_noise(rng, n, 800, 0.8, 70, 7000) * flutter(rng, n, 20, 0.2)
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 35) * lp_mag(f, 180, 2))
    whine = sum(a * np.sin(TAU * cyc(f, BURNER_LEN) * t + rng.uniform(0, TAU))
                for f, a in ((1420, 1.0), (2840, 0.4), (4260, 0.2), (1433, 0.6)))
    whine *= 1 + 0.2 * np.sin(TAU * cyc(3, BURNER_LEN) * t)
    return roar + 0.45 * rumble + 0.18 * whine


def burner_k6_loop(rng):
    """K-6 Mule: a deep, heavy roar that throbs."""
    n = secs(BURNER_LEN)
    t = np.arange(n) / SR
    roar = roar_noise(rng, n, 260, 0.7, 40, 3500, 0.55)
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 28) * lp_mag(f, 120, 3))
    throb = 1 + 0.3 * np.sin(TAU * cyc(7, BURNER_LEN) * t)
    tone = sum(a * np.sin(TAU * cyc(f, BURNER_LEN) * t + rng.uniform(0, TAU)) for f, a in ((55, 1.0), (110, 0.5), (165, 0.25)))
    x = (roar * flutter(rng, n, 16, 0.25) + 1.1 * rumble) * throb + 0.25 * tone * throb
    return np.tanh(1.5 * x / np.abs(x).max()) * 1.0


def burner_k4_kick(rng):
    """One kick of the K-4: a hard chuff with a thump under it."""
    t = timeline(0.32)
    n = len(t)
    body = thump(rng, t, 0.0, 140, 55, 0.07, 0.3)
    chuff = lp(rng.standard_normal(n), 1800) * env_ar(t, 0.002, 0.05)
    burst = bp(rng.standard_normal(n), 900, 0.8) * env_ar(t, 0.001, 0.03)
    return drive(norm(1.0 * body + 0.9 * norm(chuff) + 0.6 * norm(burst)), 1.8)


def burner_ignite(rng):
    """The burner catching: a quick "fwump"."""
    t = timeline(0.4)
    n = len(t)
    fc = 300 + 2500 * np.clip(t / 0.05, 0, 1) * np.exp(-t / 0.15)
    x = sweep(rng.standard_normal(n), fc, 0.9) * env_ar(t, 0.008, 0.11)
    return norm(norm(x) + 0.6 * thump(rng, t, 0.0, 110, 50, 0.06, 0.0))


def burner_sputter(rng):
    """A burner dying in a crash: coughs and pops, thinning out, then a last fizz."""
    L = 1.2
    t = timeline(L)
    out = np.zeros(len(t))
    at = 0.0
    k = 0
    while at < 0.9:
        s = timeline(0.12)
        cough = lp(rng.standard_normal(len(s)), rng.uniform(900, 2200)) * env_ar(s, 0.002, rng.uniform(0.02, 0.05))
        place(out, (1 - at / 1.1) * rng.uniform(0.5, 1.0) * norm(cough), at)
        place(out, 0.4 * thump(rng, s, 0.0, 120, 60, 0.03, 0.0), at)
        at += rng.uniform(0.04, 0.09) * (1 + k * 0.18)
        k += 1
    fizz = hp(rng.standard_normal(len(t)), 3000) * bump(t, 0.7, 0.5, 2) * 0.25
    return out + fizz


def thruster_hiss(rng):
    """The K-5's side thrusters: a short, sharp "pssht"."""
    t = timeline(0.28)
    fc = 2500 + 3000 * np.clip(t / 0.05, 0, 1)
    x = sweep(rng.standard_normal(len(t)), fc, 1.2, "bp") * env_ar(t, 0.004, 0.07)
    x += 0.3 * hp(rng.standard_normal(len(t)), 6000) * env_ar(t, 0.002, 0.03)
    return x


def lane_swish(rng):
    """A lane change: a quick swish of air."""
    return whoosh(rng, 0.2, 700, 2200, 1.6, 1.4, 0.35)


def rocket_loop(rng):
    """The head start's rocket: a huge crackling roar."""
    n = secs(BURNER_LEN)
    roar = roar_noise(rng, n, 450, 0.6, 40, 7000, 0.45) * flutter(rng, n, 28, 0.3)
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 28) * lp_mag(f, 140, 3))
    x = roar + 1.0 * rumble
    x = np.tanh(2.0 * x / np.abs(x).max())
    return x + 0.35 * crackles(rng, n, 60, 1200, 5000, 0.003)


def rocket_end(rng):
    """The rocket burning out: the roar falls away and the casing pings off."""
    t = timeline(1.1)
    n = len(t)
    fc = 3000 * np.exp(-t / 0.25) + 150
    roar = sweep(rng.standard_normal(n), fc, 0.8) * env_ar(t, 0.005, 0.3)
    ping = metal_hit(rng, t, 0.12, 900, 0.8, 0.3) * 0.25
    return norm(roar) + ping


def land_thump(rng):
    """Feet hitting the floor plates hard."""
    t = timeline(0.45)
    x = thump(rng, t, 0.0, 130, 55, 0.08, 0.6)
    ring = modes(t, [178, 403, 761, 1210], [1.0, 0.6, 0.35, 0.2], [0.12, 0.08, 0.05, 0.03]) * 0.25
    return x + ring


def footstep(rng):
    """A running step on the floor plates: a heel's thud and the sole's scuff."""
    t = timeline(0.16)
    n = len(t)
    heel = thump(rng, t, 0.0, rng.uniform(150, 190), 70, 0.03, 0.4)
    scuff = bp(rng.standard_normal(n), rng.uniform(1800, 3000), 1.2) * env_ar(t, 0.004, 0.02, 0.01)
    plate = modes(t, [410, 980, 1630], [1.0, 0.5, 0.3], [0.03, 0.02, 0.015]) * 0.15
    return heel + 0.35 * norm(scuff) + plate


def crash_hit(rng):
    """The pilot going down: a body hitting the floor, the pack clattering and skidding."""
    t = timeline(1.3)
    n = len(t)
    x = 1.2 * thump(rng, t, 0.0, 120, 45, 0.15, 0.8)
    x += 0.6 * metal_hit(rng, t, 0.01, 520, 1.0, 0.3)
    for at in (0.16, 0.27, 0.36):
        x += 0.3 * metal_hit(rng, t, at, rng.uniform(600, 900), 0.6, 0.15)
        x += 0.4 * thump(rng, t, at, 110, 60, 0.05, 0.3)
    grit = bp(rng.standard_normal(n), 2400, 0.7) * bump(t, 0.05, 1.1, 0.6) * 0.15
    return x + grit


def crash_slide_loop(rng):
    """Sliding along the floor on the pack: a gritty scrape with metal squeal in it."""
    L = 1.5
    n = secs(L)
    t = np.arange(n) / SR
    grit = loop_noise(rng, n, lambda f: bp_mag(f, 1800, 0.8) * hp_mag(f, 300))
    rough = flutter(rng, n, 60, 0.6)
    squeal = sum(a * np.sin(TAU * cyc(f, L) * t + rng.uniform(0, TAU)) for f, a in ((2310, 1.0), (3570, 0.5)))
    squeal *= np.clip(flutter(rng, n, 3, 0.9) - 0.6, 0, None)
    return grit * np.clip(rough, 0.1, None) + 0.25 * squeal


def shield_pop(rng):
    """The shield taking a hit: a glassy pop and a shimmer falling away."""
    t = timeline(0.8)
    n = len(t)
    pop = np.sin(TAU * np.cumsum(300 + 1500 * np.clip(t / 0.03, 0, 1)) / SR) * env_ar(t, 0.001, 0.04)
    shatter = hp(rng.standard_normal(n), 4000) * env_ar(t, 0.001, 0.06)
    shimmer = sum(fm_bell(f, 0.8, 1.41, 1.0, 0.3, 0.1) for f in (1760, 2217, 2637)) / 3
    return norm(pop + 0.5 * shatter + 0.6 * shimmer)


def armour_clank(rng):
    """The K-6's plating taking a hit: a heavy clank and a dent."""
    t = timeline(0.8)
    return thump(rng, t, 0.0, 140, 60, 0.08, 0.5) + 0.9 * metal_hit(rng, t, 0.0, 300, 1.2, 0.35)


def reboot(rng):
    """A reboot: the pack powers down with a falling whine, then chirps back up."""
    t = timeline(1.3)
    n = len(t)
    down = saw(900 * np.exp(-t / 0.18) + 60, n) * env_ar(t, 0.002, 0.2)
    down = lp(down, 2500) * 0.5
    up = np.zeros(n)
    for i, m in enumerate((69, 76, 81, 88)):
        s = timeline(0.12)
        place(up, square(mtof(m), len(s), 0.0, 0.25) * env_ar(s, 0.002, 0.05) * 0.3, 0.45 + i * 0.08)
    sweep_up = sine(200 * np.exp(np.clip(t - 0.45, 0, None) / 0.25), n) * bump(t, 0.45, 0.6) * 0.4
    return lp(down + up + sweep_up, 6000)


def stun(rng):
    """Party races: a hit that stuns you: a short electric jolt."""
    t = timeline(0.55)
    x = zap(rng, 0.55, 95, 1.5) * env_ar(t, 0.002, 0.18)
    return x + 0.6 * thump(rng, t, 0.0, 140, 60, 0.05, 0.3)


def out(rng):
    """Party races: a pilot falling off the edge: a falling "bwow-wow"."""
    t = timeline(1.0)
    n = len(t)
    f = mtof(69) * 2 ** (-14 * np.clip(t / 0.9, 0, 1) / 12) * (1 + 0.04 * np.sin(TAU * 7 * t))
    x = saw(f, n) + 0.5 * square(f * 0.5, n)
    x = sweep(x, 3000 * np.exp(-t / 0.5) + 300, 2.0)
    return x * env_ar(t, 0.01, 0.4)


# ---------------------------------------------------------------------------
# Hazards

def zapper_hum_loop(rng):
    """A zapper's arc: a mains buzz with the arc crackling through it."""
    L = 1.0
    n = secs(L)
    t = np.arange(n) / SR
    buzz = sum(a * np.sin(TAU * cyc(f, L) * t + rng.uniform(0, TAU))
               for f, a in ((120, 1.0), (240, 0.8), (360, 0.6), (480, 0.4), (600, 0.3), (840, 0.2), (1200, 0.15)))
    buzz = np.tanh(2.5 * buzz / np.abs(buzz).max())
    arc = loop_noise(rng, n, lambda f: bp_mag(f, 3200, 0.7)) * np.clip(flutter(rng, n, 40, 1.0) - 0.4, 0, None)
    pops = crackles(rng, n, 30, 2000, 7000, 0.0015)
    whine = np.sin(TAU * cyc(2400, L) * t) * 0.05
    return 0.6 * buzz + 0.25 * arc + 0.5 * pops + whine


def zapper_crackle(rng):
    """A zapper's arc snapping: a burst of sparks."""
    L = rng.uniform(0.18, 0.3)
    t = timeline(L)
    return zap(rng, L, 120, 2.0) * env_ar(t, 0.001, L * 0.35)


def laser_charge(rng):
    """A laser charging (1.6 s): a whine climbing and tightening, with ticks speeding up."""
    L = 1.6
    t = timeline(L)
    n = len(t)
    p = t / L
    f = 220 * (12 ** p ** 1.6)
    whine = sine(f, n) + 0.4 * sine(f * 2.01, n) + 0.2 * saw(f * 0.5, n)
    whine *= 0.25 + 0.75 * p ** 1.2
    hum = loop_noise(rng, n, lambda fr: bp_mag(fr, 2400, 1.5)) * p ** 2 * 0.25
    ticks = np.zeros(n)
    at = 0.0
    while at < L:
        s = timeline(0.02)
        place(ticks, np.sin(TAU * 3000 * s) * np.exp(-s / 0.003) * (0.3 + 0.7 * at / L), at)
        at += 0.16 * (1 - 0.85 * at / L)
    return lp(whine + hum + 0.35 * ticks, 9000) * np.clip((L - t) / 0.01, 0, 1)


def laser_fire(rng):
    """The beam firing across the screen: a crack and boom, then the beam's roar (0.9 s)."""
    L = 1.2
    t = timeline(L)
    n = len(t)
    boom = thump(rng, t, 0.0, 200, 50, 0.18, 0.8)
    crack = hp(rng.standard_normal(n), 2000) * env_ar(t, 0.0005, 0.03)
    beam = saw(110 * (1 + 0.01 * np.sin(TAU * 31 * t)), n) + saw(165.2, n, 0.3) + 0.6 * square(220.5, n)
    beam = bp(beam, 900, 0.6) + 0.5 * bp(rng.standard_normal(n), 3000, 0.8)
    beam *= gate(t, 0.85, 0.01, 0.25)
    return norm(1.0 * boom + 0.6 * crack) + 0.7 * norm(beam)


def seeker_beep(rng):
    """A seeker's tracking beep."""
    t = timeline(0.08)
    x = square(1760, len(t), 0.0, 0.5) * 0.6 + np.sin(TAU * 3520 * t) * 0.3
    return lp(x, 6000) * gate(t, 0.06, 0.002, 0.015)


def seeker_lock(rng):
    """Locked on: a fast, insistent double tone (0.45 s)."""
    t = timeline(0.47)
    f = np.where((t * 24).astype(int) % 2 == 0, 2093.0, 2637.0)
    x = square(f, len(t), 0.0, 0.5) * 0.5
    return lp(x, 7000) * gate(t, 0.44, 0.003, 0.02)


def seeker_launch(rng):
    """A seeker firing at the right edge: a hiss and a pop."""
    t = timeline(0.5)
    n = len(t)
    pop = thump(rng, t, 0.0, 300, 90, 0.04, 0.6)
    hiss = sweep(rng.standard_normal(n), 2000 + 3000 * np.clip(t / 0.1, 0, 1), 1.0, "bp") * env_ar(t, 0.005, 0.15)
    return norm(pop) * 0.7 + 0.6 * norm(hiss)


def seeker_whoosh(rng):
    """A seeker flying past: a rocket's roar swelling and gone (1.2 s, loudest at 0.55 s)."""
    t = timeline(1.2)
    n = len(t)
    p = t / 1.2
    shape = np.where(p < 0.46, (p / 0.46) ** 2, np.exp(-(p - 0.46) / 0.15))
    roar = roar_noise(rng, n, 1400, 0.8, 120, 9000, 0.3)
    fc = 9000 * (1 - 0.7 * p) + 800
    x = sweep(roar, fc, 0.8) * shape
    whistle = np.sin(TAU * np.cumsum(1900 - 600 * p) / SR) * shape * 0.15
    return x + whistle * np.abs(x).max()


def seeker_fizzle(rng):
    """A jammed seeker: a sputter and a sad falling beep."""
    t = timeline(0.7)
    n = len(t)
    beep = square(1760 * np.exp(-t / 0.3), n, 0.0, 0.4) * env_ar(t, 0.003, 0.25) * 0.4
    sput = zap(rng, 0.7, 70, 0.8) * env_ar(t, 0.003, 0.15) * 0.5
    return lp(beep, 5000) + sput


def shutter_klaxon(rng):
    """A blast door's alarm: two quick tones through a horn."""
    t = timeline(0.75)
    n = len(t)
    f = np.where(t < 0.18, 660.0, np.where(t < 0.36, 880.0, np.where(t < 0.54, 660.0, 880.0)))
    x = square(f, n, 0.0, 0.5) + 0.5 * saw(f * 1.01, n)
    x = bp(x, 1300, 0.8) + 0.4 * bp(x, 2600, 1.5)
    return x * gate(t, 0.7, 0.005, 0.05)


def shutter_slide(rng):
    """The door coming down: a hydraulic rush (0.5 s)."""
    t = timeline(0.55)
    n = len(t)
    hiss = sweep(rng.standard_normal(n), 1800 - 900 * t / 0.55, 0.8) * gate(t, 0.45, 0.01, 0.08)
    rattle = bp(rng.standard_normal(n), 700, 2) * (0.5 + 0.5 * np.sin(TAU * 33 * t)) * gate(t, 0.45, 0.01, 0.08)
    return norm(hiss) + 0.5 * norm(rattle)


def shutter_slam(rng):
    """The blast door slamming shut: a heavy boom and a ring of steel."""
    t = timeline(1.0)
    n = len(t)
    x = 1.4 * thump(rng, t, 0.0, 110, 38, 0.22, 0.9)
    x += 0.8 * metal_hit(rng, t, 0.0, 180, 1.6, 0.4)
    x += 0.3 * metal_hit(rng, t, 0.06, 260, 0.8, 0.2)
    dust = lp(rng.standard_normal(n), 1200) * env_ar(t, 0.01, 0.2) * 0.2
    return x + dust


def drone_whir_loop(rng):
    """An eye drone hovering: rotors buzzing, with a servo's hum."""
    L = 1.0
    n = secs(L)
    t = np.arange(n) / SR
    blade = cyc(92, L)
    rotor = sum(a * np.sin(TAU * blade * k * t + rng.uniform(0, TAU)) for k, a in ((1, 1.0), (2, 0.6), (3, 0.5), (4, 0.3), (6, 0.2)))
    rotor *= 1 + 0.3 * np.sin(TAU * cyc(8, L) * t)
    air = loop_noise(rng, n, lambda f: bp_mag(f, 1600, 0.7)) * (1 + 0.6 * np.sin(TAU * blade * t))
    servo = np.sin(TAU * cyc(640, L) * t) * 0.08
    return 0.5 * rotor / np.abs(rotor).max() + 0.25 * air + servo


def drone_charge(rng):
    """An eye drone charging its dash (0.7 s): a rising whine and its eye clicking."""
    t = timeline(0.7)
    n = len(t)
    f = 400 * 6 ** (t / 0.7)
    x = sine(f, n) + 0.3 * square(f * 0.5, n, 0.0, 0.3)
    x *= 0.3 + 0.7 * t / 0.7
    clicks = modes(t, [2800], [1.0], [0.004], 0.0) + modes(t, [3100], [1.0], [0.004], 0.3) + modes(t, [3400], [1.0], [0.004], 0.55)
    return lp(x, 6000) * np.clip((0.7 - t) / 0.01, 0, 1) + 0.6 * clicks


def drone_dash(rng):
    """An eye drone dashing along its lane: a zooming rush."""
    t = timeline(0.7)
    n = len(t)
    w = whoosh(rng, 0.7, 3500, 700, 1.4, 1.2, 0.3)
    whine = sine(1200 * np.exp(-t / 0.4), n) * bump(t, 0.0, 0.6) * 0.3
    return w + whine


def gun_charge(rng):
    """A gun drone powering a shot (0.4 s)."""
    t = timeline(0.42)
    n = len(t)
    f = 600 * 4 ** (t / 0.4)
    x = square(f, n, 0.0, 0.3) * (0.3 + 0.7 * t / 0.4)
    return lp(x, 5000) * 0.6 * np.clip((0.42 - t) / 0.01, 0, 1)


def gun_bolt(rng):
    """A slow plasma bolt fired across the lanes: a fat "pew"."""
    t = timeline(0.45)
    n = len(t)
    f = 1400 * np.exp(-t / 0.08) + 180
    x = square(f, n, 0.0, 0.4) + 0.5 * saw(f * 0.5, n)
    x = lp(x, 4000) * env_ar(t, 0.002, 0.12)
    sizzle = bp(rng.standard_normal(n), 3500, 1.0) * env_ar(t, 0.002, 0.2) * 0.3
    return x + sizzle


def walker_stomp(rng):
    """A Halberd walker's foot coming down: a servo's whirr and a heavy clank."""
    t = timeline(0.5)
    n = len(t)
    servo = sine(500 + 400 * np.clip(t / 0.08, 0, 1), n) * gate(t, 0.08, 0.005, 0.02) * 0.25
    servo = servo + 0.15 * square(250, n, 0, 0.3) * gate(t, 0.08, 0.005, 0.02)
    foot = thump(rng, t, 0.09, 100, 45, 0.12, 0.6) + 0.35 * metal_hit(rng, t, 0.09, 350, 0.8, 0.2)
    return servo + foot


def orb_roll_loop(rng):
    """A QuadOrb rolling at you: a low rumble with its seams thumping round."""
    L = 1.0
    n = secs(L)
    t = np.arange(n) / SR
    rumble = loop_noise(rng, n, lambda f: hp_mag(f, 40) * lp_mag(f, 300, 2))
    seams = np.zeros(n)
    s = timeline(0.1)
    for i in range(4):
        place(seams, thump(rng, s, 0.0, 120, 60, 0.03, 0.2), i * 0.25, wrap=True)
    hum = np.sin(TAU * cyc(180, L) * t) * 0.1
    return rumble + 0.8 * seams + hum


def robot_smash(rng):
    """A robot smashed: a crunch of metal, sparks and its power whining away."""
    t = timeline(1.1)
    n = len(t)
    crunch = metal_hit(rng, t, 0.0, 380, 1.0, 0.25) + metal_hit(rng, t, 0.03, 610, 0.8, 0.2)
    crunch += 0.8 * thump(rng, t, 0.0, 150, 55, 0.1, 0.8)
    grind = bp(rng.standard_normal(n), 1500, 0.8) * env_ar(t, 0.002, 0.08)
    sparks = zap(rng, 1.1, 140, 1.4) * env_ar(t, 0.01, 0.3) * 0.4
    power = saw(700 * np.exp(-t / 0.35) + 50, n) * env_ar(t, 0.05, 0.35) * 0.25
    return crunch + 0.6 * norm(grind) + sparks + lp(power, 2500)


def staff_thud(rng):
    """Someone knocked flat: a soft body landing."""
    t = timeline(0.4)
    n = len(t)
    body = thump(rng, t, 0.0, 95, 50, 0.08, 0.4)
    cloth = bp(rng.standard_normal(n), 1200, 0.8) * env_ar(t, 0.01, 0.04) * 0.3
    return body + cloth


def make_grunt(f0a, f0b, length, vowel, end_f):
    def build(rng):
        return grunt(rng, f0a, f0b, length, vowel, 0.35, end_f)
    return build


# ---------------------------------------------------------------------------
# Rewards: near misses, Burn, credits, crates and vehicles

def near_whoosh(rng):
    """A near miss: a fast, bright rush past (pitched up with the Burn in the game)."""
    w = whoosh(rng, 0.32, 1200, 4500, 1.8, 1.6, 0.4)
    t = timeline(0.32)
    zing = sine(2400 * 2 ** (t * 3), len(t)) * bump(t, 0.05, 0.25, 2) * 0.12
    return w + zing


def near_razor(rng):
    """Razor-close: a hot metallic zing on top of the whoosh."""
    t = timeline(0.4)
    ring = modes(t, [3150, 4721, 6290], [1.0, 0.6, 0.35], [0.12, 0.08, 0.05], 0.02)
    sizzle = hp(rng.standard_normal(len(t)), 5000) * env_ar(t, 0.003, 0.05) * 0.4
    return ring + sizzle


def near_thread(rng):
    """Threading a gap while changing lanes: a double whoosh and a glint."""
    t = timeline(0.6)
    out = np.zeros(len(t))
    place(out, whoosh(rng, 0.25, 900, 3500, 1.8, 1.5, 0.4), 0.0)
    place(out, 0.9 * whoosh(rng, 0.28, 1400, 5500, 1.8, 1.5, 0.4), 0.11)
    glint = fm_bell(mtof(93), 0.5, 3.0, 1.2, 0.2, 0.05) * 0.35
    place(out, glint, 0.18)
    return out


def burn_up(rng):
    """The Burn going up a level: a quick rising arpeggio and a swell (A minor; the game
    pitches it up for each level)."""
    L = 0.9
    t = timeline(L)
    out = np.zeros((2, len(t)))
    for i, m in enumerate((69, 72, 76, 81)):
        p = pluck(rng, mtof(m), 0.06, 1.0, 0.15)
        place(out, stereo(p, -0.4 + 0.27 * i), i * 0.045)
    place(out, 0.6 * stab(rng, [69, 76, 81, 84], 0.2), 0.18)
    rise = whoosh(rng, 0.35, 800, 6000, 1.5, 1.2, 0.9) * 0.3
    place(out, rise, 0.0)
    return out


def burn_max(rng):
    """Burn x5: a big chord, a rising rush and sparkle."""
    L = 1.6
    t = timeline(L)
    out = np.zeros((2, len(t)))
    place(out, whoosh(rng, 0.45, 500, 7000, 1.4, 1.3, 0.95) * 0.4, 0.0)
    place(out, 1.0 * brass(rng, [57, 64, 69, 72, 76, 81], 0.5, 1.2), 0.42)
    place(out, 0.5 * kick(rng, 120, 45, 0.3), 0.42)
    place(out, 0.4 * crash(rng, 1.1, 0.4), 0.42)
    sp = sparkle(rng, 0.8, [81, 84, 88, 93, 96, 100], 0.04, 0.15, 0.3)
    place(out, stereo(sp, 0.3), 0.45)
    return out


def burn_lost(rng):
    """The Burn gone: a sagging power-down."""
    t = timeline(0.6)
    n = len(t)
    f = 520 * np.exp(-t / 0.2) + 70
    x = saw(f, n) + 0.6 * square(f * 0.5, n, 0.0, 0.4)
    x = sweep(x, 2500 * np.exp(-t / 0.15) + 200, 2.0)
    return x * env_ar(t, 0.003, 0.22)


def credit(rng):
    """A credit chip: a bright "tink" tuned to A5, so the game can step it up a scale."""
    t = timeline(0.2)
    x = fm_bell(880.0, 0.2, 2.0, 1.6, 0.07, 0.02) + 0.5 * fm_bell(1760.0, 0.2, 3.0, 0.8, 0.04, 0.01)
    click = hp(rng.standard_normal(len(t)) * env_ar(t, 0.0002, 0.002), 5000) * 0.2
    return x + click


def credit_big(rng):
    """A big chip: a bright major chord shimmering up."""
    out = np.zeros(secs(0.9))
    for i, m in enumerate((81, 85, 88, 93)):
        place(out, fm_bell(mtof(m), 0.8, 2.0, 1.5, 0.25, 0.04) * (0.7 + 0.1 * i), i * 0.05)
    t = timeline(0.9)
    out += 0.25 * hp(rng.standard_normal(len(t)), 7000) * env_ar(t, 0.002, 0.15)
    return out


def crate_open(rng):
    """A vehicle crate cracking open: latches, a hiss, and the lid flung back."""
    t = timeline(0.8)
    n = len(t)
    latches = modes(t, [2400, 3700], [1.0, 0.5], [0.01, 0.006], 0.0) + modes(t, [2600, 3900], [1.0, 0.5], [0.01, 0.006], 0.05)
    hiss = bp(rng.standard_normal(n), 3000, 0.8) * env_ar(t, 0.01, 0.12, 0.07) * 0.6
    lid = metal_hit(rng, t, 0.22, 500, 0.8, 0.2) * 0.5 + thump(rng, t, 0.22, 140, 70, 0.05, 0.3) * 0.5
    return 0.5 * latches + hiss + lid


def vehicle_on(rng):
    """A hijacked robot booting up under you: rising chirps, servos and a clunk."""
    t = timeline(1.0)
    n = len(t)
    out = np.zeros(n)
    for i, m in enumerate((57, 64, 69, 76)):
        s = timeline(0.12)
        place(out, square(mtof(m) * 2, len(s), 0.0, 0.3) * env_ar(s, 0.002, 0.05) * 0.25, 0.05 + i * 0.07)
    servo = sine(300 + 600 * np.clip((t - 0.3) / 0.3, 0, 1), n) * gate(t - 0.3, 0.3, 0.01, 0.05) * (t > 0.3) * 0.3
    clunk = thump(rng, t, 0.62, 150, 60, 0.08, 0.5) + 0.4 * metal_hit(rng, t, 0.62, 400, 0.8, 0.2)
    return lp(out, 6000) + servo + clunk


def vehicle_hum_loop(rng):
    """A robot under you: servos humming, a motor's whine and gears."""
    L = 1.0
    n = secs(L)
    t = np.arange(n) / SR
    motor = sum(a * np.sin(TAU * cyc(f, L) * t + rng.uniform(0, TAU)) for f, a in ((110, 1.0), (220, 0.6), (330, 0.3), (880, 0.15)))
    motor *= 1 + 0.15 * np.sin(TAU * cyc(6, L) * t)
    gears = loop_noise(rng, n, lambda f: bp_mag(f, 2200, 2.0)) * 0.15
    return 0.4 * motor / np.abs(motor).max() + gears


def raptor_step(rng):
    """The Raptor's big foot: a hydraulic hiss and a clank."""
    t = timeline(0.4)
    n = len(t)
    foot = thump(rng, t, 0.0, 130, 50, 0.08, 0.6) + 0.4 * metal_hit(rng, t, 0.0, 330, 0.7, 0.15)
    hiss = hp(rng.standard_normal(n), 3000) * env_ar(t, 0.01, 0.04, 0.03) * 0.15
    return foot + hiss


def raptor_jump(rng):
    """The Raptor jumping: a hydraulic launch."""
    t = timeline(0.5)
    n = len(t)
    push = thump(rng, t, 0.0, 160, 70, 0.06, 0.5)
    hiss = sweep(rng.standard_normal(n), 1500 + 3000 * np.clip(t / 0.15, 0, 1), 1.0, "bp") * env_ar(t, 0.005, 0.12)
    spring = sine(250 * 2 ** (t * 4), n) * env_ar(t, 0.005, 0.1) * 0.25
    return norm(push) * 0.7 + 0.6 * norm(hiss) + spring


def shell_flip(rng):
    """The Shell flipping to the ceiling or floor: a whirl and a clamp."""
    t = timeline(0.55)
    n = len(t)
    whirl = whoosh(rng, 0.35, 600, 2500, 2.0, 1.2, 0.5) * 0.6
    clamp = thump(rng, t, 0.33, 150, 70, 0.05, 0.5) * 0.6 + metal_hit(rng, t, 0.33, 550, 0.6, 0.15) * 0.4
    return place(np.zeros(n), whirl, 0.0) + clamp


def eye_hop(rng):
    """The Eye hopping up: a thruster's blip."""
    t = timeline(0.3)
    n = len(t)
    x = sweep(rng.standard_normal(n), 800 + 2500 * np.clip(t / 0.06, 0, 1), 1.2, "bp") * env_ar(t, 0.003, 0.07)
    blip = sine(700 * 2 ** (t * 6), n) * env_ar(t, 0.002, 0.05) * 0.3
    return norm(x) + blip


def gunner_shot(rng):
    """The Gunner firing ahead: a short, punchy blaster."""
    t = timeline(0.25)
    n = len(t)
    f = 2200 * np.exp(-t / 0.04) + 300
    x = square(f, n, 0.0, 0.35) * env_ar(t, 0.001, 0.06)
    pop = thump(rng, t, 0.0, 180, 80, 0.03, 0.3) * 0.5
    return lp(x, 6000) + pop


def vehicle_lost(rng):
    """A vehicle wrecked by a hit: a bang, scattering parts and a dying motor."""
    t = timeline(1.3)
    n = len(t)
    bang = thump(rng, t, 0.0, 180, 40, 0.25, 1.0) + 0.5 * lp(rng.standard_normal(n), 3000) * env_ar(t, 0.001, 0.12)
    parts = sum(0.25 * metal_hit(rng, t, at, rng.uniform(500, 1400), 0.5, 0.12) for at in (0.12, 0.2, 0.31, 0.45, 0.6))
    motor = saw(400 * np.exp(-t / 0.4) + 40, n) * env_ar(t, 0.02, 0.4) * 0.2
    return bang + parts + lp(motor, 2000)


# ---------------------------------------------------------------------------
# Stingers and the interface

def finish_stinger(rng):
    """A course finished: a bright fanfare up to A major."""
    out = np.zeros((2, secs(2.6)))
    for at, chord, ln in ((0.0, [53, 60, 65, 69], 0.2), (0.24, [55, 62, 67, 71], 0.2), (0.48, [57, 64, 69, 73, 76], 1.3)):
        place(out, brass(rng, chord, ln, 1.2), at)
        place(out, 0.7 * kick(rng, 140, 45, 0.25), at)
    place(out, 0.5 * crash(rng, 2.0, 0.7), 0.48)
    sp = sparkle(rng, 1.0, [81, 85, 88, 93, 97, 100], 0.05, 0.2, 0.25)
    place(out, stereo(sp, -0.2), 0.5)
    return out


def round_over(rng):
    """A party round won: a short, punchy brass hit and cheer of sparkle."""
    out = np.zeros((2, secs(2.0)))
    place(out, brass(rng, [50, 57, 62, 66, 69], 0.12, 1.2), 0.0)
    place(out, brass(rng, [50, 57, 62, 66, 69], 0.9, 1.3), 0.18)
    place(out, 0.7 * kick(rng, 140, 45, 0.25), 0.0)
    place(out, 0.7 * kick(rng, 140, 45, 0.25), 0.18)
    place(out, 0.5 * crash(rng, 1.6, 0.6), 0.18)
    place(out, stereo(sparkle(rng, 0.8, [74, 78, 81, 86, 90, 93], 0.05, 0.18, 0.25), 0.2), 0.2)
    return out


def run_over(rng):
    """A run over: two soft falling chords, not a punishment."""
    out = np.zeros((2, secs(2.4)))
    place(out, pad_chord(rng, [57, 64, 69, 72], 0.4, 2600) * 1.4, 0.0)
    place(out, pad_chord(rng, [53, 60, 65, 69], 1.0, 2000) * 1.4, 0.38)
    for i, m in enumerate((76, 72, 69)):
        place(out, stereo(fm_bell(mtof(m), 1.2, 2.0, 1.0, 0.4, 0.1) * 0.35, 0.2 - 0.2 * i), 0.05 + i * 0.16)
    return reverb(out, rng, 1.8, 0.3, 4000)


def ui_buy(rng):
    """Buying something: a register's ching and chips falling into it."""
    t = timeline(0.7)
    out = np.zeros(len(t))
    place(out, fm_bell(mtof(88), 0.6, 3.5, 2.5, 0.25, 0.05), 0.0)
    place(out, 0.8 * fm_bell(mtof(93), 0.6, 3.5, 2.0, 0.25, 0.05), 0.06)
    for i in range(5):
        place(out, 0.3 * fm_bell(rng.uniform(2500, 4000), 0.1, 2.0, 1.0, 0.03, 0.01), 0.12 + 0.04 * i + rng.uniform(0, 0.02))
    return out


def ui_unlock(rng):
    """Something new unlocked: a rising bell figure over a soft chord."""
    out = np.zeros((2, secs(1.6)))
    place(out, pad_chord(rng, [60, 64, 67, 71], 0.6, 3000) * 1.2, 0.0)
    for i, m in enumerate((72, 76, 79, 84, 88)):
        place(out, stereo(fm_bell(mtof(m), 1.0, 2.0, 1.4, 0.35, 0.06) * 0.5, -0.4 + 0.2 * i), i * 0.07)
    return reverb(out, rng, 1.5, 0.25, 5000)


def ui_rank(rng):
    """A new rank: a short brass call and sparkle."""
    out = np.zeros((2, secs(1.8)))
    place(out, brass(rng, [60, 67, 72, 76], 0.14, 1.1), 0.0)
    place(out, brass(rng, [62, 69, 74, 78], 0.14, 1.1), 0.16)
    place(out, brass(rng, [64, 71, 76, 79, 83], 0.8, 1.2), 0.32)
    place(out, stereo(sparkle(rng, 0.6, [84, 88, 91, 96], 0.05, 0.2, 0.25), 0.3), 0.34)
    return reverb(out, rng, 1.4, 0.2, 5000)


def ui_start(rng):
    """Starting a run: the burner lighting and a rush away."""
    t = timeline(0.9)
    n = len(t)
    light = burner_ignite(rng)
    rush = whoosh(rng, 0.8, 500, 3500, 1.3, 1.4, 0.35)
    out = np.zeros(n)
    place(out, light, 0.0)
    place(out, 0.7 * rush, 0.05)
    return out


def ui_best(rng):
    """A new best: a sparkling run of chimes."""
    out = sparkle(rng, 0.7, [81, 85, 88, 93, 97, 100, 105], 0.045, 0.25, 1.0)
    return out


# ---------------------------------------------------------------------------
# Ambiences: quiet room tone per zone (8 s loops)

AMB_LEN = 8.0


def amb_lab(rng):
    """The Test Lab: air handling, a faint mains hum and now and then a computer's chirp."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    air = loop_noise(rng, n, lambda f: hp_mag(f, 60) * lp_mag(f, 700, 2))
    hum = sum(a * np.sin(TAU * cyc(f, AMB_LEN) * t) for f, a in ((60, 1.0), (120, 0.5), (180, 0.2))) * 0.08
    beeps = np.zeros(n)
    for _ in range(4):
        s = timeline(0.09)
        b = np.sin(TAU * rng.choice([1320, 1568, 1760, 2093]) * s) * gate(s, 0.07, 0.003, 0.015) * 0.12
        place(beeps, b, rng.uniform(0, AMB_LEN), wrap=True)
    return air + hum + beeps


def amb_servers(rng):
    """The Server Hall: racks of fans, a blade tone, and disks ticking."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    fans = loop_noise(rng, n, lambda f: bp_mag(f, 1100, 0.6) + 0.6 * lp_mag(f, 300))
    blade = sum(a * np.sin(TAU * cyc(f, AMB_LEN) * t) for f, a in ((233, 1.0), (466, 0.4), (241, 0.6))) * 0.1
    ticks = np.zeros(n)
    s = timeline(0.01)
    for _ in range(int(AMB_LEN * 14)):
        place(ticks, rng.standard_normal(len(s)) * np.exp(-s / 0.0015) * rng.uniform(0.05, 0.25), rng.uniform(0, AMB_LEN), wrap=True)
    return fans + blade + hp(ticks, 2000, loop=True)


def amb_bay(rng):
    """The Robot Bay: machinery's hum, a hydraulic hiss and distant clanks."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    hum = loop_noise(rng, n, lambda f: hp_mag(f, 40) * lp_mag(f, 250, 2))
    tone = sum(a * np.sin(TAU * cyc(f, AMB_LEN) * t) for f, a in ((98, 1.0), (147, 0.4))) * 0.12
    out = hum + tone
    for at in (1.3, 5.2):
        s = timeline(0.8)
        place(out, 0.25 * hp(rng.standard_normal(len(s)), 2500) * bump(s, 0, 0.8), at, wrap=True)
    for at in (3.1, 6.9):
        s = timeline(1.0)
        place(out, 0.3 * lp(metal_hit(rng, s, 0.0, rng.uniform(200, 400), 1.0, 0.4), 1500), at, wrap=True)
    return out


def amb_atrium(rng):
    """The Atrium: a big open space's air, softly swelling, the city's hum through glass."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    air = loop_noise(rng, n, lambda f: hp_mag(f, 80) * lp_mag(f, 1200, 2))
    swell = 1 + 0.3 * np.sin(TAU * t / AMB_LEN) + 0.15 * np.sin(TAU * 3 * t / AMB_LEN + 1)
    city = loop_noise(rng, n, lambda f: hp_mag(f, 30) * lp_mag(f, 160, 2)) * 0.6
    return air * swell + city


def amb_downtown(rng):
    """Downtown: wind over the roofs and traffic far below."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    wind = loop_noise(rng, n, lambda f: bp_mag(f, 500, 0.9) + 0.5 * bp_mag(f, 1300, 3.0))
    gust = 1 + 0.5 * np.sin(TAU * 2 * t / AMB_LEN) + 0.3 * np.sin(TAU * 5 * t / AMB_LEN + 2)
    traffic = loop_noise(rng, n, lambda f: hp_mag(f, 30) * lp_mag(f, 220, 2)) * 0.7
    return wind * np.clip(gust, 0.2, None) + traffic


def amb_halberd(rng):
    """Halberd's floor: a tense low drone and a far-off alarm."""
    n = secs(AMB_LEN)
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(f, AMB_LEN) * t + rng.uniform(0, TAU)) for f, a in ((55, 1.0), (82.5, 0.5), (110, 0.3), (58.3, 0.4)))
    drone *= 1 + 0.25 * np.sin(TAU * 4 * t / AMB_LEN)
    alarm_f = np.where((t % 2.0) < 1.0, 587.0, 523.0)
    alarm = bp(square(alarm_f, n, 0.0, 0.5), 1200, 1.0, loop=True) * 0.05
    alarm *= 0.5 + 0.5 * np.sin(TAU * t / AMB_LEN) ** 2
    air = loop_noise(rng, n, lambda f: hp_mag(f, 60) * lp_mag(f, 500, 2)) * 0.5
    return 0.4 * drone + alarm + air


# ---------------------------------------------------------------------------
# Music

class Song:
    """A loop of whole bars at a tempo, with helpers for when things happen."""

    def __init__(self, bpm, bars):
        self.bpm = bpm
        self.bars = bars
        self.step = 60.0 / bpm / 4
        self.length = self.step * 16 * bars
        self.n = secs(self.length)

    def at(self, bar, step=0.0):
        return (bar * 16 + step) * self.step

    def buf(self):
        return np.zeros((2, self.n))


def drum_stem(rng, s, fills=(7, 15), clap_on=(4, 12), ghost=0.3, kick_f=(170, 52)):
    """Four on the floor, claps on two and four, hats on the off-beats with ghost sixteenths,
    and a snare fill at the end of each half. The kick stays dry; the rest gets a little room."""
    kicks = s.buf()
    perc = s.buf()
    k = kick(rng, kick_f[0], kick_f[1])
    c = clap(rng)
    for bar in range(s.bars):
        fill = bar in fills
        for step in range(16):
            at = s.at(bar, step)
            if step % 4 == 0 and not (fill and step == 12):
                place(kicks, k, at, wrap=True)
            if step in clap_on and not (fill and step == 12):
                place(perc, stereo(0.75 * c, 0.05), at, wrap=True)
            if step % 4 == 2:
                place(perc, stereo(0.55 * hat(rng, 0.08, 0.035), 0.3), at, wrap=True)
            elif step % 2 == 1:
                place(perc, stereo(ghost * 0.55 * hat(rng, 0.05, 0.015), -0.25), at, wrap=True)
        if fill:
            for i, step in enumerate((12, 13, 14, 15)):
                place(perc, stereo((0.45 + 0.12 * i) * snare(rng, 0.25, 200 + 10 * i), -0.3 + 0.2 * i), s.at(bar, step), wrap=True)
            place(kicks, 0.9 * k, s.at(bar, 12), wrap=True)
    perc = reverb(perc, rng, 0.9, 0.12, 6000, loop=True)
    return drive((kicks + perc) * 1.3, 1.3)


def bass_stem(rng, s, roots, style="roll"):
    """The bass: rolling sixteenths between the kicks (roll), off-beat octaves (house) or a
    growling reese on eighths (reese). roots has one note per two bars."""
    out = s.buf()
    for bar in range(s.bars):
        root = roots[bar // 2]
        f = mtof(root)
        for step in range(16):
            at = s.at(bar, step)
            if style == "roll":
                if step % 4 == 0:
                    continue
                octave = step % 8 == 7
                vel = (0.7, 1.0, 0.8)[step % 4 - 1]
                note = bass_note(rng, f * (2 if octave else 1), s.step * 0.8, vel)
                place(out, note, at, wrap=True)
            elif style == "reese":
                if step % 2 == 1 or step % 4 == 0 and step % 8 != 0:
                    continue
                note = reese_note(rng, f * (2 if step in (6, 14) else 1), s.step * 1.7, 1.0 if step % 8 == 0 else 0.7)
                place(out, note, at, wrap=True)
    duck = duck_curve(s.n, [s.at(b, st) for b in range(s.bars) for st in (0, 4, 8, 12)], 0.5, 0.12)
    return out * duck


def pad_stem(rng, s, chords, bright=1800.0):
    out = s.buf()
    for i, chord in enumerate(chords):
        place(out, pad_chord(rng, chord, s.at(2) - 0.05, bright), s.at(i * 2), wrap=True)
    duck = duck_curve(s.n, [s.at(b, st) for b in range(s.bars) for st in (0, 4, 8, 12)], 0.55, 0.22)
    return reverb(out * duck, rng, 2.2, 0.35, 3500, loop=True)


def arp_stem(rng, s, chords, pattern=(0, 1, 2, 3, 2, 1, 2, 1), every=1, octave=12):
    """Plucked sixteenths up and down the chord, echoing on a dotted eighth."""
    out = s.buf()
    for bar in range(s.bars):
        chord = chords[bar // 2]
        tones = sorted(chord)[:3]
        tones = tones + [tones[0] + 12]
        for step in range(0, 16, every):
            m = tones[pattern[step % len(pattern)]] + octave
            vel = 1.0 if step % 4 == 0 else 0.75
            pan = 0.35 * np.sin(step * 0.8 + bar)
            place(out, stereo(pluck(rng, mtof(m), s.step * 0.7, vel, 0.16), pan), s.at(bar, step), wrap=True)
    out = echo(out, s.step * 3, 0.45, 0.35, 5, True, True, 3500)
    duck = duck_curve(s.n, [s.at(b, st) for b in range(s.bars) for st in (0, 4, 8, 12)], 0.35, 0.18)
    return reverb(out * duck, rng, 1.6, 0.25, 5000, loop=True)


def lead_stem(rng, s, melody):
    """The tune: a supersaw lead with an eighth-note echo."""
    out = s.buf()
    for bar0, notes in melody:
        for step, ln, m in notes:
            place(out, lead_note(rng, mtof(m), ln * s.step * 0.92, 1.0), s.at(bar0, step), wrap=True)
    out = echo(out, s.step * 2, 0.35, 0.22, 4, True, True, 3000)
    return reverb(out, rng, 1.8, 0.3, 5000, loop=True)


def hype_stem(rng, s, chords, stab_steps=(2, 6, 10, 14), crash_bars=(0, 8)):
    """Everything on top: off-beat chord stabs, open hats, a shaker, crashes and a riser with
    a snare roll into the top of the loop."""
    out = s.buf()
    oh = hat(rng, 0.3, 0.12, 7000)
    for bar in range(s.bars):
        chord = chords[bar // 2]
        for step in range(16):
            at = s.at(bar, step)
            if step in stab_steps:
                place(out, 0.55 * stab(rng, [m + 12 for m in chord], s.step * 1.2), at, wrap=True)
            if step % 4 == 2:
                place(out, stereo(0.28 * oh, -0.2), at, wrap=True)
            place(out, stereo(0.1 * shaker(rng) * (1.0 if step % 2 == 0 else 0.6), 0.45), at, wrap=True)
    for b in crash_bars:
        place(out, 0.45 * crash(rng), s.at(b), wrap=True)
    # A riser over the last two bars and a snare roll in the last.
    rl = s.at(2)
    riser = whoosh(rng, rl, 400, 9000, 1.2, 2.5, 0.995)
    place(out, stereo(0.3 * riser), s.length - rl, wrap=True)
    roll_at = s.at(s.bars - 1)
    k = 0
    while True:
        p = k / 24
        at = roll_at + s.at(1) * (1 - (1 - p) ** 1.6)
        if at >= s.length - 0.01:
            break
        place(out, (0.08 + 0.3 * p) * snare(rng, 0.2, 210, 0.08), at, wrap=True)
        k += 1
    duck = duck_curve(s.n, [s.at(b, st) for b in range(s.bars) for st in (0, 4, 8, 12)], 0.35, 0.15)
    return reverb(out * duck, rng, 1.4, 0.18, 6000, loop=True)


# A minor: Am F C G | Am F Dm E, two bars each.
RUN_CHORDS = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62],
              [57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
RUN_ROOTS = [45, 41, 48, 43, 45, 41, 50, 40]
RUN_PAD = [[57, 60, 64, 69], [53, 60, 65, 69], [52, 55, 60, 67], [55, 59, 62, 67],
           [57, 60, 64, 72], [53, 57, 60, 65], [53, 57, 62, 69], [52, 56, 59, 64]]
# (bar, [(step, sixteenths, note)]): a tune in three-three-two.
RUN_MELODY = [
    (0, [(0, 3, 76), (3, 3, 76), (6, 2, 74), (8, 2, 76), (10, 4, 79), (14, 2, 76),
         (16, 3, 74), (19, 3, 72), (22, 2, 69), (24, 6, 72), (30, 2, 74)]),
    (2, [(0, 3, 77), (3, 3, 77), (6, 2, 76), (8, 2, 74), (10, 4, 72), (14, 2, 69),
         (16, 3, 72), (19, 3, 74), (22, 2, 76), (24, 8, 72)]),
    (4, [(0, 3, 79), (3, 3, 79), (6, 2, 76), (8, 2, 79), (10, 4, 81), (14, 2, 79),
         (16, 3, 79), (19, 3, 76), (22, 2, 72), (24, 6, 76), (30, 2, 74)]),
    (6, [(0, 3, 74), (3, 3, 74), (6, 2, 71), (8, 2, 74), (10, 6, 79),
         (16, 3, 77), (19, 3, 76), (22, 2, 74), (24, 4, 71), (28, 4, 74)]),
    (8, [(0, 3, 81), (3, 3, 81), (6, 2, 79), (8, 2, 81), (10, 4, 84), (14, 2, 81),
         (16, 3, 79), (19, 3, 76), (22, 2, 72), (24, 6, 76), (30, 2, 79)]),
    (10, [(0, 3, 81), (3, 3, 81), (6, 2, 79), (8, 2, 77), (10, 4, 76), (14, 2, 72),
          (16, 3, 77), (19, 3, 76), (22, 2, 72), (24, 8, 69)]),
    (12, [(0, 3, 77), (3, 3, 77), (6, 2, 76), (8, 2, 74), (10, 4, 77), (14, 2, 81),
          (16, 3, 79), (19, 3, 77), (22, 2, 76), (24, 8, 74)]),
    (14, [(0, 3, 76), (3, 3, 80), (6, 2, 83), (8, 2, 80), (10, 6, 76),
          (16, 3, 74), (19, 3, 76), (22, 2, 80), (24, 6, 83), (30, 2, 80)]),
]

# D minor: Dm Bb F C | Dm Bb Gm A, two bars each.
PARTY_CHORDS = [[50, 53, 57], [46, 50, 53], [53, 57, 60], [48, 52, 55],
                [50, 53, 57], [46, 50, 53], [55, 58, 62], [57, 61, 64]]
PARTY_ROOTS = [38, 46, 41, 48, 38, 46, 43, 45]
# A one-bar riff, answered, then climbing.
PARTY_MELODY = [
    (0, [(0, 2, 74), (2, 2, 77), (4, 1, 81), (6, 2, 79), (8, 2, 77), (10, 2, 76), (12, 4, 74),
         (16, 2, 74), (18, 2, 77), (20, 1, 81), (22, 2, 82), (24, 2, 81), (26, 2, 79), (28, 4, 77)]),
    (2, [(0, 2, 74), (2, 2, 77), (4, 1, 81), (6, 2, 79), (8, 2, 77), (10, 2, 76), (12, 4, 72),
         (16, 2, 72), (18, 2, 76), (20, 1, 79), (22, 2, 81), (24, 2, 79), (26, 2, 76), (28, 4, 72)]),
    (4, [(0, 2, 74), (2, 2, 77), (4, 1, 81), (6, 2, 79), (8, 2, 77), (10, 2, 76), (12, 4, 74),
         (16, 2, 77), (18, 2, 81), (20, 1, 84), (22, 2, 86), (24, 2, 84), (26, 2, 82), (28, 4, 81)]),
    (6, [(0, 2, 79), (2, 2, 82), (4, 1, 86), (6, 2, 84), (8, 2, 82), (10, 2, 81), (12, 4, 79),
         (16, 2, 81), (18, 2, 85), (20, 2, 88), (22, 2, 85), (24, 4, 81), (28, 4, 85)]),
]


def run_track(rng):
    s = Song(128, 16)
    return s, {
        "pad": 0.9 * pad_stem(rng, s, RUN_PAD),
        "drums": drum_stem(rng, s),
        "bass": bass_stem(rng, s, RUN_ROOTS, "roll"),
        "arp": arp_stem(rng, s, RUN_CHORDS),
        "lead": lead_stem(rng, s, RUN_MELODY),
        "hype": hype_stem(rng, s, RUN_CHORDS),
    }


def party_track(rng):
    s = Song(136, 16)
    drums = drum_stem(rng, s, fills=(3, 7, 11, 15), kick_f=(180, 50))
    bass = bass_stem(rng, s, PARTY_ROOTS, "reese")
    lead = lead_stem(rng, s, PARTY_MELODY + [(b + 8, notes) for b, notes in PARTY_MELODY])
    arp = arp_stem(rng, s, PARTY_CHORDS, (0, 2, 1, 3, 0, 2, 1, 2), 1, 12)
    return s, {
        "base": drums + 0.8 * bass,
        "lead": lead + 0.6 * arp,
        "hype": hype_stem(rng, s, PARTY_CHORDS, (2, 6, 10, 14), (0, 4, 8, 12)),
    }


def title_track(rng):
    """The title: the run's tune, laid back at 100 BPM, with a soft beat and bells."""
    s = Song(100, 16)
    pad = pad_stem(rng, s, RUN_PAD, 1500)
    arp = arp_stem(rng, s, RUN_CHORDS, (0, 1, 2, 3, 2, 1, 2, 1), 2, 12)
    out = s.buf()
    k = kick(rng, 120, 45, 0.3, 0.05, 0.2)
    h = hat(rng, 0.06, 0.02, 9000)
    for bar in range(s.bars):
        for step in range(16):
            at = s.at(bar, step)
            if step in (0, 10) and bar >= 2:
                place(out, 0.6 * k, at, wrap=True)
            if step in (4, 12) and bar >= 4:
                place(out, stereo(0.18 * clap(rng, 0.4, 1100), 0.1), at, wrap=True)
            if step % 2 == 0 and bar >= 2:
                place(out, stereo((0.12 if step % 4 == 2 else 0.06) * h, 0.3), at, wrap=True)
    bass = s.buf()
    for bar in range(s.bars):
        f = mtof(RUN_ROOTS[bar // 2])
        for step in (0, 6, 10):
            place(bass, 0.7 * bass_note(rng, f, s.step * (5 if step == 0 else 3), 0.4, 0.6), s.at(bar, step), wrap=True)
    bells = s.buf()
    for bar0, notes in RUN_MELODY[:4] + [(b + 8, n) for b, n in RUN_MELODY[:4]]:
        for step, ln, m in notes[::2]:
            pan = 0.3 * np.sin(step)
            place(bells, stereo(fm_bell(mtof(m), 1.2, 2.0, 1.2, 0.5, 0.08) * 0.5, pan), s.at(bar0, step), wrap=True)
    bells = echo(bells, s.step * 3, 0.45, 0.4, 5, True, True, 3000)
    bells = reverb(bells, rng, 2.5, 0.4, 4000, loop=True)
    beat = reverb(out, rng, 1.0, 0.12, 6000, loop=True)
    return s, {"title": 1.0 * pad + 0.8 * arp + 0.9 * beat + 0.55 * bass + 0.7 * bells}


# Each stem's loudness against the drums (dB of RMS), so stems keep a balance.
STEM_LEVELS = {
    "run": {"drums": 0.0, "bass": -1.5, "pad": -9.0, "arp": -8.0, "lead": -4.5, "hype": -6.0},
    "party": {"base": 0.0, "lead": -4.0, "hype": -5.5},
    "title": {"title": 0.0},
}
MUSIC_LUFS = {"run": -14.0, "party": -14.0, "title": -17.0}
TRACKS = {"run": run_track, "party": party_track, "title": title_track}


# ---------------------------------------------------------------------------
# The catalogue: name -> (builder, kind); kind is "sfx", "loop", "amb" or a track

def catalogue():
    sounds = {}
    for build in (burner_k4_kick, burner_ignite, burner_sputter, thruster_hiss, lane_swish, rocket_end,
                  land_thump, crash_hit, shield_pop, armour_clank, reboot, stun, out,
                  zapper_crackle, laser_charge, laser_fire, seeker_beep, seeker_lock, seeker_launch,
                  seeker_whoosh, seeker_fizzle, shutter_klaxon, shutter_slide, shutter_slam, drone_charge,
                  drone_dash, gun_charge, gun_bolt, walker_stomp, robot_smash, staff_thud,
                  near_whoosh, near_razor, near_thread, burn_up, burn_max, burn_lost, credit, credit_big,
                  crate_open, vehicle_on, raptor_step, raptor_jump, shell_flip, eye_hop, gunner_shot,
                  vehicle_lost, finish_stinger, round_over, run_over,
                  ui_buy, ui_unlock, ui_rank, ui_start, ui_best):
        sounds[build.__name__] = (build, "sfx")
    for i in range(3):
        sounds[f"zapper_crackle_{i + 1}"] = (zapper_crackle, "sfx")
    del sounds["zapper_crackle"]
    for i in range(4):
        sounds[f"footstep_{i + 1}"] = (footstep, "sfx")
    grunts = {
        "staff_oof_m1": (150, 95, 0.26, (430, 900, 2300), 0.0),
        "staff_oof_m2": (135, 90, 0.22, (640, 1190, 2390), 0.0),
        "staff_oof_f1": (270, 190, 0.24, (450, 950, 2600), 0.0),
        "staff_oof_f2": (300, 210, 0.2, (700, 1300, 2700), 0.0),
    }
    for name, args in grunts.items():
        sounds[name] = (make_grunt(*args), "sfx")
    for build in (burner_k1_loop, burner_k2_loop, burner_k3_loop, burner_k4_loop, burner_k5_loop, burner_k6_loop,
                  rocket_loop, crash_slide_loop, zapper_hum_loop, drone_whir_loop, orb_roll_loop, vehicle_hum_loop):
        sounds[build.__name__] = (build, "loop")
    for build in (amb_lab, amb_servers, amb_bay, amb_atrium, amb_downtown, amb_halberd):
        sounds[build.__name__] = (build, "amb")
    for track in TRACKS:
        sounds[track] = (TRACKS[track], "track")
    return dict(sorted(sounds.items()))


def finish(x, loop):
    """Removes rumble and DC, fades one-shots in and out, and normalises the peak to -3 dBFS."""
    x = hp(x, 25, loop=loop)
    if not loop:
        n_in, n_out = secs(0.001), min(secs(0.02), x.shape[-1] // 8)
        x[..., :n_in] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n_in))
        x[..., -n_out:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n_out))
    return x * (PEAK / np.abs(x).max())


def write_wav(path, x):
    frames = x.T if x.ndim == 2 else x
    pcm = np.clip(np.round(frames * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[0] if x.ndim == 2 else 1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def lufs(ffmpeg, path):
    """Integrated loudness of a file, from ffmpeg's ebur128 filter."""
    out = subprocess.run([ffmpeg, "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    m = re.findall(r"I:\s+(-?[\d.]+) LUFS", out)
    return float(m[-1]) if m else -70.0


def encode(ffmpeg, wav, ogg, quality):
    subprocess.run([ffmpeg, "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality),
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", ogg], check=True)


def build_track(name, build, ffmpeg, wav_dir, music_dir):
    """Renders a track's stems, balances them, sets the mix's loudness and writes each stem."""
    rng = rng_for(name)
    song, stems = build(rng)
    levels = STEM_LEVELS[name]
    ref = rms(stems[next(iter(levels))])
    for k in stems:
        stems[k] = hp(stems[k], 25, loop=True)
        stems[k] *= ref * 10 ** (levels[k] / 20) / rms(stems[k])
    mix = sum(stems.values())
    gain = 0.5 / np.abs(mix).max()
    mix_wav = os.path.join(wav_dir, name + "_mix.wav")
    write_wav(mix_wav, mix * gain)
    level = lufs(ffmpeg, mix_wav)
    gain *= 10 ** ((MUSIC_LUFS[name] - level) / 20)
    peak = np.abs(mix).max() * gain
    if peak > 10 ** (-1 / 20):
        gain *= 10 ** (-1 / 20) / peak
    write_wav(mix_wav, mix * gain)
    for k, x in stems.items():
        stem_name = name if len(stems) == 1 else f"{name}_{k}"
        wav = os.path.join(wav_dir, stem_name + ".wav")
        write_wav(wav, x * gain)
        encode(ffmpeg, wav, os.path.join(music_dir, stem_name + ".ogg"), 4)
    print(f"{name:24s} {song.length:5.2f} s  {song.bpm} BPM, {len(stems)} stem(s), mix {lufs(ffmpeg, mix_wav):.1f} LUFS",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default="assets/audio", help="the audio folder (sfx/ and music/ go in it)")
    parser.add_argument("--wav", help="also keep the WAVs in this folder")
    parser.add_argument("--only", help="comma-separated names to build")
    parser.add_argument("--list", action="store_true", help="list every sound and stop")
    args = parser.parse_args()
    ffmpeg = shutil.which("ffmpeg") or "/usr/bin/ffmpeg"
    sounds = catalogue()
    if args.list:
        for name, (_, kind) in sounds.items():
            print(f"{name:24s} {kind}")
        return
    names = list(sounds)
    if args.only:
        names = args.only.split(",")
        for name in names:
            if name not in sounds:
                sys.exit(f"unknown sound: {name}")
    sfx_dir = os.path.join(args.out, "sfx")
    music_dir = os.path.join(args.out, "music")
    os.makedirs(sfx_dir, exist_ok=True)
    os.makedirs(music_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_dir = args.wav or tmp
        os.makedirs(wav_dir, exist_ok=True)
        for name in names:
            build, kind = sounds[name]
            if kind == "track":
                build_track(name, build, ffmpeg, wav_dir, music_dir)
                continue
            loop = kind in ("loop", "amb")
            x = finish(np.asarray(build(rng_for(name)), dtype=float), loop)
            wav = os.path.join(wav_dir, name + ".wav")
            write_wav(wav, x)
            encode(ffmpeg, wav, os.path.join(sfx_dir, name + ".ogg"), 6 if loop else 4)
            note = "  loop" if loop else ""
            if x.ndim == 2:
                note += "  stereo"
            print(f"{name:24s} {x.shape[-1] / SR:5.2f} s{note}", flush=True)


if __name__ == "__main__":
    main()
