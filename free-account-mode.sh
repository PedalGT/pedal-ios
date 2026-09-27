#!/bin/bash
# Apple Pay and NFC entitlements can't be signed by a free personal team, so a
# device build with them fails. This flips them off (and back on).
#
#   ./free-account-mode.sh on    # free Apple ID: build and run on your iPhone
#   ./free-account-mode.sh off   # paid account: Apple Pay + NFC enabled
set -e
cd "$(dirname "$0")"
FILE=Pedal/Pedal.entitlements

case "$1" in
  on)
    cat > "$FILE" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
XML
    echo "Free-account mode ON."
    echo "  Apple Pay  -> the wallet falls back to the test-card form"
    echo "  NFC scan   -> \"Scan lock\" says NFC isn't available, type the code instead"
    ;;
  off)
    cat > "$FILE" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.in-app-payments</key>
	<array>
		<string>merchant.com.sahilquazi.pedal</string>
	</array>
	<key>com.apple.developer.associated-domains</key>
	<array>
		<string>applinks:PLACEHOLDER-SITE.example</string>
	</array>
	<key>com.apple.developer.nfc.readersession.formats</key>
	<array>
		<string>NDEF</string>
		<string>TAG</string>
	</array>
</dict>
</plist>
XML
    echo "Free-account mode OFF. Apple Pay and NFC entitlements restored."
    echo "Register merchant.com.sahilquazi.pedal and add both capabilities in Xcode."
    ;;
  *)
    echo "usage: $0 on|off"; exit 1 ;;
esac
xcodegen generate >/dev/null && echo "Project regenerated."
