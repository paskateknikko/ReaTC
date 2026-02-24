.PHONY: build clean verify all help watch extension

VERSION ?= DEV
ifdef v
VERSION := $(v)
endif

help:
	@echo "ReaTC Build Commands"
	@echo ""
	@echo "  make build               - Build dist/ from src/ (VERSION=DEV by default)"
	@echo "  make build VERSION=1.3.0 - Build with specific version"
	@echo "  make build v=1.3.0       - Build with specific version (shorthand)"
	@echo "  make verify              - Verify dist/ contains all expected files"
	@echo "  make all                 - Build and verify (default)"
	@echo "  make extension           - Build C++ extension (reaper_reatc)"
	@echo "  make watch               - Rebuild on changes (requires watchexec)"
	@echo "  make clean               - Remove dist/ and extension build"
	@echo ""

build:
	python3 build/build.py --version "$(VERSION)"

verify:
	python3 build/verify.py --version "$(VERSION)"

all: build verify extension

extension:
	cmake -S src/extension -B dist/extension-build
	cmake --build dist/extension-build
	@echo "✓ Built extension"

clean:
	rm -rf dist/ dist/extension-build/
	@echo "✓ Cleaned dist/ and extension build"

watch:
	watchexec -r -w src -w build -e py,lua,md -- make VERSION=$(VERSION)

.DEFAULT_GOAL := all
