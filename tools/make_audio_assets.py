#!/usr/bin/env python3
"""Generate the VN demo's tiny OGG assets.

Music loops are *seamless by construction*: every oscillator frequency and
every amplitude LFO is an exact integer multiple of 1/T, so the waveform at
t=T equals the waveform at t=0 and Godot's loop point is click-free.

Outputs (mono, 22.05 kHz, Vorbis) — every file must stay under 20 KB:
  assets/music/day.ogg    ~4 s warm classroom pad (C major add9)
  assets/music/night.ogg  ~4 s cool evening pad (A minor 7 + drone)
  assets/sfx/click.ogg    UI tick
  assets/sfx/open.ogg     panel open sweep
  assets/sfx/close.ogg    panel close sweep
  assets/sfx/confirm.ogg  choice confirm chime
  assets/sfx/save.ogg     save/load arpeggio
  assets/sfx/error.ogg    error buzz
"""
import os
import subprocess
import wave

import numpy as np
import imageio_ffmpeg

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
SR = 22050
OUT = "/home/user/repo/assets"
LIMIT = 20 * 1024


def write_wav(path: str, sig: np.ndarray) -> None:
    sig = np.clip(sig, -1.0, 1.0)
    pcm = (sig * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def to_ogg(wav_path: str, ogg_path: str, bitrate: str = "28k") -> None:
    subprocess.run(
        [FFMPEG, "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-b:a", bitrate, "-ar", str(SR), "-ac", "1", ogg_path],
        check=True)
    size = os.path.getsize(ogg_path)
    assert size < LIMIT, f"{ogg_path} is {size} bytes (>= {LIMIT})"
    print(f"  {ogg_path}  {size:>6} bytes")


def tone(t: np.ndarray, freq: float, amp: float = 1.0, phase: float = 0.0) -> np.ndarray:
    return amp * np.sin(2 * np.pi * freq * t + phase)


def one_pole_lowpass(sig: np.ndarray, cutoff: float) -> np.ndarray:
    """Cheap RC lowpass to take the synthetic edge off the pads."""
    rc = 1.0 / (2 * np.pi * cutoff)
    dt = 1.0 / SR
    a = dt / (rc + dt)
    out = np.empty_like(sig)
    acc = 0.0
    for i, s in enumerate(sig):
        acc += a * (s - acc)
        out[i] = acc
    return out


def snap(freq: float, T: float) -> float:
    """Snap a frequency to the nearest harmonic of 1/T -> perfect loop."""
    return round(freq * T) / T


def make_pad(T: float, notes, sub, lfo_beats, brightness) -> np.ndarray:
    n = int(T * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    # Slow amplitude LFOs, integer cycles over T so the loop closes.
    for i, (f0, amp, pan_phase) in enumerate(notes):
        f = snap(f0, T)
        lfo_hz = lfo_beats[i] / T  # integer cycles per loop
        lfo = 0.72 + 0.28 * np.sin(2 * np.pi * lfo_hz * t + pan_phase)
        # Fundamental + a quiet octave for shimmer.
        voice = tone(t, f, amp) + tone(t, snap(f0 * 2, T), amp * 0.22, phase=0.7)
        sig += voice * lfo
    sub_f = snap(sub[0], T)
    sig += tone(t, sub_f, sub[1]) * (0.85 + 0.15 * np.sin(2 * np.pi * (1 / T) * t))
    sig = one_pole_lowpass(sig, brightness)
    # Gentle tape-style saturation keeps peaks musical after normalizing.
    sig = np.tanh(1.4 * sig)
    sig /= max(1e-9, np.max(np.abs(sig)))
    # Tiny 4 ms equal-power edge blend kills any residual DC-step click.
    fade = int(0.004 * SR)
    ramp = np.linspace(0, np.pi / 2, fade)
    sig[:fade] *= np.sin(ramp)
    sig[-fade:] *= np.cos(ramp)
    return sig * 0.89


def env_exp(n: int, tau: float, attack_ms: float = 2.0) -> np.ndarray:
    t = np.arange(n) / SR
    atk = max(1, int(attack_ms / 1000 * SR))
    e = np.exp(-t / tau)
    e[:atk] *= np.linspace(0, 1, atk)
    return e


def main() -> None:
    os.makedirs(f"{OUT}/music", exist_ok=True)
    os.makedirs(f"{OUT}/sfx", exist_ok=True)

    # --- music: day (C major add9, warm) ---
    T = 4.0
    day = make_pad(
        T,
        notes=[(261.63, 0.50, 0.0), (329.63, 0.34, 1.9), (392.00, 0.30, 3.6), (587.33, 0.16, 5.1)],
        sub=(130.81, 0.30),
        lfo_beats=[1, 1, 2, 2],
        brightness=2600.0,
    )
    write_wav("/tmp/day.wav", day)
    to_ogg("/tmp/day.wav", f"{OUT}/music/day.ogg", "30k")

    # --- music: night (A minor 7 + low drone, cool) ---
    night = make_pad(
        T,
        notes=[(220.00, 0.46, 0.4), (261.63, 0.30, 2.3), (329.63, 0.26, 4.2), (392.00, 0.20, 5.7)],
        sub=(110.00, 0.34),
        lfo_beats=[1, 1, 1, 2],
        brightness=1800.0,
    )
    write_wav("/tmp/night.wav", night)
    to_ogg("/tmp/night.wav", f"{OUT}/music/night.ogg", "30k")

    # --- sfx ---
    def sfx(name: str, sig: np.ndarray, bitrate: str = "32k") -> None:
        sig = sig / max(1e-9, np.max(np.abs(sig))) * 0.9
        write_wav(f"/tmp/{name}.wav", sig)
        to_ogg(f"/tmp/{name}.wav", f"{OUT}/sfx/{name}.ogg", bitrate)

    # click: 25 ms filtered noise burst + a 1.6 kHz tick
    n = int(0.025 * SR)
    rng = np.random.default_rng(7)
    click = rng.normal(0, 1, n) * env_exp(n, 0.004, 0.4)
    click += tone(np.arange(n) / SR, 1600, 0.8) * env_exp(n, 0.006, 0.4)
    sfx("click", click)

    # open: 130 ms rising sine sweep 420 -> 950 Hz
    n = int(0.13 * SR)
    t = np.arange(n) / SR
    f = 420 * (950 / 420) ** (t / t[-1])
    phase = 2 * np.pi * np.cumsum(f) / SR
    sfx("open", np.sin(phase) * env_exp(n, 0.09, 4.0) + rng.normal(0, 0.25, n) * env_exp(n, 0.01, 1.0))

    # close: 130 ms falling sweep 900 -> 380 Hz
    f = 900 * (380 / 900) ** (t / t[-1])
    phase = 2 * np.pi * np.cumsum(f) / SR
    sfx("close", np.sin(phase) * env_exp(n, 0.09, 4.0))

    # confirm: E5 -> A5 chime, 300 ms (two sequential partials, own decays)
    n = int(0.30 * SR)
    chime = np.zeros(n)
    a_at = int(0.12 * SR)
    seg_a = np.arange(a_at) / SR
    seg_b = np.arange(n - a_at) / SR
    chime[:a_at] += (tone(seg_a, 659.25) + 0.4 * tone(seg_a, 1318.5)) * env_exp(a_at, 0.06, 2.0)
    chime[a_at:] += (tone(seg_b, 880.0) + 0.4 * tone(seg_b, 1760.0)) * env_exp(n - a_at, 0.08, 2.0)
    sfx("confirm", chime)

    # save: C5-E5-G5 bell arpeggio, 420 ms
    n = int(0.42 * SR)
    bell = np.zeros(n)
    for k, f0 in enumerate([523.25, 659.25, 783.99]):
        start = int(k * 0.09 * SR)
        seg = np.arange(n - start) / SR
        bell[start:] += (tone(seg, f0) + 0.35 * tone(seg, f0 * 2) + 0.15 * tone(seg, f0 * 3)) \
            * env_exp(n - start, 0.10, 2.0)
    sfx("save", bell)

    # error: two short detuned low buzzes, 240 ms
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    buzz = (np.sign(np.sin(2 * np.pi * 196 * t)) * 0.6 + tone(t, 196, 0.5)) * env_exp(n, 0.035, 3.0)
    gap = np.zeros(int(0.05 * SR))
    sfx("error", np.concatenate([buzz, gap, buzz]))

    print("all assets under 20 KB ✔")


if __name__ == "__main__":
    main()
