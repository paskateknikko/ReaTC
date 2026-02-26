"""Tests for build system (build.py, verify.py)."""

import tempfile
from pathlib import Path

from build import substitute_version, read_changelog_for_version


class TestSubstituteVersion:
    """Test version placeholder substitution."""

    def test_basic_substitution(self):
        """{{VERSION}} is replaced with version string."""
        result = substitute_version("v{{VERSION}}", "1.2.3")
        assert result == "v1.2.3"

    def test_multiple_occurrences(self):
        """All occurrences are replaced."""
        result = substitute_version("{{VERSION}} and {{VERSION}}", "1.0.0")
        assert result == "1.0.0 and 1.0.0"

    def test_no_placeholder(self):
        """Content without placeholder is unchanged."""
        result = substitute_version("no placeholder here", "1.0.0")
        assert result == "no placeholder here"

    def test_dev_version(self):
        """DEV version string works."""
        result = substitute_version("@version {{VERSION}}", "DEV")
        assert result == "@version DEV"


class TestReadChangelogForVersion:
    """Test changelog extraction."""

    def test_dev_returns_development_build(self):
        """DEV version returns 'Development build'."""
        result = read_changelog_for_version("DEV")
        assert result == "Development build"

    def test_missing_version_returns_fallback(self):
        """Non-existent version returns fallback string."""
        result = read_changelog_for_version("99.99.99")
        # Either "Release 99.99.99" (no CHANGELOG) or actual fallback
        assert "99.99.99" in result
