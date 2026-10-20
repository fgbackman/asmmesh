#!/bin/bash
# Double-click me (or: bash "Install on iPhone.command") with your iPhone plugged in.
# Builds asmmesh for iPhone with your Apple ID's signing certificate, installs it on
# the phone and opens it. Everything is also written to build.log next to this file.
cd "$(dirname "$0")"
exec > >(tee build.log) 2>&1
echo "== asmmesh for iPhone =="

# your team: the OU of the Apple Development certificate Xcode made for your Apple ID
TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
       | openssl x509 -noout -subject 2>/dev/null \
       | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
if [ -z "$TEAM" ]; then
  echo "No Apple Development certificate found."
  echo "Open asmmesh.xcodeproj in Xcode, choose your Apple ID under Signing & Capabilities > Team, then run me again."
  exit 1
fi
echo "team: $TEAM"

echo "building (the first time takes a minute)..."
xcodebuild -project asmmesh.xcodeproj -target asmmesh -configuration Debug -sdk iphoneos \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  build > build-full.log 2>&1
rc=$?
grep -E "error:|warning: .*\.(s|swift):|\*\* BUILD" build-full.log | head -60
if [ $rc -ne 0 ]; then
  echo "Build failed - the full output is in build-full.log."
  exit 1
fi
APP="build/Debug-iphoneos/asmmesh.app"

# the plugged-in iPhone
DEV=$(xcrun devicectl list devices --json-output /tmp/asmmesh-devs.json >/dev/null 2>&1 && /usr/bin/python3 - <<'EOF'
import json
d = json.load(open('/tmp/asmmesh-devs.json'))
phones = []
for x in d.get('result', {}).get('devices', []):
    hw = x.get('hardwareProperties', {})
    cp = x.get('connectionProperties', {})
    if hw.get('platform') == 'iOS' and hw.get('reality') == 'physical' and cp.get('pairingState') == 'paired':
        phones.append((cp.get('transportType') != 'wired', x.get('identifier')))
# the phone on the cable first, then one reachable over Wi-Fi
if phones:
    print(sorted(phones)[0][1])
EOF
)
if [ -z "$DEV" ]; then
  echo "Built, but no iPhone found. Plug it in with a cable, unlock it, tap Trust, and run me again."
  echo "(First time: on the iPhone, Settings > Privacy & Security > Developer Mode > On, then restart it.)"
  exit 1
fi
echo "installing on $DEV..."
if ! xcrun devicectl device install app --device "$DEV" "$APP"; then
  echo "Install failed - see above. Developer Mode must be on (Settings > Privacy & Security)."
  exit 1
fi
if xcrun devicectl device process launch --device "$DEV" com.fbackman.asmmesh.ios; then
  echo "asmmesh is open on your iPhone."
else
  echo "Installed. The first time, iPhone won't open it until you trust your certificate:"
  echo "  Settings > General > VPN & Device Management > Apple Development: ... > Trust"
  echo "Then tap asmmesh on the home screen."
fi
echo "With a free Apple ID the app stops opening after 7 days; run me again to renew it."
