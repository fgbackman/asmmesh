#!/bin/bash
# Double-click me (or: bash "Install on iPhone.command") with your iPhone or iPad plugged in.
# A phone it doesn't find: name it, bash "Install on iPhone.command" "iphoney (2)".
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
    plat, real = hw.get('platform') or '', hw.get('reality') or ''
    if plat not in ('', 'iOS') or real == 'virtual':
        continue                    # a watch, a Mac, a simulator
    if not plat or not real:        # its details haven't come through: say so, try it anyway
        print('  %s: not fully set up with this Mac yet (unlocked? Developer Mode on?) - trying it anyway' % name, file=sys.stderr)
    via = {'wired': 'cable', 'localNetwork': 'Wi-Fi'}.get(cp.get('transportType'), 'not connected now')
    if cp.get('pairingState') != 'paired':
        print('skipped %s (%s): not paired with this Mac (plug it in, unlock it, tap Trust)' % (name, via), file=sys.stderr)
        continue
    print('  %s: paired, %s' % (name, via), file=sys.stderr)
    print(x.get('identifier') + '\t' + name + '\t' + via)
EOF2
)
# phones named on the command line get it whatever the list says (devicectl takes a name):
#   bash "Install on iPhone.command" "iphoney (2)"
for want in "$@"; do
  if ! printf '%s\n' "$DEVS" | cut -f2 | grep -qxF "$want"; then
    DEVS="$DEVS${DEVS:+
}$want	$want	named"
  fi
done
echo "found: $(printf '%s\n' "$DEVS" | cut -f2 | paste -sd ',' - | sed 's/,/, /g')"
echo "(an iPhone missing here isn't seen by this Mac at all: plug it in with a cable, unlock it, tap Trust)"
if [ -z "$DEVS" ]; then
  echo "Built, but no iPhone or iPad found. Plug it in with a cable, unlock it, tap Trust, and run me again."
  echo "(First time: on the device, Settings > Privacy & Security > Developer Mode > On, then restart it.)"
  exit 1
fi
failed=0
# The list comes in on fd 3: devicectl reads stdin, and on stdin it would eat the rest of
# the list, so only the first device got the app.
while IFS="$(printf '\t')" read -r DEV NAME VIA <&3; do
  echo "== $NAME ($VIA) =="
  ok=0
  for try in 1 2 3; do              # a locked or sleeping phone: time to unlock it, then again
    out=$(xcrun devicectl device install app --device "$DEV" "$APP" </dev/null 2>&1)
    echo "$out" | grep -E "App installed|ERROR|locked" | head -3
    if xcrun devicectl device info apps --device "$DEV" --bundle-id com.fbackman.asmmesh.ios </dev/null 2>/dev/null | grep -q asmmesh; then
      ok=1; break
    fi
    [ $try -eq 3 ] && break
    if echo "$out" | grep -q "4016"; then
      echo "  $NAME can't take it right now: unlock it and keep its screen on$( [ "$VIA" = "Wi-Fi" ] && echo ', or plug it in with a cable (over Wi-Fi a sleeping phone can'"'"'t)')."
    else
      echo "  Unlock $NAME and keep its screen on."
    fi
    echo "  Trying again in 15 s ($try of 3)..."
    sleep 15
  done
  if [ $ok -eq 0 ]; then
    echo "Not installed on $NAME - unlock it and keep the screen on; plug it in with a cable if it's on Wi-Fi;"
    echo "  the first time, turn on Developer Mode (Settings > Privacy & Security > Developer Mode)."
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
