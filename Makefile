.PHONY: build clean verify all help watch

help:
	@echo "ReaTC Build Commands"
	@echo ""
	@echo "  make build       - Build dist/ from src/ (substitute version, include modules, generate index.xml)"
	@echo "  make verify      - Verify dist/ contains all expected files with correct versions"
	@echo "  make all         - Build and verify (default)"
	@echo "  make watch       - Rebuild on changes (requires watchexec)"
	@echo "  make clean       - Remove dist/ directory"
	@echo ""

build:
	python3 build/build.py

verify:
	python3 build/verify.py

all: build verify

clean:
	rm -rf dist/
	@echo "✓ Cleaned dist/"

watch:
	watchexec -r -w src -w build -w version.txt -e py,lua,txt,md -- make

.DEFAULT_GOAL := all
