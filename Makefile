# Toret — everyday commands.
#
#   make run         build and launch on the simulator   (SIM, LOCATION)
#   make device      build, sign and install on a connected iPhone
#   make test        run the unit tests on the simulator
#   make generate    regenerate Toret.xcodeproj from project.yml
#   make archive     a Release archive for App Store Connect (nothing is uploaded)
#   make testflight  archive, then upload to TestFlight (UPLOAD=NO: only write the .ipa)
#   make clean       remove build/
#
# Simulator builds go to build/sim, device builds to build/device, archives to
# build/testflight, so none of them collides with another.

PROJECT   := Toret.xcodeproj
SCHEME    := Toret
BUNDLE_ID := br.tec.nuance.toret
BUILD_DIR := build
# Xcode 26 ships the simulator window as DeviceHub.app, not Simulator.app.
DEVICE_HUB := $(shell xcode-select -p)/../Applications/DeviceHub.app

# Per-machine settings that must not be committed (App Store Connect API key ids).
-include local.mk

# Simulator target (name or UDID) and the spot in Turin the catalogue surrounds.
SIM      ?= iPhone 17 Pro
LOCATION ?= 45.06687,7.68316

.PHONY: help run device test generate clean archive testflight

help:
	@sed -n '2,10p' Makefile | sed 's/^# \{0,1\}//'

generate:
	@xcodegen generate --quiet

run: generate
	@xcrun simctl boot "$(SIM)" 2>/dev/null || true
	@open "$(DEVICE_HUB)" 2>/dev/null || open -a Simulator 2>/dev/null || echo "note: no simulator window available; running headless"
	@xcrun simctl bootstatus "$(SIM)" -b >/dev/null
	@xcrun simctl location "$(SIM)" set $(LOCATION)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=iOS Simulator,name=$(SIM)' \
		-derivedDataPath $(BUILD_DIR)/sim -quiet build
	xcrun simctl install "$(SIM)" $(BUILD_DIR)/sim/Build/Products/Debug-iphonesimulator/Toret.app
	@xcrun simctl privacy "$(SIM)" grant location-always $(BUNDLE_ID) 2>/dev/null || true
	xcrun simctl launch --terminate-running-process "$(SIM)" $(BUNDLE_ID)

# Builds, signs and installs the app on a connected iPhone, then launches it.
#   make device                        first connected physical iPhone
#   make device DEVICE=<udid>          a specific device
#   make device TEAM=<team id>         another signing team
# Signing outcomes (verified 2026-10-10):
#   - Personal Team (M79D47H32S) cannot provision the App Groups capability the app and its widgets
#     declare ("Provisioning profile ... doesn't match the entitlements file's value for the
#     com.apple.security.application-groups entitlement"). Use GROUPS=NO to build without the group:
#     the app runs and remembers things, but the widgets cannot see its position and fall back to
#     the centre of Turin (Store.defaults falls back to the target's own defaults).
#   - Nuance (TEAM=N859AT5MST) signs the group, but the iPhone must first be registered in that
#     account's devices ("Device 'iPhone' isn't registered in your developer account").
#   make device GROUPS=NO              Personal Team, no app group
TEAM   ?= M79D47H32S
DEVICE ?=
GROUPS ?= YES
signing_extra = $(if $(filter NO,$(GROUPS)),CODE_SIGN_ENTITLEMENTS=$(CURDIR)/tools/no-app-group.entitlements,)
device: generate
	@set -e; \
	udid="$(DEVICE)"; \
	if [ -z "$$udid" ]; then \
		json=$$(mktemp); \
		xcrun devicectl list devices --json-output "$$json" >/dev/null 2>&1; \
		udid=$$(python3 -I -c 'import json,sys; \
d=json.load(open(sys.argv[1]))["result"]["devices"]; \
print(next((x["hardwareProperties"]["udid"] for x in d \
if x["hardwareProperties"].get("reality")=="physical" \
and x["hardwareProperties"].get("platform")=="iOS" \
and x["connectionProperties"].get("pairingState")=="paired" \
and x["connectionProperties"].get("tunnelState")!="unavailable"), ""))' "$$json"); \
		rm -f "$$json"; \
	fi; \
	if [ -z "$$udid" ]; then \
		echo "no physical device found: connect and unlock the iPhone (or pass DEVICE=<udid>; see: xcrun devicectl list devices)"; \
		exit 1; \
	fi; \
	echo "==> device $$udid, team $(TEAM)"; \
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-destination "platform=iOS,id=$$udid" -derivedDataPath $(BUILD_DIR)/device \
		CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(TEAM) $(signing_extra) \
		-allowProvisioningUpdates -quiet build \
		|| { echo "signing failed: see the notes above this target in the Makefile (GROUPS=NO, or TEAM=N859AT5MST once the iPhone is registered)"; exit 1; }; \
	xcrun devicectl device install app --device "$$udid" \
		$(BUILD_DIR)/device/Build/Products/$(CONFIG)-iphoneos/Toret.app | grep -E "installed|bundleID"; \
	xcrun devicectl device process launch --device "$$udid" --terminate-existing $(BUNDLE_ID) >/dev/null 2>&1 \
		&& echo "launched on $$udid" \
		|| echo "installed, but iOS refused to launch it: trust the developer profile on the phone (Settings > General > VPN & Device Management), then open the app"

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIM)' -derivedDataPath $(BUILD_DIR)/sim test

clean:
	rm -rf $(BUILD_DIR)

# TestFlight, on the Nuance App Store Connect team.
#   make archive       a Release archive in build/testflight (nothing is uploaded)
#   make testflight    archive, then upload it to App Store Connect for TestFlight
#   make testflight UPLOAD=NO   archive, then only write the .ipa to
#                      build/testflight/export: a rehearsal, nothing leaves the Mac
# Needs ONE of:
#   - the team's Apple ID signed in to Xcode (Settings > Accounts), Admin or App Manager role, or
#   - the App Store Connect API key below, with AuthKey_<key id>.p8 in
#     ~/.appstoreconnect/private_keys/ (never in the repository).
# The app record must already exist in App Store Connect with the bundle identifier
# $(BUNDLE_ID). The team is ASC_TEAM here and teamID in tools/testflight/ExportOptions*.plist:
# change both together. Every upload needs a new build number: BUILD_NUMBER defaults to
# the date and time.
ASC_TEAM   ?= N859AT5MST
# ASC_KEY_ID and ASC_ISSUER identify the API key. They live in local.mk (untracked, see
# local.mk.example); without them the upload falls back to the Apple ID signed in to Xcode.
BUILD_NUMBER ?= $(shell date +%Y%m%d%H%M)
# The archive itself is left unsigned and the export step signs it for distribution:
# signing the archive would need a development profile, which needs a registered device
# on the team. ARCHIVE_SIGNED=YES signs the archive too.
ARCHIVE_SIGNED ?= NO
UPLOAD ?= YES
ARCHIVE := $(BUILD_DIR)/testflight/Toret.xcarchive
asc_auth = $(if $(ASC_KEY_ID),-authenticationKeyPath $(HOME)/.appstoreconnect/private_keys/AuthKey_$(ASC_KEY_ID).p8 -authenticationKeyID $(ASC_KEY_ID) -authenticationKeyIssuerID $(ASC_ISSUER),)

archive: generate
	@xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination "generic/platform=iOS" -archivePath $(ARCHIVE) -derivedDataPath $(BUILD_DIR)/testflight/dd \
		CODE_SIGNING_ALLOWED=$(ARCHIVE_SIGNED) CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(ASC_TEAM) \
		CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		-allowProvisioningUpdates $(asc_auth) -quiet
	@app=$(ARCHIVE)/Products/Applications/Toret.app; \
		[ -d "$$app" ] || { echo "no archive was produced"; exit 1; }; \
		echo "archived $$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' $$app/Info.plist) $$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $$app/Info.plist) ($$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' $$app/Info.plist)), $$(du -sh $$app | cut -f1)"

testflight: archive
	@xcodebuild -exportArchive -archivePath $(ARCHIVE) -exportPath $(BUILD_DIR)/testflight/export \
		-exportOptionsPlist tools/testflight/$(if $(filter NO,$(UPLOAD)),ExportOptions.local.plist,ExportOptions.plist) \
		-allowProvisioningUpdates $(asc_auth) DEVELOPMENT_TEAM=$(ASC_TEAM) 2>&1 \
		| grep -E "error|rror:|Upload|upload|EXPORT|Progress 100|succeeded" | tail -15
	@if [ "$(UPLOAD)" = NO ]; then ls $(BUILD_DIR)/testflight/export/*.ipa 2>/dev/null | sed 's/^/not uploaded; ipa: /'; fi
