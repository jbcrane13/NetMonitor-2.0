#!/bin/bash
# CI gate: verify NSBonjourServices has all required types in both plists.
# Fails if any plist is missing keys or has fewer than expected.

set -euo pipefail

REPO="${1:-$HOME/Projects/NetMonitor-2.0}"
EXPECTED_COUNT=19
PLISTS=(
  "$REPO/NetMonitor-iOS/Resources/Info.plist"
  "$REPO/NetMonitor-macOS/Resources/Info.plist"
)

FAILED=0

for plist in "${PLISTS[@]}"; do
  if [ ! -f "$plist" ]; then
    echo "❌ MISSING: $plist"
    FAILED=1
    continue
  fi

  if ! plutil -extract NSBonjourServices json -o - "$plist" >/dev/null 2>&1; then
    echo "❌ $plist: NSBonjourServices key MISSING"
    FAILED=1
    continue
  fi

  COUNT=$(plutil -extract NSBonjourServices json -o - "$plist" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")
  if [ "$COUNT" -lt "$EXPECTED_COUNT" ]; then
    echo "❌ $plist: NSBonjourServices has $COUNT types (expected >= $EXPECTED_COUNT)"
    FAILED=1
  else
    echo "✅ $plist: $COUNT Bonjour types"
  fi

  if ! plutil -extract NSLocalNetworkUsageDescription raw -o - "$plist" >/dev/null 2>&1; then
    echo "❌ $plist: NSLocalNetworkUsageDescription MISSING"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "🚨 Bonjour keys check FAILED"
  exit 1
fi

echo "✅ All Bonjour keys verified"
