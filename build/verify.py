#!/usr/bin/env python3
"""
Verification script for ReaTC build output.

Checks that all expected files exist in dist/ with correct version substitutions.
Version is passed via --version flag (default: DEV).
"""

import re
import sys
from pathlib import Path

BUILD_DIR = Path(__file__).parent
REPO_ROOT = BUILD_DIR.parent
DIST_BASE = REPO_ROOT / "dist"
PLATFORMS_ENV = BUILD_DIR / "platforms.env"
REAPACK_ENV = BUILD_DIR / "reapack.env"


def parse_env(path):
    """Parse a KEY=VALUE env file into a dict."""
    config = {}
    if path.exists():
        for line in path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                m = re.match(r"^([A-Z_]+)=(.+)$", line)
                if m:
                    config[m.group(1)] = m.group(2)
    return config


def verify_badges(config, dist_dir):
    """Check that README.md badges match platforms.env values."""
    readme = REPO_ROOT / "README.md"
    if not readme.exists():
        # README is optional in dist; check repo root
        readme = dist_dir / "README.md"
    if not readme.exists():
        print("  ⚠ README.md not found, skipping badge check")
        return []

    content = readme.read_text()
    errors = []

    macos_target = config.get("MACOS_DEPLOYMENT_TARGET")
    win_version = config.get("WINDOWS_MIN_VERSION")

    if macos_target:
        # Badge format: macOS-10.15%2B  (URL-encoded '+')
        pattern = rf"macOS-{re.escape(macos_target)}%2B"
        if not re.search(pattern, content):
            errors.append(f"macOS badge missing or wrong (expected {macos_target})")

    if win_version:
        # Badge format: Windows-10%2B
        pattern = rf"Windows-{re.escape(win_version)}%2B"
        if not re.search(pattern, content):
            errors.append(f"Windows badge missing or wrong (expected {win_version})")

    return errors


def verify(version="DEV"):
    """Verify build output"""
    print(f"Verifying ReaTC v{version} build...")
    print()

    # Read ReaPack config for install paths
    reapack = parse_env(REAPACK_ENV)
    index_name = reapack.get("REAPACK_INDEX_NAME", "ReaTC")
    category = reapack.get("REAPACK_CATEGORY", "Timecode")
    scripts_dir = f"Scripts/{index_name}/{category}"
    effects_dir = f"Effects/{index_name}/{category}"

    dist_dir = DIST_BASE / f"{index_name}-{version}"
    if not dist_dir.exists():
        print(f"✗ {dist_dir.relative_to(REPO_ROOT)} not found")
        return 1

    expected_files = {
        "LICENSE": None,
        "README.md": None,
        "ABOUT.md": None,
        "RELEASE_NOTES.md": None,
        f"{scripts_dir}/reatc.lua": version,
        f"{scripts_dir}/reatc_core.lua": version,
        f"{scripts_dir}/reatc_outputs.lua": version,
        f"{scripts_dir}/reatc_ui.lua": version,
        f"{scripts_dir}/reatc_regions_to_ltc.lua": version,
        f"{scripts_dir}/reatc_artnet.py": version,
        f"{scripts_dir}/reatc_osc.py": version,
        f"{scripts_dir}/reatc_ltcgen.py": version,
        f"{effects_dir}/reatc_tc.jsfx": version,
    }

    missing = []
    version_errors = []

    for filename, expected_version in expected_files.items():
        filepath = dist_dir / filename
        if not filepath.exists():
            missing.append(filename)
            print(f"  ✗ {filename} — missing")
        else:
            print(f"  ✓ {filename}")

            # Check version substitution if expected
            if expected_version:
                with open(filepath, "r", encoding="utf-8") as f:
                    content = f.read()
                if expected_version not in content:
                    version_errors.append(filename)
                    print(f"    ↳ WARNING: version {expected_version} not found in content")
                elif "{{VERSION}}" in content:
                    version_errors.append(filename)
                    print(f"    ↳ ERROR: {{{{VERSION}}}} placeholder not substituted")

    print()

    # Check README badges match platforms.env
    badge_errors = []
    config = parse_env(PLATFORMS_ENV)
    if config:
        print("Checking deployment target badges...")
        badge_errors = verify_badges(config, dist_dir)
        for err in badge_errors:
            print(f"  ✗ {err}")
        if not badge_errors:
            print("  ✓ Badges match platforms.env")
        print()

    if missing:
        print(f"✗ Missing {len(missing)} file(s)")
        return 1
    elif version_errors:
        print(f"✗ Version substitution errors in {len(version_errors)} file(s)")
        return 1
    elif badge_errors:
        print(f"✗ Badge mismatch: {len(badge_errors)} error(s)")
        return 1
    else:
        print(f"✓ All files present and version correctly substituted")
        return 0


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', default='DEV',
                        help='Version string (default: DEV)')
    args = parser.parse_args()
    sys.exit(verify(version=args.version))
