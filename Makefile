# RepoBar Makefile — thin wrappers around Scripts/*.sh
# Run `make` or `make help` to see available targets.

# Pull version from version.env for targets that need it
include version.env
export MARKETING_VERSION
export BUILD_NUMBER

# Auto-detect Developer ID signing identity to avoid keychain prompts on rebuild.
# Override: make run APP_IDENTITY="Developer ID Application: Your Name (TEAMID)"
APP_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
export APP_IDENTITY

# GitHub repo for fork releases (override: make sign-and-release GH_REPO="org/repo")
GH_REPO ?= johnlarkin1/RepoBar

.PHONY: help build build-release test run lint format check \
        sign package release sign-and-release appcast check-release \
        clean coverage codegen stop

# ── Default ──────────────────────────────────────────────────────────
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' Makefile | \
		awk -F ':.*## ' '{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ── Core Development ────────────────────────────────────────────────
build: ## Debug build
	./Scripts/build.sh

build-release: ## Release build
	swift build -c release

test: ## Run full test suite
	./Scripts/test.sh

run: ## Build, package, and launch (main dev workflow)
	./Scripts/compile_and_run.sh

check: format lint test ## Format + lint + test (run before PRs)

# ── Code Quality ────────────────────────────────────────────────────
lint: ## SwiftLint
	./Scripts/swiftlint.sh

format: ## SwiftFormat auto-fix
	./Scripts/swiftformat.sh

# ── Release ─────────────────────────────────────────────────────────
sign: ## Sign + notarize for distribution
	./Scripts/sign-and-notarize.sh

package: ## Build release binary and create RepoBar.app bundle
	./Scripts/package_app.sh

release: ## Full release pipeline (DISABLED — use sign-and-release instead)
	@echo "ERROR: 'make release' is disabled to prevent accidental pushes to upstream (steipete/RepoBar)." >&2; \
	echo "Use 'make sign-and-release' to release to $(GH_REPO)." >&2; \
	exit 1

_guard-no-upstream: ## (internal) Block releases targeting upstream
	@if echo "$(GH_REPO)" | grep -qi 'steipete/RepoBar'; then \
		echo "ERROR: Refusing to release to upstream steipete/RepoBar. Set GH_REPO to your fork." >&2; \
		exit 1; \
	fi

sign-and-release: _guard-no-upstream sign ## Sign, notarize, tag, and create GitHub release on fork
	@TAG="v$(MARKETING_VERSION)"; \
	ZIP="RepoBar-$(MARKETING_VERSION).zip"; \
	DSYM_ZIP="RepoBar-$(MARKETING_VERSION).dSYM.zip"; \
	if [ ! -f "$$ZIP" ]; then \
		echo "ERROR: $$ZIP not found. Did sign-and-notarize.sh succeed?" >&2; \
		exit 1; \
	fi; \
	echo "Tagging $$TAG and pushing to $(GH_REPO)..."; \
	git tag -f "$$TAG"; \
	git push -f origin "$$TAG"; \
	echo "Creating GitHub release on $(GH_REPO)..."; \
	NOTES="RepoBar $(MARKETING_VERSION) (build $(BUILD_NUMBER))"; \
	if [ -f CHANGELOG.md ]; then \
		SECTION=$$(awk '/^## \[?$(MARKETING_VERSION)\]?/{found=1;next} /^## /{if(found)exit} found' CHANGELOG.md); \
		if [ -n "$$SECTION" ]; then NOTES="$$SECTION"; fi; \
	fi; \
	gh release create "$$TAG" "$$ZIP" "$$DSYM_ZIP" \
		--repo "$(GH_REPO)" \
		--title "RepoBar $(MARKETING_VERSION)" \
		--notes "$$NOTES"; \
	echo "Release $(MARKETING_VERSION) published to $(GH_REPO)."

appcast: ## Generate Sparkle appcast (requires args: make appcast ARGS="<zip> <url>")
	@if [ -z "$(ARGS)" ]; then \
		echo "Usage: make appcast ARGS=\"<path-to-zip> <download-url>\""; \
		echo "  e.g. make appcast ARGS=\"RepoBar-0.2.0-jl.1.zip https://example.com/RepoBar-0.2.0-jl.1.zip\""; \
		exit 1; \
	fi
	./Scripts/make_appcast.sh $(ARGS)

# ── Validation & Checks ────────────────────────────────────────────
check-release: ## Verify GitHub release assets
	./Scripts/check-release-assets.sh

# ── Utilities ───────────────────────────────────────────────────────
stop: ## Kill running RepoBar
	pkill -f "RepoBar.app/Contents/MacOS/RepoBar" || true

clean: ## Clean build artifacts
	swift package clean
	rm -rf .build/debug/RepoBar.app RepoBar.app

coverage: ## Run tests with coverage
	./Scripts/coverage.sh

codegen: ## Apollo GraphQL codegen
	./Scripts/apollo_codegen.sh
