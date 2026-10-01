#!/bin/bash
# Double-click me: builds asmmesh, runs its self-tests, installs it to /Applications,
# pins it to the Dock and launches it. The output is also saved to install.log.
# In a git checkout, every successful install is committed ("build N installed").
cd "$(dirname "$0")"
# one install at a time: a second double-click (or another session) is turned away
LOCK="${TMPDIR:-/tmp}/asmmesh-install.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
    echo "Another asmmesh install is already running - this one will not start. Wait for it to finish."
    sleep 8
    exit 1
  fi
  echo "(clearing a lock left behind by an install that was stopped)"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT
set -o pipefail
pkill -9 -f "lldb --batch" 2>/dev/null; pkill -9 -f "asmmesh --selftest" 2>/dev/null
sh ./install.sh 2>&1 | tee install.log
rc=$?
# a quick health check: still running 20 s later? if not, keep the crash report
sleep 20
if pgrep -x asmmesh >/dev/null; then echo "health: asmmesh still running after 20 s" >> install.log
else
  echo "health: asmmesh is NOT running" >> install.log
  f=$(ls -t ~/Library/Logs/DiagnosticReports/*asmmesh* 2>/dev/null | head -1)
  [ -n "$f" ] && { echo "crash report: $f"; head -c 40000 "$f"; } > crash.log
  rc=1
fi
# record the build in git (only when the self-tests passed and the app is running)
if [ $rc -eq 0 ] && [ -d .git ] && git --version >/dev/null 2>&1; then
  b=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Info.plist 2>/dev/null)
  git add -A
  if git diff --cached --quiet; then echo "git: nothing new to commit" >> install.log
  else git commit -q -m "build $b installed" && echo "git: committed build $b on $(git branch --show-current)" >> install.log
  fi
fi
