#!/usr/bin/env python3
"""
Build script for ReaTC.

Reads version.txt, substitutes {{VERSION}} in source files,
generates index.xml from template, and copies to dist/.
"""

import os
import sys
import shutil
import re
from pathlib import Path

# Get script directory
BUILD_DIR = Path(__file__).parent
REPO_ROOT = BUILD_DIR.parent
SRC_DIR = REPO_ROOT / "src"
DIST_DIR = REPO_ROOT / "dist"
VERSION_FILE = REPO_ROOT / "version.txt"

def read_version():
    """Read version from version.txt"""
    if not VERSION_FILE.exists():
        raise FileNotFoundError(f"version.txt not found at {VERSION_FILE}")
    with open(VERSION_FILE, "r") as f:
        version = f.read().strip()
    if not version:
        raise ValueError("version.txt is empty")
    return version

def substitute_version(content, version):
    """Replace {{VERSION}} placeholder with actual version"""
    return content.replace("{{VERSION}}", version)

def build():
    """Build and distribute files"""
    try:
        version = read_version()
        print(f"Building ReaTC v{version}...")
        print()
        
        # Verify source directory exists
        if not SRC_DIR.exists():
            raise FileNotFoundError(f"src/ directory not found at {SRC_DIR}")
        
        # Clean dist directory
        if DIST_DIR.exists():
            shutil.rmtree(DIST_DIR)
            print("  ✓ Cleaned previous dist/")
        DIST_DIR.mkdir(parents=True, exist_ok=True)
        
        # Create Scripts/ReaTC subdirectory in dist
        dist_scripts_dir = DIST_DIR / "Scripts" / "ReaTC"
        dist_scripts_dir.mkdir(parents=True, exist_ok=True)
        
        # Process source files: substitute version and copy to dist
        src_scripts_dir = SRC_DIR / "Scripts" / "ReaTC"
        if not src_scripts_dir.exists():
            raise FileNotFoundError(f"Source scripts dir not found at {src_scripts_dir}")
        
        files_processed = 0
        for filepath in sorted(src_scripts_dir.iterdir()):
            if filepath.is_file():
                with open(filepath, "r") as f:
                    content = f.read()
                content = substitute_version(content, version)
                dist_file = dist_scripts_dir / filepath.name
                with open(dist_file, "w") as f:
                    f.write(content)
                print(f"  ✓ {filepath.name}")
                files_processed += 1
        
        if files_processed == 0:
            raise ValueError("No source files found in src/Scripts/ReaTC/")
        
        # Copy LICENSE, README.md to dist root
        for filename in ["LICENSE", "README.md"]:
            src = REPO_ROOT / filename
            dst = DIST_DIR / filename
            if src.exists():
                shutil.copy2(src, dst)
                print(f"  ✓ {filename}")
        
        # Generate index.xml for ReaPack
        index_xml = generate_index_xml(version)
        root_index_path = REPO_ROOT / "index.xml"
        dist_index_path = DIST_DIR / "index.xml"
        for index_path in [root_index_path, dist_index_path]:
            with open(index_path, "w") as f:
                f.write(index_xml)
        print("  ✓ index.xml (repo root)")
        print("  ✓ index.xml (dist)")
        
        print()
        print(f"✓ Build complete: {DIST_DIR}")
        return 0
        
    except Exception as e:
        print(f"✗ Build failed: {e}", file=sys.stderr)
        return 1

def read_changelog(version):
    """Extract changelog notes for a specific version from CHANGELOG.md"""
    changelog_file = REPO_ROOT / "CHANGELOG.md"
    if not changelog_file.exists():
        return f"Release {version}. See https://github.com/paskateknikko/ReaTC/releases/tag/v{version} for details."
    
    with open(changelog_file, "r") as f:
        content = f.read()
    
    lines = content.splitlines()
    notes = []
    in_section = False
    for line in lines:
        if re.match(rf"^## \[{re.escape(version)}\]", line):
            in_section = True
            continue
        if in_section:
            if re.match(r"^## \[", line):
                break
            notes.append(line)
    
    notes_text = "\n".join(notes).strip()
    if notes_text:
        return notes_text
    return f"Release {version}. See https://github.com/paskateknikko/ReaTC/releases/tag/v{version} for details."


def generate_index_xml(version):
    """Generate ReaPack index.xml with all source files and proper metadata"""
    from datetime import datetime
    
    # Generate ISO 8601 timestamp (UTC)
    timestamp = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    
    changelog = read_changelog(version)
    about_rtf = "{\\rtf1\\ansi\\deff0\n{\\fonttbl{\\f0 Helvetica;}}\n\\f0\\fs22\\b ReaTC\\b0\\par\nArt-Net and MIDI Timecode sender for REAPER.\\par\nSupports transport timecode or LTC audio input.\\par\n}"
    
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<index version="1" name="ReaTC">
  <category name="Timecode">
    <reapack name="ReaTC.lua" type="script" desc="Art-Net and MIDI Timecode sender for REAPER">
            <metadata>
                <description><![CDATA[{about_rtf}]]></description>
        <link rel="website">https://github.com/paskateknikko/ReaTC</link>
        <link rel="donation">https://github.com/paskateknikko/ReaTC</link>
      </metadata>
      <version name="{version}" author="Tuukka Aimasmäki" time="{timestamp}">
        <changelog><![CDATA[{changelog}]]></changelog>
        <source main="main" file="Scripts/ReaTC/ReaTC.lua">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/ReaTC.lua</source>
        <source file="Scripts/ReaTC/reatc_core.lua">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_core.lua</source>
        <source file="Scripts/ReaTC/reatc_ltc.lua">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_ltc.lua</source>
        <source file="Scripts/ReaTC/reatc_outputs.lua">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_outputs.lua</source>
        <source file="Scripts/ReaTC/reatc_ui.lua">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_ui.lua</source>
        <source file="Scripts/ReaTC/reatc_udp.py">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_udp.py</source>
        <source file="Scripts/ReaTC/reatc_mtc.py">https://github.com/paskateknikko/ReaTC/raw/gh-pages/Scripts/ReaTC/reatc_mtc.py</source>
      </version>
    </reapack>
  </category>
</index>
'''


if __name__ == "__main__":
    sys.exit(build())
