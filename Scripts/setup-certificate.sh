#!/bin/bash
# Creates a self-signed code signing certificate in the login keychain.
# This certificate persists across builds, so macOS TCC permissions
# (Accessibility, Screen Recording) remain valid after rebuilding.

set -euo pipefail

CERT_NAME="WorkLogger Dev"

# Check if certificate already exists
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✅ Certificate '$CERT_NAME' already exists."
    exit 0
fi

echo "🔐 Creating self-signed code signing certificate '$CERT_NAME'..."
echo "   This uses Keychain Access — you may be prompted for your login password."
echo ""

# Use the certtool/security method that properly creates a code signing identity.
# The most reliable way on macOS is via the Certificate Assistant CLI.
TMPDIR_CERT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CERT"' EXIT

# Create the certificate config for Certificate Assistant
cat > "$TMPDIR_CERT/certparams.cfg" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>certType</key>             <string>Self-Signed Root</string>
    <key>hashFunction</key>         <string>sha256</string>
    <key>keySize</key>              <integer>2048</integer>
    <key>keyUsage</key>
    <array>
        <string>digitalSignature</string>
    </array>
    <key>extendedKeyUsage</key>
    <array>
        <string>1.3.6.1.5.5.7.3.3</string>
    </array>
    <key>basicConstraints</key>
    <dict>
        <key>CA</key>               <false/>
    </dict>
    <key>validityPeriod</key>       <integer>3650</integer>
</dict>
</plist>
EOF

# Try the Python-based approach which works reliably on macOS
python3 - "$CERT_NAME" <<'PYEOF'
import subprocess, sys, os, tempfile

cert_name = sys.argv[1]

# Create certificate using security command with proper extensions
# Step 1: Create a temporary keychain for the operation

script = f'''
    tell application "Keychain Access"
        -- We create the certificate through the Certificate Assistant
    end tell
'''

# Use the command-line certificate creation that works on macOS
# Create an RSA key pair, then a self-signed cert with code signing EKU
tmpdir = tempfile.mkdtemp()

# Generate key and certificate with proper code signing extensions  
subprocess.run([
    "openssl", "req", "-x509", "-newkey", "rsa:2048",
    "-keyout", f"{tmpdir}/key.pem",
    "-out", f"{tmpdir}/cert.pem",
    "-days", "3650", "-nodes",
    "-subj", f"/CN={cert_name}",
    "-addext", "keyUsage=critical,digitalSignature",
    "-addext", "extendedKeyUsage=critical,codeSigning",
    "-addext", "basicConstraints=critical,CA:FALSE",
], check=True, capture_output=True)

# Create PKCS12 bundle  
subprocess.run([
    "openssl", "pkcs12", "-export",
    "-out", f"{tmpdir}/cert.p12",
    "-inkey", f"{tmpdir}/key.pem",
    "-in", f"{tmpdir}/cert.pem",
    "-passout", "pass:temppass123",
    "-legacy",
], check=True, capture_output=True)

# Import into login keychain
result = subprocess.run([
    "security", "import", f"{tmpdir}/cert.p12",
    "-k", os.path.expanduser("~/Library/Keychains/login.keychain-db"),
    "-T", "/usr/bin/codesign",
    "-P", "temppass123",
], capture_output=True, text=True)

if result.returncode != 0:
    # Try without -db suffix
    result = subprocess.run([
        "security", "import", f"{tmpdir}/cert.p12",
        "-k", os.path.expanduser("~/Library/Keychains/login.keychain"),
        "-T", "/usr/bin/codesign",
        "-P", "temppass123",
    ], capture_output=True, text=True)

if result.returncode != 0:
    print(f"Import error: {result.stderr}", file=sys.stderr)
    sys.exit(1)

# Set the key partition list to allow codesign access without prompts
# This requires the login keychain password
subprocess.run([
    "security", "set-key-partition-list",
    "-S", "apple-tool:,apple:,codesign:",
    "-s", "-k", "",  # empty password - will prompt if needed
    os.path.expanduser("~/Library/Keychains/login.keychain-db"),
], capture_output=True, text=True)

print("Certificate imported successfully")
PYEOF

# Verify
echo ""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "✅ Certificate '$CERT_NAME' created and ready for code signing."
    echo "   Now run 'make app' to rebuild with the stable certificate."
else
    echo "❌ Certificate was imported but not recognized for code signing."
    echo ""
    echo "   Manual fallback — create the certificate in Keychain Access:"
    echo "   1. Open Keychain Access.app"
    echo "   2. Menu: Keychain Access → Certificate Assistant → Create a Certificate…"
    echo "   3. Name: $CERT_NAME"
    echo "   4. Identity Type: Self Signed Root"
    echo "   5. Certificate Type: Code Signing"
    echo "   6. Click Create"
    echo ""
    echo "   Then run 'make app' to rebuild with the new certificate."
    exit 1
fi
