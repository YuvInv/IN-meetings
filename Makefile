# INV Meetings build system  (macOS menu-bar app)
# Usage: make help

# --- Configuration ---
SCHEME          := INMeetings-App
APP_NAME        := INV Meetings.app
PROC_NAME       := INV Meetings
CONFIGURATION   := Debug
DERIVED_DATA    := ./DerivedData
APP_DIR         := Apps/INMeetings
PROJECT         := $(APP_DIR)/INMeetings.xcodeproj
PROJECT_YML     := $(APP_DIR)/project.yml
PROJECT_PBXPROJ := $(PROJECT)/project.pbxproj
APP_PRODUCT     := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)

# Google Picker browser API key, injected into the build (never committed). Prefer an env var (CI passes
# the GOOGLE_PICKER_API_KEY secret), else read the gitignored local file. Empty ⇒ the in-app Drive folder
# picker shows a "not configured" setup panel instead of a broken web view.
PICKER_KEY      := $(or $(GOOGLE_PICKER_API_KEY),$(shell cat .secrets/picker_api_key.txt 2>/dev/null))

# Colors
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

# --- Auto-xcodegen: (re)generate the .xcodeproj when project.yml is newer/missing ---
$(PROJECT_PBXPROJ): $(PROJECT_YML)
	@printf "$(YELLOW)[xcodegen]$(NC) project.yml changed, regenerating...\n"
	@cd $(APP_DIR) && xcodegen generate
	@printf "$(GREEN)[xcodegen]$(NC) Project regenerated\n"

.PHONY: help
help: ## Show all targets
	@printf "$(GREEN)INV Meetings Build System$(NC)\n\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-12s$(NC) %s\n", $$1, $$2}'

.PHONY: gen
gen: ## Force xcodegen regeneration
	@printf "$(YELLOW)[xcodegen]$(NC) Regenerating project...\n"
	@cd $(APP_DIR) && xcodegen generate
	@printf "$(GREEN)[xcodegen]$(NC) Done\n"

.PHONY: build-mac
build-mac: $(PROJECT_PBXPROJ) ## Build the macOS app
	@printf "$(GREEN)[build]$(NC) Building $(APP_NAME)...\n"
	@set -o pipefail; xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(DERIVED_DATA) \
		-allowProvisioningUpdates \
		GOOGLE_PICKER_API_KEY="$(PICKER_KEY)" \
		build 2>&1 | tail -25
	@if [ ! -d "$(APP_PRODUCT)" ]; then \
		printf "$(RED)[build]$(NC) FAILED: $(APP_NAME) not found. Try 'make gen'.\n"; \
		exit 1; \
	fi
	@printf "$(GREEN)[build]$(NC) Built: $(APP_PRODUCT)\n"

.PHONY: run-mac
run-mac: ## Launch the app (builds first if missing)
	@if [ ! -d "$(APP_PRODUCT)" ]; then $(MAKE) build-mac; fi
	@printf "$(GREEN)[run]$(NC) Launching $(APP_NAME)...\n"
	@open "$(APP_PRODUCT)"

RELEASE_PRODUCT := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME)

.PHONY: reset-test-data
reset-test-data: ## Reset per-user state (TCC/prefs/data) for a fresh onboarding test (KEEP_MODEL=1 by default)
	@bash scripts/reset-app-data.sh

.PHONY: dmg
dmg: ## Build a LOCAL UNSIGNED Release .dmg for install/onboarding testing (NOT notarized)
	@$(MAKE) gen >/dev/null   # regen so the project matches the current branch's files (esp. on feature branches)
	@printf "$(GREEN)[dmg]$(NC) Building Release (a Debug build's debug-dylib won't run from /Applications)...\n"
	@set -o pipefail; xcodebuild -project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination 'platform=macOS' \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-allowProvisioningUpdates \
		GOOGLE_PICKER_API_KEY="$(PICKER_KEY)" \
		build 2>&1 | tail -8
	@if [ ! -d "$(RELEASE_PRODUCT)" ]; then \
		printf "$(RED)[dmg]$(NC) FAILED: Release app not found. Try 'make gen'.\n"; exit 1; \
	fi
	@bash scripts/make-dmg.sh "$(RELEASE_PRODUCT)"
	@printf "$(YELLOW)[dmg]$(NC) Open it, drag INV Meetings to Applications, then launch from /Applications.\n"

.PHONY: release
release: ## Cut a release: bump version, tag, push → triggers CI. Usage: make release VERSION=0.2.0 (run from main)
	@if [ -z "$(VERSION)" ]; then printf "$(RED)[release]$(NC) Set VERSION, e.g. make release VERSION=0.2.0\n"; exit 1; fi
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { printf "$(RED)[release]$(NC) VERSION must be x.y.z (got '$(VERSION)')\n"; exit 1; }
	@if [ -n "$$(git status --porcelain)" ]; then printf "$(RED)[release]$(NC) Working tree not clean — commit or stash first.\n"; exit 1; fi
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	 if [ "$$BRANCH" != "main" ]; then printf "$(RED)[release]$(NC) Releases must be cut from 'main' (you're on '$$BRANCH'). Merge your work to main first.\n"; exit 1; fi
	@git fetch origin main --quiet
	@if [ -n "$$(git rev-list HEAD...origin/main)" ]; then printf "$(RED)[release]$(NC) Local main and origin/main have diverged — pull/push so they match, then release.\n"; exit 1; fi
	@if git rev-parse "v$(VERSION)" >/dev/null 2>&1; then printf "$(RED)[release]$(NC) Tag v$(VERSION) already exists.\n"; exit 1; fi
	@printf "$(GREEN)[release]$(NC) Bumping MARKETING_VERSION → $(VERSION)...\n"
	@sed -i '' -E 's/MARKETING_VERSION: ".*"/MARKETING_VERSION: "$(VERSION)"/' $(PROJECT_YML)
	@git add $(PROJECT_YML)
	@git commit -m "chore(release): v$(VERSION)" >/dev/null
	@git tag "v$(VERSION)"
	@printf "$(YELLOW)[release]$(NC) Pushing commit + tag v$(VERSION) (the tag triggers the GitHub release workflow)...\n"
	@git push origin HEAD
	@git push origin "v$(VERSION)"
	@printf "$(GREEN)[release]$(NC) Done — watch Actions → Release. (Build number is the CI run number.)\n"

.PHONY: verify-mac
verify-mac: build-mac ## Build + launch + confirm the menu-bar process is alive
	@pkill -x "$(PROC_NAME)" 2>/dev/null || true
	@printf "$(GREEN)[verify]$(NC) Launching $(APP_NAME)...\n"
	@open "$(APP_PRODUCT)"
	@sleep 3
	@if pgrep -x "$(PROC_NAME)" >/dev/null 2>&1; then \
		printf "$(GREEN)[verify]$(NC) $(PROC_NAME) is running (PID $$(pgrep -x '$(PROC_NAME)')).\n"; \
		printf "$(GREEN)[verify]$(NC) Look for the waveform icon in the menu bar (no Dock icon = LSUIElement OK).\n"; \
	else \
		printf "$(RED)[verify]$(NC) $(PROC_NAME) is NOT running — likely crashed on launch.\n"; \
		printf "$(YELLOW)[verify]$(NC) Recent logs:\n"; \
		log show --last 30s --predicate 'process == "$(PROC_NAME)"' --style compact 2>/dev/null | tail -20; \
		exit 1; \
	fi

.PHONY: test
test: ## Run Swift package tests (INMeetingsCore)
	@printf "$(GREEN)[test]$(NC) Running core tests...\n"
	@swift test

.PHONY: clean
clean: ## Remove DerivedData + the generated .xcodeproj
	@printf "$(YELLOW)[clean]$(NC) Removing $(DERIVED_DATA) and $(PROJECT)...\n"
	@rm -rf $(DERIVED_DATA) $(PROJECT)
	@printf "$(GREEN)[clean]$(NC) Done\n"

.PHONY: info
info: ## Show build config
	@printf "$(GREEN)Build Configuration$(NC)\n"
	@printf "  Scheme:   %s\n" "$(SCHEME)"
	@printf "  App:      %s\n" "$(APP_NAME)"
	@printf "  Product:  %s\n" "$(APP_PRODUCT)"
	@printf "  Project:  %s\n" "$(PROJECT)"
