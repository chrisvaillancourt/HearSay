# Makefile for Reproducible Builds

APP_NAME := MeetingRecorder
BUNDLE_NAME := $(APP_NAME).app
CONFIG := release
BUILD_DIR := .build/arm64-apple-macosx/$(CONFIG)

.PHONY: all bootstrap build test clean lint bundle run

all: build

# Bootstrap: Check environment and fetch dependencies
bootstrap:
	@echo "Checking Swift version..."
	@swift --version
	@echo "Resolving dependencies..."
	swift package resolve

# Build: Deterministic build command
build:
	swift build -c $(CONFIG) --arch arm64

# Bundle: Create a valid macOS .app structure from the binary
bundle: build
	@echo "Bundling $(BUNDLE_NAME)..."
	@mkdir -p $(BUNDLE_NAME)/Contents/{MacOS,Resources}
	@cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE_NAME)/Contents/MacOS/
	@cp Sources/$(APP_NAME)/Info.plist $(BUNDLE_NAME)/Contents/Info.plist
	@# Run ad-hoc signing with entitlements
	@codesign --force --deep --sign - --entitlements $(APP_NAME).entitlements $(BUNDLE_NAME)
	@echo "Created $(BUNDLE_NAME)"

# Run: Build, Bundle, and Open
run: bundle
	open $(BUNDLE_NAME)

# Test: Run tests
test:
	swift test

# Clean: Remove build artifacts
clean:
	swift package clean
	rm -rf .build
	rm -rf $(BUNDLE_NAME)

# CI: The exact command run by GitHub Actions
ci: bootstrap build test
