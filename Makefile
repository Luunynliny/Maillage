# Local shortcuts for what CI runs, so a red check can be reproduced with one command instead of
# a scroll through a workflow file. `make check` is the whole pipeline.
#
# `swift format` ships with the toolchain (Swift 5.9+), so `format` and `format-lint` need no
# install. `lint` needs SwiftLint: `brew install swiftlint`.

.DEFAULT_GOAL := help
.PHONY: help check format format-lint lint test build parity clean

help: ## Show this help
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk -F':.*?## ' '{ printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2 }'

check: format-lint lint parity test ## Everything CI runs, in CI's order

format: ## Rewrite sources to match .swift-format
	swift format --recursive --in-place Sources Tests

format-lint: ## Fail if anything is misformatted (CI's read-only version of `format`)
	swift format lint --recursive --strict Sources Tests

lint: ## SwiftLint, warnings included
	swiftlint lint --quiet --strict

test: ## Run the test suite
	swift test

build: ## Compile the app bundle the way the Maillage scheme does
	xcodebuild build -project maillage.xcodeproj -scheme Maillage \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO | \
		xcbeautify 2>/dev/null || \
	xcodebuild build -project maillage.xcodeproj -scheme Maillage \
		-destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO

parity: ## Check Package.swift and maillage.xcodeproj still agree
	./Scripts/check-build-parity.sh

clean: ## Remove build products
	rm -rf .build
	rm -rf ~/Library/Developer/Xcode/DerivedData/maillage-*
