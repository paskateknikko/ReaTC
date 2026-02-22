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
        
        # Create Scripts/ReaTC and Effects/ReaTC subdirectories in dist
        dist_scripts_dir = DIST_DIR / "Scripts" / "ReaTC"
        dist_effects_dir = DIST_DIR / "Effects" / "ReaTC"
        dist_scripts_dir.mkdir(parents=True, exist_ok=True)
        dist_effects_dir.mkdir(parents=True, exist_ok=True)

        # Process source files: substitute version and copy to dist
        src_dirs = [
            (SRC_DIR / "Scripts" / "ReaTC", dist_scripts_dir),
            (SRC_DIR / "Effects" / "ReaTC", dist_effects_dir),
        ]

        files_processed = 0
        for src_dir, dist_dir in src_dirs:
            if not src_dir.exists():
                continue
            for filepath in sorted(src_dir.iterdir()):
                if filepath.is_file():
                    with open(filepath, "r") as f:
                        content = f.read()
                    content = substitute_version(content, version)
                    dist_file = dist_dir / filepath.name
                    with open(dist_file, "w") as f:
                        f.write(content)
                    print(f"  ✓ {filepath.name}")
                    files_processed += 1

        if files_processed == 0:
            raise ValueError("No source files found in src/")
        
        # Copy LICENSE, README.md to dist root
        for filename in ["LICENSE", "README.md"]:
            src = REPO_ROOT / filename
            dst = DIST_DIR / filename
            if src.exists():
                shutil.copy2(src, dst)
                print(f"  ✓ {filename}")
        
        # Generate index.xml for ReaPack (dist only, published to reapack branch)
        index_xml = generate_index_xml(version)
        dist_index_path = DIST_DIR / "index.xml"
        with open(dist_index_path, "w") as f:
            f.write(index_xml)
        print("  ✓ index.xml (dist → reapack)")
        
        print()
        print(f"✓ Build complete: {DIST_DIR}")
        return 0
        
    except Exception as e:
        print(f"✗ Build failed: {e}", file=sys.stderr)
        return 1

def escape_rtf_text(text):
    """Escape backslash, braces, and non-ASCII chars for RTF."""
    result = []
    for ch in text:
        if ch == '\\':
            result.append('\\\\')
        elif ch == '{':
            result.append('\\{')
        elif ch == '}':
            result.append('\\}')
        elif ord(ch) > 127:
            result.append(f'\\u{ord(ch)}?')
        else:
            result.append(ch)
    return ''.join(result)


def markdown_to_rtf(md_text):
    """Convert simple Markdown to RTF for the ReaPack description dialog.

    Supported syntax:
      # H1        → bold paragraph (larger)
      ## H2       → bold paragraph
      **bold**    → inline bold
      [text](url) → text only (URL dropped)
      - item      → bullet item
      blank line  → paragraph break
      plain text  → paragraph
    """
    def process_inline(text):
        """Handle **bold** and [link](url) → text."""
        text = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', text)
        parts = re.split(r'\*\*(.+?)\*\*', text)
        out = []
        for i, part in enumerate(parts):
            if i % 2 == 1:
                out.append(f'\\b {escape_rtf_text(part)}\\b0 ')
            else:
                out.append(escape_rtf_text(part))
        return ''.join(out)

    lines = md_text.splitlines()
    rtf_parts = []
    prev_empty = False

    for line in lines:
        if line.startswith('# '):
            content = process_inline(line[2:].strip())
            rtf_parts.append(f'\\b\\fs26 {content}\\b0\\fs22\\par')
        elif line.startswith('## '):
            content = process_inline(line[3:].strip())
            rtf_parts.append(f'\\b {content}\\b0\\par')
        elif line.startswith('### '):
            content = process_inline(line[4:].strip())
            rtf_parts.append(f'\\b {content}\\b0\\par')
        elif line.startswith('- '):
            content = process_inline(line[2:].strip())
            rtf_parts.append(f'  - {content}\\par')
        elif line.strip() == '':
            if not prev_empty:
                rtf_parts.append('\\par')
            prev_empty = True
            continue
        else:
            content = process_inline(line.strip())
            rtf_parts.append(f'{content}\\par')
        prev_empty = False

    body = '\n'.join(rtf_parts)
    return (
        '{\\rtf1\\ansi\\deff0\n'
        '{\\fonttbl{\\f0 Helvetica;}}\n'
        '\\f0\\fs22\n'
        + body + '\n}'
    )


def parse_about_from_script():
    """Parse the @about Markdown block from ReaTC.lua and return RTF.

    Reads lines after '-- @about' until the first non-comment line.
    Strips the leading '-- ' prefix (up to 3 spaces) from each line.
    Returns None if the @about block is not found.
    """
    script_file = SRC_DIR / "Scripts" / "ReaTC" / "ReaTC.lua"
    if not script_file.exists():
        return None

    with open(script_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    about_lines = []
    in_about = False
    for line in lines:
        stripped = line.rstrip('\n')
        if re.match(r'^--\s*@about\s*$', stripped):
            in_about = True
            continue
        if in_about:
            if stripped.startswith('--'):
                # Strip leading "--" plus up to 3 spaces of indent
                content = re.sub(r'^--\s{0,3}', '', stripped)
                about_lines.append(content)
            else:
                break   # first non-comment line terminates the block

    if not about_lines:
        return None

    return markdown_to_rtf('\n'.join(about_lines))


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
    about_rtf = parse_about_from_script()
    if about_rtf is None:
        # Fallback if @about block is missing from the script
        about_rtf = (
            "{\\rtf1\\ansi\\deff0\n"
            "{\\fonttbl{\\f0 Helvetica;}}\n"
            "\\f0\\fs22\\b ReaTC\\b0\\par\n"
            "Art-Net and MIDI Timecode sender for REAPER.\\par\n"
            "Supports transport timecode or LTC audio input.\\par\n}"
        )
    
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
        <source main="main" file="Scripts/ReaTC/ReaTC.lua">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/ReaTC.lua</source>
        <source file="Scripts/ReaTC/reatc_core.lua">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_core.lua</source>
        <source file="Scripts/ReaTC/reatc_ltc.lua">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_ltc.lua</source>
        <source file="Effects/ReaTC/reatc_ltc.jsfx">https://github.com/paskateknikko/ReaTC/raw/reapack/Effects/ReaTC/reatc_ltc.jsfx</source>
        <source file="Scripts/ReaTC/reatc_outputs.lua">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_outputs.lua</source>
        <source file="Scripts/ReaTC/reatc_ui.lua">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_ui.lua</source>
        <source file="Scripts/ReaTC/reatc_udp.py">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_udp.py</source>
        <source file="Scripts/ReaTC/reatc_mtc.py">https://github.com/paskateknikko/ReaTC/raw/reapack/Scripts/ReaTC/reatc_mtc.py</source>
      </version>
    </reapack>
  </category>
</index>
'''


if __name__ == "__main__":
    sys.exit(build())
