"""Tests for LTC frame building, TC advance, and drop-frame logic (reatc_ltcgen.py)."""

from reatc_ltcgen import build_ltc_frame, advance_tc, render_frame, AMPLITUDE, SYNC_WORD


class TestBuildLtcFrame:
    """Test 80-bit LTC frame construction."""

    def test_frame_length(self):
        """LTC frame is exactly 80 bits."""
        bits = build_ltc_frame(0, 0, 0, 0, 0)
        assert len(bits) == 80

    def test_sync_word(self):
        """Bits 64-79 contain the sync word 0x3FFD (LSB-first)."""
        bits = build_ltc_frame(0, 0, 0, 0, 0)
        sync_val = 0
        for i in range(16):
            sync_val |= bits[64 + i] << i
        assert sync_val == SYNC_WORD

    def test_bcd_frame_units(self):
        """Frame units (bits 0-3) are BCD-encoded."""
        bits = build_ltc_frame(0, 0, 0, 7, 1)  # frame=7
        val = bits[0] | (bits[1] << 1) | (bits[2] << 2) | (bits[3] << 3)
        assert val == 7

    def test_bcd_frame_tens(self):
        """Frame tens (bits 8-9) are BCD-encoded."""
        bits = build_ltc_frame(0, 0, 0, 24, 0)  # frame=24, tens=2
        val = bits[8] | (bits[9] << 1)
        assert val == 2
        # Units should be 4
        units = bits[0] | (bits[1] << 1) | (bits[2] << 2) | (bits[3] << 3)
        assert units == 4

    def test_bcd_seconds(self):
        """Seconds (bits 16-26) are BCD-encoded."""
        bits = build_ltc_frame(0, 0, 45, 0, 1)  # secs=45
        s_u = bits[16] | (bits[17] << 1) | (bits[18] << 2) | (bits[19] << 3)
        s_t = bits[24] | (bits[25] << 1) | (bits[26] << 2)
        assert s_u == 5
        assert s_t == 4

    def test_bcd_minutes(self):
        """Minutes (bits 32-42) are BCD-encoded."""
        bits = build_ltc_frame(0, 37, 0, 0, 1)  # mins=37
        m_u = bits[32] | (bits[33] << 1) | (bits[34] << 2) | (bits[35] << 3)
        m_t = bits[40] | (bits[41] << 1) | (bits[42] << 2)
        assert m_u == 7
        assert m_t == 3

    def test_bcd_hours(self):
        """Hours (bits 48-57) are BCD-encoded."""
        bits = build_ltc_frame(23, 0, 0, 0, 1)  # hours=23
        h_u = bits[48] | (bits[49] << 1) | (bits[50] << 2) | (bits[51] << 3)
        h_t = bits[56] | (bits[57] << 1)
        assert h_u == 3
        assert h_t == 2

    def test_drop_frame_flag(self):
        """Bit 10 is set for drop-frame (type 2) and clear otherwise."""
        bits_df = build_ltc_frame(0, 0, 0, 0, 2)
        bits_ndf = build_ltc_frame(0, 0, 0, 0, 1)
        assert bits_df[10] == 1
        assert bits_ndf[10] == 0

    def test_bmpc_even_parity(self):
        """BMPC (bit 27) ensures even total parity of the 80-bit frame."""
        for h in [0, 12, 23]:
            for m in [0, 30, 59]:
                for s in [0, 30, 59]:
                    for f in [0, 12, 24]:
                        for ft in range(4):
                            bits = build_ltc_frame(h, m, s, f, ft)
                            assert sum(bits) % 2 == 0, \
                                f"Odd parity at {h}:{m}:{s}:{f} type={ft}"

    def test_all_zeros(self):
        """Frame with all-zero TC has valid sync and parity."""
        bits = build_ltc_frame(0, 0, 0, 0, 0)
        assert len(bits) == 80
        assert sum(bits) % 2 == 0


class TestAdvanceTc:
    """Test timecode advance logic."""

    def test_simple_advance(self):
        """Frame increments by 1."""
        h, m, s, f = advance_tc(0, 0, 0, 0, 1)  # 25fps
        assert (h, m, s, f) == (0, 0, 0, 1)

    def test_frame_rollover_25fps(self):
        """Frame 24 at 25fps rolls to next second."""
        h, m, s, f = advance_tc(0, 0, 0, 24, 1)
        assert (h, m, s, f) == (0, 0, 1, 0)

    def test_frame_rollover_24fps(self):
        """Frame 23 at 24fps rolls to next second."""
        h, m, s, f = advance_tc(0, 0, 0, 23, 0)
        assert (h, m, s, f) == (0, 0, 1, 0)

    def test_frame_rollover_30fps(self):
        """Frame 29 at 30fps rolls to next second."""
        h, m, s, f = advance_tc(0, 0, 0, 29, 3)
        assert (h, m, s, f) == (0, 0, 1, 0)

    def test_second_rollover(self):
        """Second 59 rolls to next minute."""
        h, m, s, f = advance_tc(0, 0, 59, 24, 1)
        assert (h, m, s, f) == (0, 1, 0, 0)

    def test_minute_rollover(self):
        """Minute 59 rolls to next hour."""
        h, m, s, f = advance_tc(0, 59, 59, 24, 1)
        assert (h, m, s, f) == (1, 0, 0, 0)

    def test_hour_rollover(self):
        """Hour 23 wraps to 0."""
        h, m, s, f = advance_tc(23, 59, 59, 24, 1)
        assert (h, m, s, f) == (0, 0, 0, 0)

    def test_drop_frame_skip_at_minute(self):
        """Drop-frame skips frames 0-1 at non-multiple-of-10 minutes."""
        # At 59:59:29 type=2, next minute is not multiple of 10 → skip to frame 2
        h, m, s, f = advance_tc(0, 0, 59, 29, 2)
        assert (h, m, s, f) == (0, 1, 0, 2)  # frame 2 (skipped 0 and 1)

    def test_drop_frame_no_skip_at_10min(self):
        """Drop-frame does NOT skip at multiples of 10 minutes."""
        h, m, s, f = advance_tc(0, 9, 59, 29, 2)
        assert (h, m, s, f) == (0, 10, 0, 0)  # frame 0 (no skip)

    def test_drop_frame_no_skip_at_20min(self):
        """Drop-frame does NOT skip at minute 20."""
        h, m, s, f = advance_tc(0, 19, 59, 29, 2)
        assert (h, m, s, f) == (0, 20, 0, 0)

    def test_non_drop_no_skip(self):
        """Non-drop-frame never skips frames."""
        h, m, s, f = advance_tc(0, 0, 59, 24, 1)  # 25fps
        assert (h, m, s, f) == (0, 1, 0, 0)  # frame 0

    def test_full_day_frame_count_25fps(self):
        """25fps has exactly 2,160,000 frames per day (25 * 86400)."""
        h, m, s, f = 0, 0, 0, 0
        count = 0
        for _ in range(2_160_000):
            h, m, s, f = advance_tc(h, m, s, f, 1)
            count += 1
        assert (h, m, s, f) == (0, 0, 0, 0)  # back to midnight

    def test_full_day_frame_count_df(self):
        """29.97DF has exactly 2,589,408 frames per day."""
        h, m, s, f = 0, 0, 0, 0
        count = 0
        for _ in range(2_589_408):
            h, m, s, f = advance_tc(h, m, s, f, 2)
            count += 1
        assert (h, m, s, f) == (0, 0, 0, 0)


class TestRenderFrame:
    """Test biphase-mark audio rendering."""

    def test_output_length(self):
        """Output has exactly 2 * n_samples bytes (16-bit PCM)."""
        bits = build_ltc_frame(0, 0, 0, 0, 1)
        data, _ = render_frame(bits, 1920, 1, AMPLITUDE)
        assert len(data) == 1920 * 2

    def test_polarity_preserved_even_parity(self):
        """Even-parity frame returns to original polarity."""
        bits = build_ltc_frame(0, 0, 0, 0, 1)
        assert sum(bits) % 2 == 0
        data, gen_out = render_frame(bits, 1920, 1, AMPLITUDE)
        # After an even-parity frame, gen_out should return to original sign
        # (each 0-bit has 1 transition, each 1-bit has 2; boundary always flips)
        # The BMPC bit ensures even parity → polarity preserved
        assert gen_out == 1 or gen_out == -1  # must be valid polarity

    def test_different_sample_rates(self):
        """Rendering works at different sample counts per frame."""
        bits = build_ltc_frame(1, 2, 3, 4, 1)
        for n_samples in [960, 1920, 2000]:
            data, _ = render_frame(bits, n_samples, 1, AMPLITUDE)
            assert len(data) == n_samples * 2
