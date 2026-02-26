"""Tests for OSC packet construction (reatc_osc.py)."""

import struct
from reatc_osc import osc_string, build_osc_timecode


class TestOscString:
    """Test OSC string encoding."""

    def test_null_termination(self):
        """OSC strings are null-terminated."""
        result = osc_string("test")
        assert b"\x00" in result

    def test_4byte_alignment(self):
        """OSC strings are padded to 4-byte boundary."""
        for s in ["", "a", "ab", "abc", "abcd", "abcde", "abcdefgh"]:
            result = osc_string(s)
            assert len(result) % 4 == 0, f"'{s}' produced {len(result)} bytes"

    def test_content_preserved(self):
        """String content is preserved before null terminator."""
        result = osc_string("/tc")
        assert result[:3] == b"/tc"

    def test_empty_string(self):
        """Empty string produces 4 bytes (null + 3 pad)."""
        result = osc_string("")
        assert len(result) == 4
        assert result[0:1] == b"\x00"

    def test_exact_boundary(self):
        """String that naturally aligns still has null terminator."""
        # "abc" = 3 bytes + null = 4 bytes, already aligned
        result = osc_string("abc")
        assert len(result) == 4
        assert result[3:4] == b"\x00"

    def test_osc_address_encoding(self):
        """Typical OSC address encodes correctly."""
        result = osc_string("/timecode/main")
        assert result.startswith(b"/timecode/main\x00")
        assert len(result) % 4 == 0


class TestBuildOscTimecode:
    """Test OSC timecode message builder."""

    def test_type_tag(self):
        """Message contains ',iiiii' type tag."""
        pkt = build_osc_timecode("/tc", 0, 0, 0, 0, 0)
        assert b",iiiii" in pkt

    def test_five_int32_args(self):
        """Message contains 5 big-endian int32 arguments."""
        pkt = build_osc_timecode("/tc", 1, 23, 45, 12, 1)
        # Find the arguments after the type tag string
        addr_len = len(osc_string("/tc"))
        tag_len = len(osc_string(",iiiii"))
        args_start = addr_len + tag_len
        args = struct.unpack_from(">iiiii", pkt, args_start)
        assert args == (1, 23, 45, 12, 1)

    def test_address_in_packet(self):
        """OSC address is the first element in the packet."""
        pkt = build_osc_timecode("/tc", 0, 0, 0, 0, 0)
        assert pkt[:3] == b"/tc"

    def test_custom_address(self):
        """Custom OSC addresses work correctly."""
        pkt = build_osc_timecode("/show/timecode", 10, 20, 30, 15, 2)
        assert pkt.startswith(b"/show/timecode")

    def test_all_framerates(self):
        """All framerate types produce valid packets."""
        for tc_type in range(4):
            pkt = build_osc_timecode("/tc", 0, 0, 0, 0, tc_type)
            addr_len = len(osc_string("/tc"))
            tag_len = len(osc_string(",iiiii"))
            args = struct.unpack_from(">iiiii", pkt, addr_len + tag_len)
            assert args[4] == tc_type

    def test_max_values(self):
        """Maximum valid TC values are encoded correctly."""
        pkt = build_osc_timecode("/tc", 23, 59, 59, 29, 3)
        addr_len = len(osc_string("/tc"))
        tag_len = len(osc_string(",iiiii"))
        args = struct.unpack_from(">iiiii", pkt, addr_len + tag_len)
        assert args == (23, 59, 59, 29, 3)
