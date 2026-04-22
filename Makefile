APP_NAME = WorkLogger
BUNDLE_ID = com.worklogger.app
APP_DIR = /Applications
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_DIR)/$(APP_NAME).app
BINARY = $(BUILD_DIR)/$(APP_NAME)
CERT_NAME = WorkLogger Dev
VENV = .build/venv
VENV_PYTHON = $(VENV)/bin/python3

.PHONY: build app install clean setup-cert test reset-permissions venv

## Create build-time virtualenv with all Python dependencies
venv: $(VENV_PYTHON)
$(VENV_PYTHON):
	python3 -m venv $(VENV)
	$(VENV_PYTHON) -m pip install --upgrade pip --quiet
	$(VENV_PYTHON) -m pip install openpyxl pytest --quiet

## Run compliance tests
test: venv
	SDKROOT=$(shell xcrun --show-sdk-path) swift test -Xcxx -I$(shell xcrun --show-sdk-path)/usr/include/c++/v1
	$(VENV_PYTHON) -m pytest test_report/test_report.py -v
## Build release binary (tests must pass first)
build: test
	swift build -c release

## Create WorkLogger.app on your Desktop
app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp config.json "$(APP_BUNDLE)/Contents/Resources/config.json"
	cp test_report/report.py "$(APP_BUNDLE)/Contents/Resources/report.py"
	@echo "🐍 Creating bundled Python environment..."
	python3 -m venv "$(APP_BUNDLE)/Contents/Resources/venv"
	"$(APP_BUNDLE)/Contents/Resources/venv/bin/python3" -m pip install --upgrade pip --quiet
	"$(APP_BUNDLE)/Contents/Resources/venv/bin/python3" -m pip install openpyxl --quiet
	@echo "🎨 Generating icon..."
	@swift Scripts/generate-icon.swift
	@cp /tmp/WorkLogger.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '<plist version="1.0"><dict>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>CFBundleName</key><string>$(APP_NAME)</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>CFBundleExecutable</key><string>$(APP_NAME)</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>CFBundleVersion</key><string>1.0</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>CFBundleIconFile</key><string>AppIcon</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>LSMinimumSystemVersion</key><string>12.0</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>NSPrincipalClass</key><string>NSApplication</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>LSUIElement</key><true/>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>NSAppleScriptEnabled</key><true/>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>NSAppleEventsUsageDescription</key><string>WorkLogger uses AppleScript to read the active Safari tab and URL.</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '  <key>NSScreenCaptureUsageDescription</key><string>WorkLogger reads window titles to track which project you are working in.</string>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@echo '</dict></plist>' >> "$(APP_BUNDLE)/Contents/Info.plist"
	@if security find-identity -v -p codesigning | grep -q "$(CERT_NAME)"; then \
		codesign --force --sign "$(CERT_NAME)" --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"; \
		echo "🔏 Signed with persistent certificate '$(CERT_NAME)'"; \
	else \
		codesign --force --sign - --identifier "$(BUNDLE_ID)" "$(APP_BUNDLE)"; \
	fi
	@touch "$(APP_BUNDLE)"
	@/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(APP_BUNDLE)"
	@killall Dock 2>/dev/null || true
	@echo "✅ Built $(APP_BUNDLE)"
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@tccutil reset ScreenCapture $(BUNDLE_ID) 2>/dev/null || true
	@echo "🚀 Launching WorkLogger..."
	@open "$(APP_BUNDLE)"

## Install binary to /usr/local/bin for terminal use
install: build
	cp "$(BINARY)" /usr/local/bin/$(APP_NAME)
	@echo "✅ Installed to /usr/local/bin/$(APP_NAME)"

clean:
	swift package clean
	rm -rf $(VENV)

## Create a persistent self-signed certificate for stable code signing
setup-cert:
	@bash Scripts/setup-certificate.sh

## Reset TCC permissions for WorkLogger (Accessibility + Screen Recording)
reset-permissions:
	@echo "🔄 Resetting TCC permissions for $(BUNDLE_ID)..."
	@tccutil reset Accessibility $(BUNDLE_ID) 2>/dev/null || true
	@tccutil reset ScreenCapture $(BUNDLE_ID) 2>/dev/null || true
	@echo "⚠️  Re-grant permissions: System Settings → Privacy & Security"
	@echo "   1. Accessibility → enable WorkLogger"
	@echo "   2. Screen Recording → enable WorkLogger"

## Run build and permission validation tests
validate:
	@bash Scripts/test-build.sh
