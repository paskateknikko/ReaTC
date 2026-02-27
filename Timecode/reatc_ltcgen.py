#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# LTC Audio Generator
# Generates a SMPTE/EBU LTC WAV file for a given timecode start and duration.
# Uses the same biphase-mark encoding as reatc_ltc.jsfx — no external deps.
#
# Usage: python3 reatc_ltcgen.py <fps_type> <h> <m> <s> <f>
#                                <n_frames> <sample_rate> <output_path>
#
# fps_type: 0=24fps  1=25fps  2=29.97DF  3=30fps
#
# @noindex
# @version 1.1.0

from __future__ import annotations

__version__ = "1.1.0"

import sys
import struct
import wave

# Integer frame counts (29.97 DF uses 30 integer frames per display frame)
FPS_INT = {0: 24, 1: 25, 2: 30, 3: 30}
# Exact frame rates (used for sample-accurate frame boundaries)
FPS_VAL = {0: 24.0, 1: 25.0, 2: 29.97, 3: 30.0}

# SMPTE LTC sync word (bits 64-79), stored LSB-first — matches reatc_ltc.jsfx
SYNC_WORD = 0x3FFD

# Output amplitude: ~50 % of int16 range, leaves headroom for the decoder
AMPLITUDE = 16383


def build_ltc_frame(h: int, m: int, s: int, f: int, fps_type: int) -> list[int]:
    """Build the 80-bit LTC word as a list of ints (0 or 1), LSB-first.

    @param h: Hours (0-23).
    @param m: Minutes (0-59).
    @param s: Seconds (0-59).
    @param f: Frame number (0-29).
    @param fps_type: Frame-rate type (0=24fps, 1=25fps, 2=29.97DF, 3=30fps).
    @return: List of 80 integers, each 0 or 1, representing the LTC frame bits.
    """
    bits = [0] * 80
    drop = fps_type == 2

    # BCD decompose
    f_u, f_t = f % 10, f // 10
    s_u, s_t = s % 10, s // 10
    m_u, m_t = m % 10, m // 10
    h_u, h_t = h % 10, h // 10

    # Bits 0-3: frame units
    for i in range(4): bits[0  + i] = (f_u >> i) & 1
    # Bits 4-7: user bits (0)
    # Bits 8-9: frame tens
    for i in range(2): bits[8  + i] = (f_t >> i) & 1
    # Bit 10: drop-frame flag
    bits[10] = 1 if drop else 0
    # Bit 11: color frame (0); bits 12-15: user bits (0)

    # Bits 16-19: seconds units
    for i in range(4): bits[16 + i] = (s_u >> i) & 1
    # Bits 20-23: user bits (0)
    # Bits 24-26: seconds tens
    for i in range(3): bits[24 + i] = (s_t >> i) & 1
    # Bit 27: BMPC — computed below; bits 28-31: user bits (0)

    # Bits 32-35: minutes units
    for i in range(4): bits[32 + i] = (m_u >> i) & 1
    # Bits 36-39: user bits (0)
    # Bits 40-42: minutes tens
    for i in range(3): bits[40 + i] = (m_t >> i) & 1
    # Bit 43: BGF0 (0); bits 44-47: user bits (0)

    # Bits 48-51: hours units
    for i in range(4): bits[48 + i] = (h_u >> i) & 1
    # Bits 52-55: user bits (0)
    # Bits 56-57: hours tens
    for i in range(2): bits[56 + i] = (h_t >> i) & 1
    # Bits 58-63: BGF1, BGF2, user bits (0)

    # Bits 64-79: sync word 0x3FFD, stored LSB-first (mirrors JSFX logic)
    for i in range(16):
        bits[64 + i] = (SYNC_WORD >> i) & 1

    # BMPC (bit 27): set so that the total count of 1-bits in the 80-bit
    # frame is even.  This makes the biphase-mark transition count even,
    # which guarantees the output returns to the original polarity each frame.
    ones = sum(bits[i] for i in range(64) if i != 27) + sum(bits[64:80])
    bits[27] = ones % 2

    return bits


def advance_tc(h: int, m: int, s: int, f: int, fps_type: int) -> tuple[int, int, int, int]:
    """Increment timecode by one frame, handling drop-frame correctly.

    @param h: Hours (0-23).
    @param m: Minutes (0-59).
    @param s: Seconds (0-59).
    @param f: Frame number.
    @param fps_type: Frame-rate type (0=24fps, 1=25fps, 2=29.97DF, 3=30fps).
    @return: Tuple of (hours, minutes, seconds, frames) after advancing one frame.
    """
    fps = FPS_INT[fps_type]
    drop = fps_type == 2
    f += 1
    if f >= fps:
        f = 0
        s += 1
        if s >= 60:
            s = 0
            m += 1
            if drop and m % 10 != 0:
                f = 2  # skip frames 0 and 1 on non-multiple-of-10 minutes
            if m >= 60:
                m = 0
                h = (h + 1) % 24
    return h, m, s, f


def render_frame(bits: list[int], n_samples: int, gen_out: int, amplitude: int = AMPLITUDE) -> tuple[bytes, int]:
    """Convert 80 LTC bits to n_samples int16 PCM bytes using biphase-mark.

    Encoding rules (matches reatc_ltc.jsfx @sample block):
      - bit boundary (start of each bit):  always flip gen_out
      - bit midpoint:                       flip gen_out only for 1-bits

    @param bits: List of 80 ints (0 or 1) from build_ltc_frame().
    @param n_samples: Number of PCM samples to generate for this frame.
    @param gen_out: Current output polarity (+1 or -1).
    @param amplitude: Peak sample value (default AMPLITUDE).
    @return: Tuple of (raw PCM bytes, final gen_out polarity).
    """
    pos_bytes = struct.pack("<h",  amplitude)
    neg_bytes = struct.pack("<h", -amplitude)

    def smp(level):
        return pos_bytes if level > 0 else neg_bytes

    parts = []
    for i, bit in enumerate(bits):
        bit_start = round(i       * n_samples / 80)
        bit_mid   = round((i + 0.5) * n_samples / 80)
        bit_end   = round((i + 1)   * n_samples / 80)

        n_first  = bit_mid - bit_start
        n_second = bit_end - bit_mid

        # First half of bit at current level
        parts.append(smp(gen_out) * n_first)

        # Mid-bit transition for 1-bits
        if bit:
            gen_out = -gen_out

        # Second half of bit
        parts.append(smp(gen_out) * n_second)

        # Boundary transition (always, at start of next bit)
        gen_out = -gen_out

    return b"".join(parts), gen_out


def generate_ltc_wav(fps_type: int, h: int, m: int, s: int, f: int,
                     n_frames: int, sample_rate: int, out_path: str,
                     amplitude: int = AMPLITUDE) -> None:
    """Write a mono 16-bit WAV containing n_frames of LTC audio.

    @param fps_type: Frame-rate type (0=24fps, 1=25fps, 2=29.97DF, 3=30fps).
    @param h: Starting hours (0-23).
    @param m: Starting minutes (0-59).
    @param s: Starting seconds (0-59).
    @param f: Starting frame number.
    @param n_frames: Total number of timecode frames to render.
    @param sample_rate: Audio sample rate in Hz (e.g. 48000).
    @param out_path: Filesystem path for the output WAV file.
    @param amplitude: Peak sample value (default AMPLITUDE).
    """
    fps_val = FPS_VAL[fps_type]
    gen_out = 1  # initial polarity
    ch, cm, cs, cf = h, m, s, f

    with wave.open(out_path, "w") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)       # 16-bit PCM
        wav.setframerate(sample_rate)

        for frame_idx in range(n_frames):
            # Sample-accurate frame boundary (same rounding as JSFX phase acc)
            frame_start = round(frame_idx       * sample_rate / fps_val)
            frame_end   = round((frame_idx + 1) * sample_rate / fps_val)
            n_samples   = frame_end - frame_start

            bits = build_ltc_frame(ch, cm, cs, cf, fps_type)
            frame_bytes, gen_out = render_frame(bits, n_samples, gen_out,
                                                amplitude)
            wav.writeframes(frame_bytes)

            ch, cm, cs, cf = advance_tc(ch, cm, cs, cf, fps_type)


def main() -> None:
    """Entry point: parse CLI arguments and generate an LTC WAV file."""
    if len(sys.argv) < 9:
        print(
            "Usage: reatc_ltcgen.py <fps_type> <h> <m> <s> <f>"
            " <n_frames> <sample_rate> <output_path>",
            file=sys.stderr,
        )
        sys.exit(1)

    fps_type    = int(sys.argv[1])
    h           = int(sys.argv[2])
    m           = int(sys.argv[3])
    s           = int(sys.argv[4])
    f           = int(sys.argv[5])
    n_frames    = int(sys.argv[6])
    sample_rate = int(sys.argv[7])
    out_path    = sys.argv[8]
    amplitude   = max(1, min(32767, int(sys.argv[9]))) if len(sys.argv) > 9 else AMPLITUDE

    generate_ltc_wav(fps_type, h, m, s, f, n_frames, sample_rate, out_path,
                     amplitude)


if __name__ == "__main__":
    main()
