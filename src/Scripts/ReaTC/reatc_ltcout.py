#!/usr/bin/env python3
# ReaTC — https://github.com/<org>/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# LTC (Linear Timecode) Audio Output Daemon / WAV Generator
# Persistent process that encodes timecode as LTC audio and outputs it.
#
# Usage:
#   python3 reatc_ltcout.py [device_name]   -- start daemon, reads commands from stdin
#   python3 reatc_ltcout.py --list-devices  -- print available audio output devices
#   python3 reatc_ltcout.py --generate <file> <H> <M> <S> <F> <type> <duration>
#                                              -- generate LTC WAV file
#
# Stdin protocol (one command per line):
#   play H M S F type   -- start/continue playback at given TC position
#   stop H M S F type   -- stop playback (outputs silence)
#
#   type: 0=24fps  1=25fps  2=29.97DF  3=30fps
#
# Requirements:
#   pip3 install sounddevice numpy

__version__ = "{{VERSION}}"

import sys
import time
import threading
import collections
import wave
import struct

try:
    import numpy as np
    NP_AVAILABLE = True
except ImportError:
    NP_AVAILABLE = False

try:
    import sounddevice as sd
    SD_AVAILABLE = True
except ImportError:
    SD_AVAILABLE = False

SAMPLE_RATE  = 48000
# Samples per frame at each rate (fractional for 29.97)
FPS_TABLE     = {0: 24.0, 1: 25.0, 2: 29.97, 3: 30.0}
INT_FPS_TABLE = {0: 24,   1: 25,   2: 30,    3: 30}
# Target pre-buffered audio (seconds)
_TARGET_BUF_SEC = 1.0


def list_devices():
    if not SD_AVAILABLE:
        print("ERROR: sounddevice/numpy not installed. "
              "Run: pip3 install sounddevice numpy")
        return
    devices = sd.query_devices()
    for i, d in enumerate(devices):
        if d['max_output_channels'] > 0:
            print(f"{i}: {d['name']}")


def generate_ltc_wav(filename, h, m, s, f, tc_type, duration):
    """Generate LTC WAV file with specified timecode and duration.
    
    Parameters
    ----------
    filename : str        Output WAV file path
    h, m, s, f : int      Starting timecode
    tc_type : int         Frame rate type (0-3)
    duration : float      Duration in seconds
    """
    if not NP_AVAILABLE:
        print("ERROR: numpy not installed. Run: pip3 install numpy", file=sys.stderr)
        return False
    
    fps = FPS_TABLE.get(tc_type, 25.0)
    total_samples = int(duration * SAMPLE_RATE)
    
    # Generate LTC audio
    audio_data = []
    level = 1
    ideal_pos = 0.0
    current_h, current_m, current_s, current_f = h, m, s, f
    samples_generated = 0
    
    while samples_generated < total_samples:
        # Generate one frame
        frame_samples, level, ideal_pos = encode_ltc_frame(
            current_h, current_m, current_s, current_f,
            tc_type, level, ideal_pos
        )
        
        audio_data.append(frame_samples)
        samples_generated += len(frame_samples)
        
        # Advance to next frame
        current_h, current_m, current_s, current_f = _advance_frame(
            current_h, current_m, current_s, current_f, tc_type
        )
    
    # Concatenate all frames
    audio_array = np.concatenate(audio_data)
    
    # Trim to exact duration
    audio_array = audio_array[:total_samples]
    
    # Convert to 16-bit PCM at -6dB (0.5 amplitude)
    audio_int16 = (audio_array * 32767 * 0.5).astype(np.int16)
    
    # Write WAV file
    try:
        with wave.open(filename, 'wb') as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(SAMPLE_RATE)
            wav_file.writeframes(audio_int16.tobytes())
        return True
    except Exception as e:
        print(f"ERROR writing WAV file: {e}", file=sys.stderr)
        return False


# ---------------------------------------------------------------------------
# LTC encoding helpers
# ---------------------------------------------------------------------------

def _advance_frame(h, m, s, f, tc_type):
    int_fps = INT_FPS_TABLE.get(tc_type, 25)
    f += 1
    if f >= int_fps:
        f = 0
        s += 1
        if s >= 60:
            s = 0
            m += 1
            if m >= 60:
                m = 0
                h = (h + 1) % 24
    return h, m, s, f


def encode_ltc_frame(h, m, s, f, tc_type, start_level, ideal_pos):
    """Encode one LTC frame as biphase mark code.

    Parameters
    ----------
    h, m, s, f : int   timecode components
    tc_type    : int   0-3 (frame-rate selector)
    start_level: int   +1 or -1, current signal polarity before this frame
    ideal_pos  : float running count of ideal sample position (for fractional fps)

    Returns
    -------
    samples   : numpy float32 array
    end_level : int   +1 or -1 after this frame
    ideal_pos : float updated ideal position
    """
    fps = FPS_TABLE.get(tc_type, 25.0)
    spb = SAMPLE_RATE / (fps * 80.0)   # samples per bit (may be fractional)

    # --- Build 80-bit LTC word (BCD, LSB first within each field) ----------
    bits = [0] * 80

    # Frames
    f_u, f_t = f % 10, f // 10
    for i in range(4): bits[i]     = (f_u >> i) & 1
    for i in range(2): bits[8 + i] = (f_t >> i) & 1
    if tc_type == 2:   bits[10]    = 1          # drop-frame flag

    # Seconds
    s_u, s_t = s % 10, s // 10
    for i in range(4): bits[16 + i] = (s_u >> i) & 1
    for i in range(3): bits[24 + i] = (s_t >> i) & 1

    # Minutes
    m_u, m_t = m % 10, m // 10
    for i in range(4): bits[32 + i] = (m_u >> i) & 1
    for i in range(3): bits[40 + i] = (m_t >> i) & 1

    # Hours
    h_u, h_t = h % 10, h // 10
    for i in range(4): bits[48 + i] = (h_u >> i) & 1
    for i in range(2): bits[56 + i] = (h_t >> i) & 1

    # Sync word  bits[64..79] = 0011111111111101
    sync_pattern = [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1]
    for i, b in enumerate(sync_pattern):
        bits[64 + i] = b

    # Polarity correction (bit 27): total '1' bits in bits[0..63] must be even
    if sum(bits[0:64]) % 2 != 0:
        bits[27] ^= 1

    # --- Biphase mark encoding ---------------------------------------------
    # Always a transition at the start of each bit cell.
    # '1' bit: also a transition at the mid-point of the cell.
    output = []
    level  = start_level

    for bit in bits:
        # Start of cell: always transition
        level = -level

        # Determine sample count for each half-cell using ideal position
        half_spb     = spb / 2.0
        next_pos_mid = ideal_pos + half_spb
        n1           = round(next_pos_mid) - round(ideal_pos)
        ideal_pos    = next_pos_mid

        output.extend([level] * max(n1, 1))

        # Mid-cell: transition only for '1'
        if bit == 1:
            level = -level

        next_pos_end = ideal_pos + half_spb
        n2           = round(next_pos_end) - round(ideal_pos)
        ideal_pos    = next_pos_end

        output.extend([level] * max(n2, 1))

    return np.array(output, dtype=np.float32), level, ideal_pos


# ---------------------------------------------------------------------------
# LTC output daemon class
# ---------------------------------------------------------------------------

class LTCOutDaemon:
    """Continuously outputs LTC audio.  TC position is updated via `update()`."""

    def __init__(self, device=None):
        self._device    = device
        self._lock      = threading.Lock()
        self._buf_lock  = threading.Lock()

        # Shared state (protected by _lock)
        self._playing   = False
        self._tc_type   = 1
        self._pending   = None  # (h, m, s, f, tc_type) or None

        # Audio ring-buffer (deque of numpy chunks)
        self._chunks       = collections.deque()
        self._buf_samples  = 0
        self._chunk_offset = 0   # offset into self._chunks[0]

        self._running = True
        self._gen_thread = threading.Thread(target=self._generate_loop, daemon=True)
        self._gen_thread.start()

        self._stream = sd.OutputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype='float32',
            blocksize=512,
            device=device,
            callback=self._callback,
        )
        self._stream.start()

    # ------------------------------------------------------------------
    # Audio callback (called from sounddevice's audio thread)
    # ------------------------------------------------------------------

    def _callback(self, outdata, frames, time_info, status):
        with self._buf_lock:
            remaining = frames
            offset    = 0
            while remaining > 0 and self._chunks:
                chunk     = self._chunks[0]
                available = len(chunk) - self._chunk_offset
                take      = min(remaining, available)
                outdata[offset:offset + take, 0] = chunk[self._chunk_offset:
                                                          self._chunk_offset + take]
                offset           += take
                remaining        -= take
                self._buf_samples -= take
                self._chunk_offset += take
                if self._chunk_offset >= len(chunk):
                    self._chunks.popleft()
                    self._chunk_offset = 0
            if remaining > 0:
                outdata[offset:, 0] = 0.0

    # ------------------------------------------------------------------
    # Generator thread – keeps the audio buffer filled
    # ------------------------------------------------------------------

    def _generate_loop(self):
        target_samples = int(SAMPLE_RATE * _TARGET_BUF_SEC)

        # Local frame counter for pre-generation (ahead of playback)
        h, m, s, f  = 0, 0, 0, 0
        tc_type      = 1
        level        = 1
        ideal_pos    = 0.0
        playing      = False

        while self._running:
            with self._lock:
                pending  = self._pending
                self._pending = None
                playing  = self._playing
                tc_type  = self._tc_type

            if pending is not None:
                h, m, s, f, tc_type = pending
                level     = 1
                ideal_pos = 0.0
                # Flush pre-generated buffer so playback starts cleanly
                with self._buf_lock:
                    self._chunks.clear()
                    self._buf_samples  = 0
                    self._chunk_offset = 0

            with self._buf_lock:
                buf_samples = self._buf_samples

            if buf_samples < target_samples:
                if playing:
                    samples, level, ideal_pos = encode_ltc_frame(
                        h, m, s, f, tc_type, level, ideal_pos)
                    h, m, s, f = _advance_frame(h, m, s, f, tc_type)
                else:
                    # Silence; keep size consistent with one frame
                    fps  = FPS_TABLE.get(tc_type, 25.0)
                    n    = int(round(SAMPLE_RATE / fps))
                    samples = np.zeros(n, dtype=np.float32)
                    ideal_pos += n

                with self._buf_lock:
                    self._chunks.append(samples)
                    self._buf_samples += len(samples)
            else:
                time.sleep(0.005)

    # ------------------------------------------------------------------
    # Public API (called from main thread / stdin reader)
    # ------------------------------------------------------------------

    def update(self, cmd, h, m, s, f, tc_type):
        with self._lock:
            self._tc_type = tc_type
            if cmd == "play":
                if not self._playing:
                    # Transition stop→play: sync immediately
                    self._pending = (h, m, s, f, tc_type)
                else:
                    # Already playing: only sync if position differs significantly
                    self._pending = (h, m, s, f, tc_type)
                self._playing = True
            elif cmd == "stop":
                self._playing = False
                self._pending = (h, m, s, f, tc_type)

    def close(self):
        self._running = False
        self._gen_thread.join(timeout=2.0)
        self._stream.stop()
        self._stream.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    if "--list-devices" in sys.argv:
        list_devices()
        return
    
    # Handle WAV file generation mode
    if "--generate" in sys.argv:
        try:
            idx = sys.argv.index("--generate")
            if len(sys.argv) < idx + 8:
                print("Usage: reatc_ltcout.py --generate <file> <H> <M> <S> <F> <type> <duration>",
                      file=sys.stderr)
                sys.exit(1)
            
            filename = sys.argv[idx + 1]
            h = int(sys.argv[idx + 2])
            m = int(sys.argv[idx + 3])
            s = int(sys.argv[idx + 4])
            f = int(sys.argv[idx + 5])
            tc_type = int(sys.argv[idx + 6])
            duration = float(sys.argv[idx + 7])
            
            if generate_ltc_wav(filename, h, m, s, f, tc_type, duration):
                sys.exit(0)
            else:
                sys.exit(1)
        except (ValueError, IndexError) as e:
            print(f"ERROR: Invalid arguments - {e}", file=sys.stderr)
            sys.exit(1)
    
    # Daemon mode
    if not SD_AVAILABLE:
        print("ERROR: sounddevice/numpy not installed. "
              "Run: pip3 install sounddevice numpy", file=sys.stderr)
        sys.exit(1)

    device = None
    for arg in sys.argv[1:]:
        if not arg.startswith("--"):
            # Try numeric device index first, then string name
            try:
                device = int(arg)
            except ValueError:
                device = arg
            break

    try:
        daemon = LTCOutDaemon(device)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 6:
                continue
            cmd = parts[0]
            try:
                h       = int(parts[1])
                m       = int(parts[2])
                s       = int(parts[3])
                f       = int(parts[4])
                tc_type = int(parts[5])
                daemon.update(cmd, h, m, s, f, tc_type)
            except (ValueError, IndexError):
                pass
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        daemon.close()


if __name__ == "__main__":
    main()
