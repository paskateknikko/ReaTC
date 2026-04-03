.PHONY: build clean verify all help watch extension docs test install

VERSION ?= DEV
ifdef v
VERSION := $(v)
endif

# Read ReaPack config (index name and category)
include build/reapack.env

help:
	@echo "ReaTC Build Commands"
	@echo ""
	@echo "  make build               - Build dist/ from src/ (VERSION=DEV by default)"
	@echo "  make build VERSION=1.3.0 - Build with specific version"
	@echo "  make build v=1.3.0       - Build with specific version (shorthand)"
	@echo "  make verify              - Verify dist/ contains all expected files"
	@echo "  make all                 - Build and verify (default)"
	@echo "  make extension           - Build C++ extension (reaper_reatc)"
	@echo "  make test                - Run Python unit tests"
	@echo "  make docs                - Generate Lua API docs (requires ldoc)"
	@echo "  make watch               - Rebuild on changes (requires watchexec)"
	@echo "  make install             - Build and copy to REAPER resource folder (macOS)"
	@echo "  make clean               - Remove dist/ and extension build"
	@echo ""

build:
	python3 build/build.py --version "$(VERSION)"

verify:
	python3 build/verify.py --version "$(VERSION)"

extension:
	cmake -S src/extension -B src/extension/build -DCMAKE_BUILD_TYPE=Release
	cmake --build src/extension/build --config Release
	@echo "✓ Built extension: src/extension/build/"

DIST_DIR = dist/$(REAPACK_INDEX_NAME)-$(VERSION)

all: build verify extension
	mkdir -p "$(DIST_DIR)/UserPlugins"
	cp src/extension/build/reaper_reatc.dylib "$(DIST_DIR)/UserPlugins/"
	@echo "✓ Complete: $(DIST_DIR)/"

ifeq ($(OS),Windows_NT)
REAPER_RESOURCE ?= $(APPDATA)/REAPER
else
REAPER_RESOURCE ?= $(HOME)/Library/Application Support/REAPER
endif

install: all
	cp -R "$(DIST_DIR)/Scripts/" "$(REAPER_RESOURCE)/Scripts/"
	cp -R "$(DIST_DIR)/Effects/" "$(REAPER_RESOURCE)/Effects/"
	cp -R "$(DIST_DIR)/UserPlugins/" "$(REAPER_RESOURCE)/UserPlugins/"
	@echo "✓ Installed to $(REAPER_RESOURCE)"
	@echo "  Restart REAPER to load the extension"

test:
	python3 -m pytest tests/ -v

docs:
	ldoc .

clean:
	rm -rf dist/ src/extension/build/
	@echo "✓ Cleaned dist/ and extension build"

watch:
	watchexec -r -w src -w build -e py,lua,md -- make VERSION=$(VERSION)

.DEFAULT_GOAL := all
