"""Tests for Art-Net packet construction (reatc_artnet.py)."""

import struct
from reatc_artnet import build_artnet_timecode


class TestBuildArtnetTimecode:
    """Test Art-Net TimeCode packet builder."""

    def test_packet_length(self):
        """Art-Net TC packet must be exactly 19 bytes."""
        pkt = build_artnet_timecode(1, 2, 3, 4, 1)
        assert len(pkt) == 19

    def test_header(self):
        """Packet starts with 'Art-Net\\0'."""
        pkt = build_artnet_timecode(0, 0, 0, 0, 0)
        assert pkt[:8] == b"Art-Net\x00"

    def test_opcode(self):
        """OpCode is 0x9700 (little-endian)."""
        pkt = build_artnet_timecode(0, 0, 0, 0, 0)
        opcode = struct.unpack_from("<H", pkt, 8)[0]
        assert opcode == 0x9700

    def test_protocol_version(self):
        """Protocol version is 14 (0x000E big-endian)."""
        pkt = build_artnet_timecode(0, 0, 0, 0, 0)
        assert pkt[10] == 0x00  # ProtVerHi
        assert pkt[11] == 0x0E  # ProtVerLo

    def test_timecode_fields(self):
        """TC fields are in correct byte positions."""
        pkt = build_artnet_timecode(12, 34, 56, 23, 2)
        assert pkt[14] == 23   # frames
        assert pkt[15] == 56   # seconds
        assert pkt[16] == 34   # minutes
        assert pkt[17] == 12   # hours
        assert pkt[18] == 2    # type (29.97DF)

    def test_all_framerates(self):
        """All four framerate types produce valid packets."""
        for tc_type in range(4):
            pkt = build_artnet_timecode(0, 0, 0, 0, tc_type)
            assert pkt[18] == tc_type

    def test_max_values(self):
        """Maximum valid TC values are encoded correctly."""
        pkt = build_artnet_timecode(23, 59, 59, 29, 3)
        assert pkt[14] == 29
        assert pkt[15] == 59
        assert pkt[16] == 59
        assert pkt[17] == 23
        assert pkt[18] == 3

    def test_zero_values(self):
        """All-zero TC produces correct packet."""
        pkt = build_artnet_timecode(0, 0, 0, 0, 0)
        assert pkt[14:19] == bytes(5)

    def test_byte_masking(self):
        """Values are masked to 0xFF (overflow protection)."""
        pkt = build_artnet_timecode(256, 0, 0, 0, 0)
        assert pkt[17] == 0  # 256 & 0xFF == 0
