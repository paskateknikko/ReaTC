#!/usr/bin/env python3
"""
Development setup for ReaTC.

Makes build scripts executable and ensures proper permissions.
Run this once after cloning the repository.
"""

import os
import stat
from pathlib import Path

REPO_ROOT = Path(__file__).parent
BUILD_SCRIPTS = [
    REPO_ROOT / "build" / "build.py",
    REPO_ROOT / "build" / "verify.py",
    REPO_ROOT / "src" / "Scripts" / "ReaTC" / "reatc_artnet.py",
    REPO_ROOT / "src" / "Scripts" / "ReaTC" / "reatc_osc.py",
    REPO_ROOT / "src" / "Scripts" / "ReaTC" / "reatc_ltcgen.py",
]

def setup():
    """Make scripts executable"""
    print("Setting up ReaTC development environment...")
    print()

    for script in BUILD_SCRIPTS:
        if script.exists():
            # Add execute permission for owner
            st = script.stat()
            script.chmod(st.st_mode | stat.S_IEXEC | stat.S_IXUSR | stat.S_IXGRP)
            print(f"  ✓ Made executable: {script.relative_to(REPO_ROOT)}")
        else:
            print(f"  ⊘ Not found: {script.relative_to(REPO_ROOT)}")

    print()
    print("✓ Setup complete. You can now run: make build")

if __name__ == "__main__":
    setup()
