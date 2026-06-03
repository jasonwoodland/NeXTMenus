APP_NAME := NeXTMenus
PROJECT := NeXTMenus.xcodeproj
TARGET := NeXTMenus
CONFIGURATION ?= Release
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(CONFIGURATION)/$(APP_NAME).app
DSYM_BUNDLE := $(APP_BUNDLE).dSYM

.PHONY: build run release test check-sources verify clean clean-release

build:
	swift build

run:
	swift run

release: clean-release
	xcodebuild -project $(PROJECT) -target $(TARGET) -configuration $(CONFIGURATION) build
	@echo "Built $(APP_BUNDLE)"

test:
	swift test

check-sources:
	./scripts/check-xcode-sources.py

verify: check-sources build test release

clean-release:
	rm -rf $(APP_BUNDLE) $(DSYM_BUNDLE)

clean:
	rm -rf .build $(BUILD_DIR)
