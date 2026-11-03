#!/bin/bash
# Double-click me (or: bash "Install on iPhone.command") with your iPhone or iPad plugged in.
# Builds asmmesh for iPhone and iPad with your Apple ID's signing certificate, installs it on
# every paired one and opens it. Everything is also written to build.log next to this file.
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
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
  build > build-full.log 2>&1
rc=$?
grep -E "error:|warning: .*\.(s|swift):|\*\* BUILD" build-full.log | head -60
if [ $rc -ne 0 ]; then
  echo "Build failed - the full output is in build-full.log."
  exit 1
fi
APP="build/Debug-iphoneos/asmmesh.app"

# every paired iPhone and iPad (cable or Wi-Fi), so they all run the same build. A new one
# must be in the signing profile: -allowProvisioningDeviceRegistration adds plugged-in ones;
# if one still says "profile cannot be installed", build once with -destination id=<its UDID>.
# Ones seen but left out are named, with why, so none is skipped without a word.
DEVS=$(xcrun devicectl list devices --json-output /tmp/asmmesh-devs.json </dev/null >/dev/null 2>&1 && /usr/bin/python3 - <<'EOF2'
import json, sys
d = json.load(open('/tmp/asmmesh-devs.json'))
for x in d.get('result', {}).get('devices', []):
    hw = x.get('hardwareProperties', {})
    cp = x.get('connectionProperties', {})
    name = x.get('deviceProperties', {}).get('name', '?')
    if hw.get('platform') != 'iOS' or hw.get('reality') != 'physical':
        continue
    if cp.get('pairingState') != 'paired':
        print('skipped %s: not paired with this Mac (plug it in, unlock it, tap Trust)' % name, file=sys.stderr)
        continue
    print(x.get('identifier') + '\t' + name)
EOF2
)
echo "found: $(printf '%s\n' "$DEVS" | cut -f2 | paste -sd ',' - | sed 's/,/, /g')"
if [ -z "$DEVS" ]; then
  echo "Built, but no iPhone or iPad found. Plug it in with a cable, unlock it, tap Trust, and run me again."
  echo "(First time: on the device, Settings > Privacy & Security > Developer Mode > On, then restart it.)"
  exit 1
fi
failed=0
# The list comes in on fd 3: devicectl reads stdin, and on stdin it would eat the rest of
# the list, so only the first device got the app.
while IFS="$(printf '\t')" read -r DEV NAME <&3; do
  echo "== $NAME =="
  xcrun devicectl device install app --device "$DEV" "$APP" </dev/null 2>&1 | grep -E "App installed|ERROR|locked" | head -3
  if ! xcrun devicectl device info apps --device "$DEV" --bundle-id com.fbackman.asmmesh.ios </dev/null 2>/dev/null | grep -q asmmesh; then
    echo "Not installed on $NAME - unlock it; the first time, turn on Developer Mode (Settings > Privacy & Security)."
    failed=1
    continue
  fi
  if out=$(xcrun devicectl device process launch --device "$DEV" com.fbackman.asmmesh.ios </dev/null 2>&1); then
    echo "asmmesh is open on $NAME."
  elif echo "$out" | grep -q "Locked"; then
    echo "Installed on $NAME, but it was locked: unlock it and tap asmmesh."
  else
    echo "Installed on $NAME, but it didn't open. The first time, trust your certificate:"
    echo "  Settings > General > VPN & Device Management > Apple Development: ... > Trust"
  fi
done 3<<< "$DEVS"
echo "With a free Apple ID the app stops opening after 7 days; run me again to renew it."
exit $failed
