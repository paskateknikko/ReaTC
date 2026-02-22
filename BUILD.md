# Building ReaTC

## Quick Start

```bash
# First time: set up development scripts
python3 setup.py

# Build and verify
make          # or: make build verify
```

## Build System

The project uses a **simple Python-based build** with a `Makefile` wrapper for convenience.

### What the build does:

1. **Version substitution** — reads `version.txt` and replaces `{{VERSION}}` placeholders in source files
2. **File copying** — copies all source files to `dist/Scripts/ReaTC/`
3. **Metadata** — copies `LICENSE`, `README.md` to `dist/`
4. **ReaPack index** — generates `dist/index.xml` for package distribution

### Directory structure after build:

```
dist/
├── LICENSE
├── README.md
├── index.xml                    ← for ReaPack
└── Scripts/
    └── ReaTC/
        ├── ReaTC.lua            ← Version substituted
        ├── reatc_udp.py         ← Version substituted
        └── reatc_mtc.py         ← Version substituted
```

## Available Commands

```bash
make              # Build and verify (default)
make build        # Build only (version substitution + file copying)
make verify       # Verify all files are present with correct versions
make clean        # Remove dist/ directory
make watch        # Rebuild on changes (requires watchexec)
make help         # Show this help
```

## Auto Rebuild on Changes

Use `make watch` to automatically rebuild when source files change.

Install `watchexec`:

```bash
# macOS
brew install watchexec

# Windows (choose one)
choco install watchexec
scoop install watchexec
```

Then run:

```bash
make watch
```

## Version Management

**Single source of truth:** `version.txt`

Don't edit version strings in source files. Instead:

1. Edit `version.txt` with the new version (e.g., `"2.1.0"`)
2. Run `make build`
3. The build system automatically substitutes `{{VERSION}}` in all files

## Development Workflow

1. **Edit source files** in `src/Scripts/ReaTC/`
2. **Run `make build`** to generate `dist/`
3. **Test** by loading `dist/Scripts/ReaTC/ReaTC.lua` in REAPER
4. **Commit** `src/` and `version.txt` changes to git (never commit `dist/`)

## Release Workflow

Follow these steps to create a new release:

### 1. Update Version & Changelog

```bash
# Edit version.txt with new semantic version
echo "0.0.2" > version.txt

# Edit CHANGELOG.md and add release notes under ## [0.0.2]
# Include: Features, Bug Fixes, Requirements changes, etc.
```

### 2. Build & Verify Locally

```bash
python3 setup.py
make build
make verify

# Check dist/index.xml has correct version, author, and URLs
cat dist/index.xml
```

### 3. Commit Changes

```bash
git add version.txt CHANGELOG.md src/
git commit -m "Release v0.0.2"
```

### 4. Create Annotated Git Tag

```bash
# Standard release
git tag -a v0.0.2 -m "ReaTC v0.0.2: Brief release description"

# Pre-release (beta/rc)
git tag -a v0.0.2-beta.1 -m "ReaTC v0.0.2-beta.1: Testing new features"
```

### 5. Push to GitHub

```bash
# Push commits
git push origin main

# Push tag(s) - triggers GitHub Actions release workflow
git push origin v0.0.2
```

### 6. GitHub Actions Automatically

- ✅ Detects the `v*` tag
- ✅ Builds the package with `make build`
- ✅ Generates `dist/index.xml` with all source files
- ✅ Creates Release asset: `ReaTC-0.0.2.zip`
- ✅ Extracts release notes from CHANGELOG.md
- ✅ Creates GitHub Release with artifact attached
- ✅ **Users can now install via ReaPack**

### Release Verification

1. Check GitHub repository "Releases" tab for new release
2. Verify `ReaTC-*.zip` artifact is attached
3. In REAPER: Extensions > ReaPack > Manage repositories
4. Repositories should reflect the new version available

## CI/CD Integration

For GitHub Actions (example):

```bash
# Install dependencies
python3 setup.py

# Build
make build

# The dist/ folder is ready for release
```

## Troubleshooting

**Build fails with "permission denied":**
```bash
python3 setup.py
```

**dist/ directory missing after build:**
- Check `version.txt` is readable
- Ensure `src/Scripts/ReaTC/` contains `.lua` and `.py` files
- Run `python3 build/build.py` for detailed error messages

**Version not substituted:**
- Run `make verify` to check all files
- Check that placeholder is exactly `{{VERSION}}` (not `{VERSION}` or `{{ VERSION }}`)
