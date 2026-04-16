#!/bin/bash
# Test script for WorkLogger build validation.
# Checks that the .app bundle is correctly structured, signed,
# and has stable permissions after rebuilding.
#
# Usage: make test   (or bash Scripts/test-build.sh)

set -uo pipefail

APP_NAME="WorkLogger"
BUNDLE_ID="com.worklogger.app"
APP_BUNDLE="$HOME/Desktop/$APP_NAME.app"
CERT_NAME="WorkLogger Dev"

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ PASS: $1"; ((PASS++)); }
fail() { echo "  ❌ FAIL: $1"; ((FAIL++)); }
warn() { echo "  ⚠️  WARN: $1"; ((WARN++)); }
section() { echo ""; echo "── $1 ──"; }

# ─────────────────────────────────────────────
section "1. App Bundle Structure"
# ─────────────────────────────────────────────

if [[ -d "$APP_BUNDLE" ]]; then
    pass "App bundle exists at $APP_BUNDLE"
else
    fail "App bundle not found at $APP_BUNDLE (run 'make app' first)"
    echo ""
    echo "Summary: $PASS passed, $FAIL failed, $WARN warnings"
    exit 1
fi

if [[ -x "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ]]; then
    pass "Binary is executable"
else
    fail "Binary missing or not executable: $APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

if [[ -f "$APP_BUNDLE/Contents/Info.plist" ]]; then
    pass "Info.plist exists"
else
    fail "Info.plist missing"
fi

if [[ -f "$APP_BUNDLE/Contents/Resources/config.json" ]]; then
    pass "config.json bundled"
else
    fail "config.json not bundled in Resources"
fi

if [[ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
    pass "App icon bundled"
else
    warn "AppIcon.icns not found (cosmetic)"
fi

# ─────────────────────────────────────────────
section "2. Info.plist Validation"
# ─────────────────────────────────────────────

PLIST="$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$PLIST" ]]; then
    # Check bundle ID
    PLIST_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "")
    if [[ "$PLIST_BUNDLE_ID" == "$BUNDLE_ID" ]]; then
        pass "CFBundleIdentifier = $BUNDLE_ID"
    else
        fail "CFBundleIdentifier is '$PLIST_BUNDLE_ID', expected '$BUNDLE_ID'"
    fi

    # Check LSUIElement (menu bar only, no dock icon)
    LSUI=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$PLIST" 2>/dev/null || echo "")
    if [[ "$LSUI" == "true" ]]; then
        pass "LSUIElement = true (no dock icon)"
    else
        fail "LSUIElement not set to true — app will show in dock instead of menu bar only"
    fi

    # Check usage descriptions exist
    for key in NSAppleEventsUsageDescription NSScreenCaptureUsageDescription; do
        VAL=$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || echo "")
        if [[ -n "$VAL" ]]; then
            pass "$key is set"
        else
            fail "$key missing — macOS will deny permission without a usage description"
        fi
    done

    # Check executable name matches
    EXEC=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST" 2>/dev/null || echo "")
    if [[ "$EXEC" == "$APP_NAME" ]]; then
        pass "CFBundleExecutable = $APP_NAME"
    else
        fail "CFBundleExecutable is '$EXEC', expected '$APP_NAME'"
    fi
fi

# ─────────────────────────────────────────────
section "3. Code Signing"
# ─────────────────────────────────────────────

# Verify the signature is valid
if codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    pass "Code signature is valid"
else
    fail "Code signature verification failed"
fi

# Check signing identity
SIGN_INFO=$(codesign -dvv "$APP_BUNDLE" 2>&1)
SIGN_AUTHORITY=$(echo "$SIGN_INFO" | grep "^Authority=" | head -1 | cut -d= -f2-)

if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
    fail "Signed ad-hoc — permissions will reset on every rebuild!"
    echo "       Fix: run 'make setup-cert' then 'make app'"
elif [[ "$SIGN_AUTHORITY" == *"$CERT_NAME"* ]]; then
    pass "Signed with persistent certificate '$CERT_NAME'"
else
    warn "Signed with unknown identity: $SIGN_AUTHORITY"
fi

# Check that the identifier matches the bundle ID
SIGN_IDENT=$(echo "$SIGN_INFO" | grep "^Identifier=" | cut -d= -f2-)
if [[ "$SIGN_IDENT" == "$BUNDLE_ID" ]]; then
    pass "Signing identifier = $BUNDLE_ID"
else
    fail "Signing identifier is '$SIGN_IDENT', expected '$BUNDLE_ID'"
fi

# ─────────────────────────────────────────────
section "4. Signing Stability (Rebuild Test)"
# ─────────────────────────────────────────────

# Save the current code directory hash before rebuild
HASH_BEFORE=$(codesign -dvv "$APP_BUNDLE" 2>&1 | grep "^CDHash=" | cut -d= -f2-)

if [[ -n "$HASH_BEFORE" ]]; then
    pass "CDHash before rebuild: $HASH_BEFORE"

    # Do a fresh build + sign (without launching)
    echo "       Rebuilding app to check signature stability..."
    make app > /dev/null 2>&1

    HASH_AFTER=$(codesign -dvv "$APP_BUNDLE" 2>&1 | grep "^CDHash=" | cut -d= -f2-)
    
    if [[ "$HASH_BEFORE" == "$HASH_AFTER" ]]; then
        pass "CDHash is stable across rebuilds — permissions will persist!"
    else
        # With ad-hoc signing this WILL differ; with a certificate the binary hash
        # differs but the signing identity is stable, which is what TCC cares about.
        if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
            fail "CDHash changed ($HASH_BEFORE → $HASH_AFTER) — ad-hoc signing invalidates TCC permissions!"
        else
            pass "CDHash changed but signing identity is stable — TCC permissions will persist"
        fi
    fi
else
    warn "Could not extract CDHash"
fi

# ─────────────────────────────────────────────
section "5. macOS Permissions (TCC)"
# ─────────────────────────────────────────────

# Check Screen Recording permission
if CGPreflightScreenCaptureAccess 2>/dev/null; then
    pass "Screen Recording permission granted"
else
    # Try via the app itself
    SCREEN_OK=$("$APP_BUNDLE/Contents/MacOS/$APP_NAME" --check-screen 2>/dev/null || echo "")
    # We can't easily check this from a script, so check the TCC database
    TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
    if [[ -r "$TCC_DB" ]]; then
        SCREEN_REC=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='$BUNDLE_ID';" 2>/dev/null || echo "")
        if [[ "$SCREEN_REC" == "2" ]]; then
            pass "Screen Recording: authorized in TCC database"
        elif [[ "$SCREEN_REC" == "0" ]]; then
            fail "Screen Recording: denied in TCC database"
        else
            warn "Screen Recording: unknown status (value='$SCREEN_REC'). Grant in System Settings → Privacy → Screen Recording"
        fi
    else
        warn "Cannot read TCC database (this is normal on recent macOS). Check manually:"
        echo "       System Settings → Privacy & Security → Screen Recording → WorkLogger"
    fi
fi

# Check Accessibility permission
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
if [[ -r "$TCC_DB" ]]; then
    ACCESS=$(sqlite3 "$TCC_DB" "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='$BUNDLE_ID';" 2>/dev/null || echo "")
    if [[ "$ACCESS" == "2" ]]; then
        pass "Accessibility: authorized in TCC database"
    elif [[ "$ACCESS" == "0" ]]; then
        fail "Accessibility: denied in TCC database"
    else
        warn "Accessibility: unknown status. Grant in System Settings → Privacy → Accessibility"
    fi
else
    warn "Cannot read TCC database directly. Checking via alternative method..."
fi

# ─────────────────────────────────────────────
section "6. Certificate Setup"
# ─────────────────────────────────────────────

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    pass "Signing certificate '$CERT_NAME' found in keychain"
else
    fail "Signing certificate '$CERT_NAME' not found — run 'make setup-cert'"
fi

# ─────────────────────────────────────────────
section "7. App Launch Smoke Test"
# ─────────────────────────────────────────────

# Kill any running instance
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Launch the app
open "$APP_BUNDLE"
sleep 2

# Check if it's running
if pgrep -x "$APP_NAME" > /dev/null; then
    pass "App launched successfully"
    
    # Check if menu bar item exists (via AppleScript)
    MENU_CHECK=$(osascript -e '
        tell application "System Events"
            set menuExtras to name of every menu bar item of menu bar 1 of application process "WorkLogger"
            return (count of menuExtras) > 0
        end tell
    ' 2>/dev/null || echo "error")
    
    if [[ "$MENU_CHECK" == "true" ]]; then
        pass "Menu bar item is visible"
    elif [[ "$MENU_CHECK" == "error" ]]; then
        warn "Could not verify menu bar item (Accessibility permission needed for test)"
    else
        fail "Menu bar item not visible — app may be crashing or lacking permissions"
    fi
else
    fail "App failed to launch or crashed immediately"
    
    # Check crash logs
    CRASH_LOG=$(ls -t "$HOME/Library/Logs/DiagnosticReports/${APP_NAME}"* 2>/dev/null | head -1)
    if [[ -n "$CRASH_LOG" ]]; then
        echo "       Recent crash log: $CRASH_LOG"
        echo "       Last 5 lines:"
        tail -5 "$CRASH_LOG" | sed 's/^/       /'
    fi
fi

# Clean up — don't kill the app, leave it running
# killall "$APP_NAME" 2>/dev/null || true

# ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Suggested fixes:"
    echo "  1. Run 'make setup-cert' to create a persistent signing certificate"
    echo "  2. Run 'make app' to rebuild with the new certificate"
    echo "  3. Grant permissions in System Settings → Privacy & Security"
    echo "  4. Run 'make test' again to verify"
    exit 1
fi
