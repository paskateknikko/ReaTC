"""Shared fixtures and path setup for ReaTC tests."""

import sys
from pathlib import Path

# Add source directories to path so tests can import daemon modules
SRC_SCRIPTS = Path(__file__).parent.parent / "src" / "Scripts" / "ReaTC"
BUILD_DIR = Path(__file__).parent.parent / "build"

sys.path.insert(0, str(SRC_SCRIPTS))
sys.path.insert(0, str(BUILD_DIR))
