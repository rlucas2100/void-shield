"""Void Shield Lite sound packs. Everything sits in G major so the packs feel related.
chimes: ready = the existing chime (untouched); max = that chime 3x cascading up + sparkles + warm bloom
birds  : ready = a little song phrase;         max = the phrase 3x climbing + trill + answering birds
ocean  : ready = sonar ping + echo;            max = 3 rising pings + bubbles + dolphins + whale call"""
import math, os, sys
import numpy as np
import soundfile as sf
from scipy import signal

MEDIA, OUT = sys.argv[1], sys.argv[2]
SR = 44100
rng = np.random.default_rng(12)


def note(n):            # semitones from A4
    return 440.0 * 2 ** (n / 12)


G = {k: v for k, v in {'G3': -14, 'B3': -10, 'D4': -7, 'G4': -2, 'B4': 2, 'D5': 5, 'E5': 7, 'G5': 10,
                       'A5': 12, 'B5': 14, 'D6': 17, 'E6': 19, 'G6': 22, 'A6': 24, 'B6': 26, 'D7': 29,
                       'E7': 31, 'G7': 34, 'A7': 36, 'B7': 38, 'D8': 41}.items()}
F = {k: note(v) for k, v in G.items()}


def buf(sec):
    return np.zeros((int(sec * SR), 2))


def place(out, x, t, gain=1.0, pan=0.0):
    """mix mono or stereo x into out at time t (sec), constant-power pan -1..1"""
    i = int(t * SR)
    x = x.copy()
    k = min(len(x), int(0.06 * SR))                          # fade every note's end: no clicks
    w = np.cos(np.linspace(0, math.pi / 2, k)) ** 2
    x[-k:] = x[-k:] * (w if x.ndim == 1 else w[:, None])
    if x.ndim == 1:
        a = (pan + 1) * math.pi / 4
        x = np.stack([x * math.cos(a), x * math.sin(a)], 1) * math.sqrt(2)
    n = min(len(x), len(out) - i)
    if n > 0:
        out[i:i + n] += x[:n] * gain


def env_ad(n, att, dec_tau, sr=SR):
    t = np.arange(n) / sr
    a = np.minimum(1, t / max(att, 1e-4))
    a = np.sin(a * math.pi / 2) ** 2
    return a * np.exp(-np.maximum(0, t - att) / dec_tau)


def lowpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), 'low')
    return signal.lfilter(b, a, x, axis=0)


def highpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), 'high')
    return signal.lfilter(b, a, x, axis=0)


def bandpass(x, f0, f1, order=2):
    b, a = signal.butter(order, [f0 / (SR / 2), f1 / (SR / 2)], 'band')
    return signal.lfilter(b, a, x, axis=0)


def reverb(x, rt60=1.6, wet=0.25, pre=0.018, damp=6000, seed=1, er=True):
    """synthetic stereo hall: decorrelated decaying noise, darker as it decays"""
    r = np.random.default_rng(seed)
    n = int(rt60 * SR * 1.1)
    t = np.arange(n) / SR
    decay = np.exp(-6.9 * t / rt60)
    ir = np.zeros((n, 2))
    for ch in range(2):
        noise = r.standard_normal(n) * decay
        # darken the tail: blend a low-passed copy in over time
        dark = lowpass(noise, damp * 0.35, 1)
        k = np.clip(t / (rt60 * 0.6), 0, 1)
        ir[:, ch] = lowpass(noise * (1 - k) + dark * k * 1.6, damp, 1)
    p = int(pre * SR)
    ir = np.concatenate([np.zeros((p, 2)), ir])
    if er:
        for d, g in ((0.011, 0.5), (0.019, 0.35), (0.027, 0.3), (0.041, 0.22)):
            j = int(d * SR)
            ir[j, 0] += g * r.uniform(0.7, 1.0)
            ir[j + int(0.003 * SR), 1] += g * r.uniform(0.7, 1.0)
    ir /= np.sqrt((ir ** 2).sum(0, keepdims=True))
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    wetsig = np.stack([signal.fftconvolve(x[:, c], ir[:, c]) for c in range(2)], 1)
    out = np.zeros_like(wetsig)
    out[:len(x)] = x * (1 - wet * 0.5)
    return out + wetsig * wet


def finish(x, lufs=-14.5, fade=0.3):
    """clean up, trim the silent tail, soft-limit, and match perceived loudness (LUFS)"""
    import pyloudnorm as pyln
    x = x - x.mean(0)
    x = highpass(x, 60, 2)
    x = x / np.abs(x).max()
    x = np.tanh(x * 1.15) / np.tanh(1.15)                           # gentle soft clip
    env = np.convolve(np.abs(x).max(1), np.ones(441) / 441, 'same')
    alive = np.where(env > 10 ** (-48 / 20))[0]                       # -48 dB below peak = done
    x = x[:alive[-1] + int(0.05 * SR)] if len(alive) else x
    n = int(fade * SR)
    if len(x) > n:
        x[-n:] *= np.linspace(1, 0, n)[:, None] ** 2
    x[:64] *= np.linspace(0, 1, 64)[:, None]
    meter = pyln.Meter(SR, block_size=0.2)
    x = x * 10 ** ((lufs - meter.integrated_loudness(x)) / 20)
    if np.abs(x).max() > 0.89:
        x = x / np.abs(x).max() * 0.89
    return x


def write(name, x):
    sf.write(os.path.join(OUT, name + '.ogg'), x.astype(np.float32), SR, format='OGG', subtype='VORBIS')
    sf.write(os.path.join(OUT, name + '.wav'), x.astype(np.float32), SR)
    act = x[np.abs(x).max(1) > 0.02]
    import pyloudnorm as pyln
    print(f"{name}: {len(x) / SR:.2f}s peak {np.abs(x).max():.2f} {pyln.Meter(SR, block_size=0.2).integrated_loudness(x):.1f} LUFS")


# ---------------------------------------------------------------------------------------------
# instruments
# ---------------------------------------------------------------------------------------------
def bell(f, dur=1.2, att=0.002, tau=0.35, bright=1.0):
    """celesta / glockenspiel-like: a few partials, upper ones dying faster"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for ratio, g, td in ((1, 1.0, 1.0), (2.0, 0.28 * bright, 0.5), (3.0, 0.10 * bright, 0.32),
                         (4.16, 0.06 * bright, 0.2), (5.43, 0.035 * bright, 0.14)):
        if f * ratio > 16000:
            continue
        x += g * np.sin(2 * math.pi * f * ratio * t + rng.uniform(0, 6)) * np.exp(-t / (tau * td))
    return x * env_ad(n, att, 99)


def epiano(f, dur=2.2, att=0.03, tau=0.9):
    """soft FM e-piano: warm bloom under the cascade"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    idx = 1.2 * np.exp(-t / 0.25) + 0.15
    x = np.sin(2 * math.pi * f * t + idx * np.sin(2 * math.pi * f * t))
    x += 0.3 * np.sin(2 * math.pi * f * 2 * t) * np.exp(-t / 0.4)
    return x * env_ad(n, att, tau)


def pitch(x, up, down):
    """resample: plays `down/up` times faster -> pitch up by that ratio (like speeding up tape)"""
    return signal.resample_poly(x, up, down)


# ---------------------------------------------------------------------------------------------
# 1. CHIMES max: the ready chime 3x, cascading root -> fifth -> octave, then sparkles + bloom
# ---------------------------------------------------------------------------------------------
ready, sr0 = sf.read(os.path.join(MEDIA, 'ready.ogg'))
assert sr0 == SR
if ready.ndim > 1:
    ready = ready.mean(1)
ready = ready / np.abs(ready).max()

out = buf(4.2)
place(out, ready, 0.00, 0.78, -0.25)
place(out, lowpass(pitch(ready, 2, 3), 11000), 0.27, 0.62, 0.25)        # +7 (a fifth), 1.5x faster
place(out, lowpass(pitch(ready, 1, 2), 8000), 0.48, 0.46, 0.0)          # +12 (an octave), 2x faster
# warm bloom: G major chord swelling in under the last run
for nm, g in (('G4', 0.20), ('B4', 0.13), ('D5', 0.14), ('G5', 0.12)):
    place(out, epiano(F[nm], 2.6, 0.05, 1.1), 0.62, g, rng.uniform(-0.3, 0.3))
place(out, epiano(F['G3'], 2.6, 0.08, 1.2), 0.62, 0.10, 0)
# the jackpot sparkle: a quick rising pentatonic cascade of tiny bells, accelerating
seq = ['G6', 'A6', 'B6', 'D7', 'E7', 'G7', 'A7', 'B7']
t = 0.66
for i, nm in enumerate(seq):
    place(out, bell(F[nm], 1.0, 0.002, 0.22, 0.6), t, 0.17 - i * 0.008, -0.6 if i % 2 else 0.6)
    t += 0.085 - i * 0.006
# final star: top G with a shimmering tremolo, plus its octave-below partner
st = bell(F['G7'], 1.6, 0.004, 0.55, 0.4) * (1 + 0.35 * np.sin(2 * math.pi * 11 * np.arange(int(1.6 * SR)) / SR))
place(out, st, t + 0.04, 0.12, 0.15)
place(out, bell(F['D7'], 1.6, 0.004, 0.6, 0.4), t + 0.06, 0.09, -0.15)
out = reverb(out, rt60=1.9, wet=0.30, pre=0.02, damp=7000, seed=3)
out = lowpass(out, 12500, 1)
write('max', finish(out, -13.8))


# ---------------------------------------------------------------------------------------------
# 2. BIRDS
# ---------------------------------------------------------------------------------------------
def syl(f0, f1, dur, curve=1.0, att=0.006, rel=0.02, vib=0.0, vib_hz=0.0, trill=0.0, trill_hz=0.0,
        harm=(1.0, 0.12, 0.04), shape=None):
    """one bird syllable: a whistled glide (pure tone + a touch of harmonics)"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    fr = f0 + (f1 - f0) * (u ** curve if shape is None else shape(u))
    if vib:
        fr = fr * (1 + vib * np.sin(2 * math.pi * vib_hz * t))
    ph = 2 * math.pi * np.cumsum(fr) / SR
    x = sum(g * np.sin(ph * (k + 1)) for k, g in enumerate(harm))
    e = np.minimum(1, t / att) * np.minimum(1, (dur - t) / rel)
    e = np.clip(e, 0, 1) ** 1.5
    if trill:
        e = e * (1 - trill * (0.5 + 0.5 * np.cos(2 * math.pi * trill_hz * t)))
    return x * e


def phrase(sh=0.0, speed=1.0):
    """'tsip-tsip-tweee!': two quick up-slurs then a sweet rising whistle. sh = semitones."""
    k = 2 ** (sh / 12)
    out = np.zeros(int(1.1 * SR))
    def put(x, t, g=1.0):
        i = int(t * SR / speed)
        out[i:i + len(x)] += x[:len(out) - i] * g
    put(syl(2600 * k, 3900 * k, 0.055 / speed, 0.7), 0.00, 0.8)
    put(syl(2700 * k, 4100 * k, 0.055 / speed, 0.7), 0.11, 0.85)
    # the 'tweee': G7 gliding up to B7 with a little vibrato, swelling then softening
    sw = syl(F['G7'] * k * 0.94, F['B7'] * k, 0.30 / speed, shape=lambda u: 1 - (1 - u) ** 2.2,
             att=0.03, rel=0.08, vib=0.012, vib_hz=26)
    put(sw, 0.24, 1.0)
    put(syl(F['B7'] * k, F['G7'] * k * 0.98, 0.06 / speed, 1.0, rel=0.03), 0.24 + 0.33, 0.55)
    return out


b = buf(2.4)
place(b, phrase(-5), 0.05, 0.9, 0.1)
# a soft distant reply from another bird
place(b, phrase(-9, 1.1), 0.95, 0.22, -0.7)
b = reverb(b, rt60=0.9, wet=0.2, pre=0.012, damp=9000, seed=5)
write('bird_ready', finish(b, -14.5))

b = buf(4.2)
# the phrase three times, each a step higher and a little quicker: D, G, B (cascading up)
for i, (sh, sp, t0, pan) in enumerate(((-10, 1.0, 0.00, -0.35), (-5, 1.12, 0.55, 0.35), (-1, 1.25, 1.02, 0.0))):
    place(b, phrase(sh, sp), t0, 0.62 + 0.08 * i, pan)
# a canary trill climbing to the top
t = 1.48
for i in range(16):
    f = 2400 * (2 ** (i / 13))
    place(b, syl(f, f * 1.22, 0.024, 0.8, att=0.003, rel=0.008), t, 0.42, 0.2 * math.sin(i))
    t += 0.031
# 'tweet-tweet!' at the top: B7 -> D8 bright pair, then a long happy G7 whistle with vibrato
place(b, syl(F['B7'] * 0.96, F['D8'], 0.07, 0.6), t + 0.03, 0.55, 0.1)
place(b, syl(F['B7'] * 0.96, F['D8'], 0.07, 0.6), t + 0.15, 0.55, -0.1)
place(b, syl(F['G7'] * 1.03, F['G7'], 0.55, 1.0, att=0.02, rel=0.25, vib=0.018, vib_hz=18), t + 0.3, 0.42, 0)
# dawn chorus: other birds joining in the background
for j in range(9):
    f = rng.uniform(2600, 4600)
    tt = rng.uniform(1.2, 2.9)
    place(b, syl(f, f * rng.uniform(0.75, 1.3), rng.uniform(0.04, 0.11), 1.0), tt, rng.uniform(0.08, 0.16),
          rng.uniform(-0.9, 0.9))
b = reverb(b, rt60=1.1, wet=0.24, pre=0.012, damp=9000, seed=6)
write('bird_max', finish(b, -13.8))


# ---------------------------------------------------------------------------------------------
# 3. OCEAN
# ---------------------------------------------------------------------------------------------
def ping(f, dur=1.6):
    """sonar ping: pure tone, soft-but-quick attack, slight Doppler sag, long decay"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    fr = f * (1 - 0.006 * (1 - np.exp(-t / 0.4)))
    ph = 2 * math.pi * np.cumsum(fr) / SR
    x = np.sin(ph) + 0.18 * np.sin(2 * ph) * np.exp(-t / 0.15) + 0.05 * np.sin(3 * ph) * np.exp(-t / 0.08)
    k = int(0.25 * SR)
    x = x * env_ad(n, 0.006, 0.42)
    x[-k:] *= np.cos(np.linspace(0, math.pi / 2, k)) ** 2
    return x


def with_echo(x, delay=0.42, g=0.32, n=2):
    y = np.concatenate([x, np.zeros(int(SR * delay * (n + 0.5)))])
    for k in range(1, n + 1):
        e = lowpass(x, 2600 / k, 2) * (g ** k)
        i = int(delay * k * SR)
        y[i:i + len(e)] += e
    return y


def bubble(f0):
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    fr = f0 * (1 + 2.2 * t / 0.06)
    return np.sin(2 * math.pi * np.cumsum(fr) / SR) * env_ad(n, 0.002, 0.018)


def whistle(f0, f1, dur, loops=1.5, depth=0.12):
    """dolphin whistle: a rising sweep with looping frequency modulation"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    fr = (f0 + (f1 - f0) * u ** 1.4) * (1 + depth * np.sin(2 * math.pi * loops * u) * u)
    x = np.sin(2 * math.pi * np.cumsum(fr) / SR) + 0.1 * np.sin(4 * math.pi * np.cumsum(fr) / SR)
    e = np.clip(np.minimum(t / 0.03, (dur - t) / 0.06), 0, 1)
    return x * e


def clicks(t_len, start_rate, end_rate):
    n = int(t_len * SR)
    x = np.zeros(n)
    t = 0.0
    while t < t_len:
        u = t / t_len
        rate = start_rate + (end_rate - start_rate) * u
        i = int(t * SR)
        k = np.arange(min(90, n - i))
        x[i:i + len(k)] += np.sin(2 * math.pi * 6000 * k / SR) * np.exp(-k / 14) * (0.6 + 0.4 * u)
        t += 1 / rate
    return x


def whale(f0, f1, dur):
    """humpback-style call: a slow rising moan with harmonics and a gentle vibrato"""
    n = int(dur * SR)
    t = np.arange(n) / SR
    u = t / dur
    fr = f0 * (f1 / f0) ** (np.clip(u * 1.25, 0, 1) ** 1.6)
    fr = fr * (1 + 0.012 * np.sin(2 * math.pi * 5.2 * t))
    ph = 2 * math.pi * np.cumsum(fr) / SR
    x = np.sin(ph) + 0.55 * np.sin(2 * ph) + 0.32 * np.sin(3 * ph) + 0.18 * np.sin(4 * ph) + 0.08 * np.sin(5 * ph)
    x = bandpass(x, 140, 2400, 1)
    e = np.sin(np.clip(u, 0, 1) * math.pi) ** 0.8
    return x * e


o = buf(3.2)
place(o, with_echo(ping(F['D6'])), 0.03, 0.75, 0.0)
for i, f in enumerate(rng.uniform(500, 1300, 6)):
    place(o, bubble(f), 0.0 + i * 0.05 + rng.uniform(0, 0.03), 0.10, rng.uniform(-0.6, 0.6))
o = reverb(lowpass(o, 7000), rt60=2.4, wet=0.32, pre=0.03, damp=3500, seed=8, er=False)
write('ocean_ready', finish(o, -14.5))

o = buf(5.0)
# three pings rising G5 -> D6 -> G6, echoing off the sea floor
for i, (nm, t0, pan) in enumerate((('G5', 0.00, -0.4), ('D6', 0.30, 0.4), ('G6', 0.58, 0.0))):
    place(o, with_echo(ping(F[nm], 1.4), 0.36, 0.28), t0, 0.55 + 0.05 * i, pan)
# a stream of bubbles rising (higher as they go)
for i in range(26):
    tt = 0.5 + i * 0.045 + rng.uniform(0, 0.03)
    place(o, bubble(rng.uniform(500, 900) * (1 + i / 18)), tt, 0.09, rng.uniform(-0.7, 0.7))
# dolphins: an excited click buzz and two looping whistles
place(o, clicks(0.45, 18, 120), 0.82, 0.10, -0.5)
place(o, whistle(4200, 7800, 0.55, 1.5, 0.10), 0.95, 0.15, 0.55)
place(o, whistle(5200, 9200, 0.42, 2.0, 0.08), 1.38, 0.12, -0.45)
# the whale: a deep call sweeping up G3 -> G4 under everything, resolving the cascade
place(o, whale(F['G3'] * 0.8, F['G4'], 2.4), 0.70, 0.40, 0.0)
place(o, bell(F['G6'], 1.6, 0.01, 0.6, 0.2), 2.15, 0.10, 0.2)
place(o, bell(F['D7'], 1.6, 0.01, 0.6, 0.2), 2.22, 0.08, -0.2)
o = reverb(lowpass(o, 9000), rt60=2.8, wet=0.34, pre=0.03, damp=3800, seed=9, er=False)
write('ocean_max', finish(o, -13.8))
