# Solitaire — build, run, test and profile on the Mac from the command line, no Xcode IDE.
# Run `make help` for targets. Needs full Xcode as the active toolchain:
#   sudo xcode-select -s /Applications/Xcode.app
# The .xcodeproj is generated from project.yml by the XcodeGen pinned in .xcodegen-version
# (tools/xcodegen builds it once into a shared cache).

.DEFAULT_GOAL := build

PROJECT   := Solitaire.xcodeproj
SCHEME    := Solitaire
CONFIG    := Debug
DERIVED   := build/DerivedData
MAC_APP   := $(DERIVED)/Build/Products/$(CONFIG)/Solitaire.app
IOS_APP   := $(DERIVED)/Build/Products/$(CONFIG)-iphoneos/Solitaire.app
XCODEGEN  := tools/xcodegen
MAC_PID   := pgrep -n -f "$(CURDIR)/$(MAC_APP)/Contents/MacOS/Solitaire"
XCB       := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED)

# Signing — per developer, so read from gitignored files (or set on the command line):
#   1. SIGN_ID  (.signid)  — a named code-signing identity; manual signing. Mac only.
#   2. DEV_TEAM (.devteam) — your 10-character Apple team ID; automatic signing with your Apple
#                            Development certificate. Required for an iPhone or iPad.
#   3. (neither)           — ad-hoc (`-`): fine for your own Mac, not for a device.
SIGN_ID  ?= $(shell cat .signid 2>/dev/null)
DEV_TEAM ?= $(shell cat .devteam 2>/dev/null)
ifneq ($(strip $(SIGN_ID)),)
  MAC_SIGN := CODE_SIGN_IDENTITY="$(SIGN_ID)" CODE_SIGN_STYLE=Manual
else ifneq ($(strip $(DEV_TEAM)),)
  MAC_SIGN := CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) -allowProvisioningUpdates
else
  MAC_SIGN := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
endif
IOS_SIGN := CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) -allowProvisioningUpdates

# The iPhone or iPad to install on and profile: its name or UDID, from the gitignored .device file
# or DEVICE=… on the command line (`make devices` lists them).
DEVICE ?= $(shell cat .device 2>/dev/null)

# Profiling opens the Debug-only King→Ace position (UITestScenario.swift) with its own save file
# and settings, so it never touches your game. It profiles the Debug build — slower than Release,
# so a clean trace holds for both.
BUNDLE_ID   := com.oneoffendeavors.solitaire
PROFILE_ENV := SOLITAIRE_SCENARIO=kingToAce SOLITAIRE_SAVE_FILE=profiling SOLITAIRE_DEFAULTS_SUITE=profiling
PROFILE_ENV_JSON := {"SOLITAIRE_SCENARIO":"kingToAce","SOLITAIRE_SAVE_FILE":"profiling","SOLITAIRE_DEFAULTS_SUITE":"profiling"}
TEMPLATE ?= Animation Hitches
TIME     ?= 30s
TRACES   := build/traces
# OPEN=no records and saves the trace without opening Instruments — for unattended runs, which
# would otherwise leave Instruments (and its save prompt on quit) on the Mac's screen.
OPEN     ?= yes

.PHONY: help xcodegen generate build run logs stop test uitest devices device install profile \
        profile-mac need-device clean

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

xcodegen: ## Build the pinned XcodeGen if needed
	$(XCODEGEN) --version

generate: ## Generate the .xcodeproj from project.yml
	$(XCODEGEN) generate --quiet

build: generate ## Build the Mac app (signed per .signid / .devteam, else ad-hoc)
	$(XCB) -destination 'generic/platform=macOS' $(MAC_SIGN) build
	@echo ">> built: $(MAC_APP)"

run: build ## Build, launch the Mac app, stream its logs (stops when you quit it)
	@open "$(MAC_APP)"
	@echo ">> launched — streaming logs (stops when you quit Solitaire; Ctrl-C also works):"
	@app_pid=""; \
	for i in $$(seq 1 50); do app_pid=$$($(MAC_PID)); [ -n "$$app_pid" ] && break; sleep 0.1; done; \
	log stream --style compact --predicate 'process == "Solitaire"' & \
	log_pid=$$!; \
	trap 'kill $$log_pid 2>/dev/null' INT TERM EXIT; \
	if [ -n "$$app_pid" ]; then \
	  while kill -0 "$$app_pid" 2>/dev/null; do sleep 0.5; done; \
	  kill $$log_pid 2>/dev/null || true; \
	else \
	  wait $$log_pid; \
	fi

logs: ## Stream the running app's logs
	log stream --style compact --predicate 'process == "Solitaire"'

stop: ## Quit the running Mac app
	-killall Solitaire

test: generate ## Engine tests + the app's unit tests on the Mac
	swift test --package-path Packages/SolitaireEngine
	$(XCB) -destination 'platform=macOS' -only-testing:SolitaireTests $(MAC_SIGN) test

uitest: generate ## UI tests on the Mac — leave the Mac alone while they run
	$(XCB) -destination 'platform=macOS' -only-testing:SolitaireUITests $(MAC_SIGN) test

devices: ## List iPhones and iPads (connected devices and simulators)
	xcrun devicectl list devices

device: generate ## Build for an iPhone or iPad (needs .devteam)
	@test -n "$(strip $(DEV_TEAM))" || { echo "A device build needs your Apple team ID: echo XXXXXXXXXX > .devteam"; exit 1; }
	$(XCB) -destination 'generic/platform=iOS' $(IOS_SIGN) build
	@echo ">> built: $(IOS_APP)"

install: need-device device ## Build and install on DEVICE
	xcrun devicectl device install app --device "$(DEVICE)" "$(IOS_APP)"

# Both profile targets launch the app normally, then attach the recording to it. (Launched by
# xctrace itself, the Mac app came up without a window and outlived the recording.)
profile: install ## Record Animation Hitches on DEVICE from the King→Ace position, then open the trace
	@test "$(CONFIG)" = Debug || { echo "profiling needs CONFIG=Debug: the King→Ace position is Debug-only"; exit 1; }
	@mkdir -p $(TRACES)
	xcrun devicectl device process launch --device "$(DEVICE)" --terminate-existing \
	  --environment-variables '$(PROFILE_ENV_JSON)' $(BUNDLE_ID)
	@sleep 2
	@echo ">> recording $(TIME) on $(DEVICE) — drag the King→Ace run back and forth"
	xcrun xctrace record --template "$(TEMPLATE)" --device "$(DEVICE)" --time-limit $(TIME) \
	  --output "$(TRACES)/device-$$(date +%Y%m%d-%H%M%S).trace" --attach Solitaire
	@trace="$$(ls -td $(TRACES)/*.trace | head -1)"; \
	if [ "$(OPEN)" = no ]; then echo ">> saved: $$trace"; else open "$$trace"; fi

profile-mac: build ## The same recording on this Mac (a separate copy; your game is untouched)
	@test "$(CONFIG)" = Debug || { echo "profiling needs CONFIG=Debug: the King→Ace position is Debug-only"; exit 1; }
	@mkdir -p $(TRACES)
	open -n $(addprefix --env ,$(PROFILE_ENV)) "$(MAC_APP)"
	@sleep 2
	@echo ">> recording $(TIME) — drag the King→Ace run back and forth"
	xcrun xctrace record --template "$(TEMPLATE)" --time-limit $(TIME) \
	  --output "$(TRACES)/mac-$$(date +%Y%m%d-%H%M%S).trace" --attach $$($(MAC_PID))
	@trace="$$(ls -td $(TRACES)/*.trace | head -1)"; \
	if [ "$(OPEN)" = no ]; then echo ">> saved: $$trace"; else open "$$trace"; fi

need-device:
	@test -n "$(DEVICE)" || { echo "Which device? echo '<name or UDID>' > .device, or DEVICE=… (see make devices)"; exit 1; }

clean: ## Remove build output and the generated project
	rm -rf build $(PROJECT)
