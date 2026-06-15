# IN-meetings build system  (macOS menu-bar app)
# Usage: make help

# --- Configuration ---
SCHEME          := INMeetings-App
APP_NAME        := INMeetings.app
PROC_NAME       := INMeetings
CONFIGURATION   := Debug
DERIVED_DATA    := ./DerivedData
APP_DIR         := Apps/INMeetings
PROJECT         := $(APP_DIR)/INMeetings.xcodeproj
PROJECT_YML     := $(APP_DIR)/project.yml
PROJECT_PBXPROJ := $(PROJECT)/project.pbxproj
APP_PRODUCT     := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/$(APP_NAME)

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
	@printf "$(GREEN)IN-meetings Build System$(NC)\n\n"
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

.PHONY: verify-mac
verify-mac: build-mac ## Build + launch + confirm the menu-bar process is alive
	@pkill -x "$(PROC_NAME)" 2>/dev/null || true
	@printf "$(GREEN)[verify]$(NC) Launching $(APP_NAME)...\n"
	@open "$(APP_PRODUCT)"
	@sleep 3
	@if pgrep -x "$(PROC_NAME)" >/dev/null 2>&1; then \
		printf "$(GREEN)[verify]$(NC) $(PROC_NAME) is running (PID $$(pgrep -x $(PROC_NAME))).\n"; \
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
