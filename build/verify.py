#!/usr/bin/env python3
"""
Verification script for ReaTC build output.

Checks that all expected files exist in dist/ with correct version substitutions.
"""

import sys
from pathlib import Path

BUILD_DIR = Path(__file__).parent
REPO_ROOT = BUILD_DIR.parent
DIST_DIR = REPO_ROOT / "dist"
VERSION_FILE = REPO_ROOT / "version.txt"

def read_version():
    """Read version from version.txt"""
    with open(VERSION_FILE, "r") as f:
        return f.read().strip()

def verify():
    """Verify build output"""
    version = read_version()
    
    print(f"Verifying ReaTC v{version} build...")
    print()
    
    if not DIST_DIR.exists():
        print("✗ dist/ directory not found")
        return 1
    
    expected_files = {
        "LICENSE": None,  # No version check
        "README.md": None,
        "index.xml": version,
        # Only files containing {{VERSION}} need substitution checks
        "Scripts/ReaTC/ReaTC.lua": None,
        "Scripts/ReaTC/reatc_core.lua": version,
        "Scripts/ReaTC/reatc_ltc.lua": None,
        "Scripts/ReaTC/reatc_outputs.lua": None,
        "Scripts/ReaTC/reatc_ui.lua": None,
        "Scripts/ReaTC/reatc_udp.py": version,
        "Scripts/ReaTC/reatc_mtc.py": version,
    }
    
    missing = []
    version_errors = []
    
    for filename, expected_version in expected_files.items():
        filepath = DIST_DIR / filename
        if not filepath.exists():
            missing.append(filename)
            print(f"  ✗ {filename} — missing")
        else:
            print(f"  ✓ {filename}")
            
            # Check version substitution if expected
            if expected_version:
                with open(filepath, "r") as f:
                    content = f.read()
                if expected_version not in content:
                    version_errors.append(filename)
                    print(f"    ↳ WARNING: version {expected_version} not found in content")
                elif "{{VERSION}}" in content:
                    version_errors.append(filename)
                    print(f"    ↳ ERROR: {{{{VERSION}}}} placeholder not substituted")
    
    print()
    
    if missing:
        print(f"✗ Missing {len(missing)} file(s)")
        return 1
    elif version_errors:
        print(f"✗ Version substitution errors in {len(version_errors)} file(s)")
        return 1
    else:
        print(f"✓ All files present and version correctly substituted")
        return 0

if __name__ == "__main__":
    sys.exit(verify())
