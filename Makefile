# Local shortcuts for what CI runs, so a red check can be reproduced with one command instead of
# a scroll through a workflow file. `make check` is the whole pipeline.
#
# `swift format` ships with the toolchain (Swift 5.9+), so `format` and `format-lint` need no
# install. `lint` needs SwiftLint: `brew install swiftlint`. The release targets need the Node
# tooling: `npm ci`.

.DEFAULT_GOAL := help
.PHONY: help check format format-lint lint test build dmg commits release-dry parity clean

# The version stamped into a local build, so it is never mistaken for a released one. Real versions
# come from semantic-release and are never typed anywhere.
DEV_VERSION ?= 0.0.0-dev

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

build: ## Build the shippable app bundle into dist/ (the same command CI's package stage runs)
	./Scripts/build-app.sh $(DEV_VERSION)

dmg: build ## Build dist/Maillage-$(DEV_VERSION).dmg, exactly as a release would
	./Scripts/make-dmg.sh dist/Maillage.app $(DEV_VERSION)

commits: ## Lint this branch's commit messages against Conventional Commits
	npx --no-install commitlint --from origin/main --to HEAD

release-dry: ## Show the version and release notes a merge to main would produce (publishes nothing)
	GITHUB_TOKEN=$${GITHUB_TOKEN:-$$(gh auth token)} \
		npx --no-install semantic-release --dry-run --no-ci

parity: ## Check Package.swift, maillage.xcodeproj and App/Info.plist still agree
	./Scripts/check-build-parity.sh

clean: ## Remove build products
	rm -rf .build build dist
	rm -rf ~/Library/Developer/Xcode/DerivedData/maillage-*
