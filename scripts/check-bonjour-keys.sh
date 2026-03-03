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

# plist_get KEY FILE  — returns value using plutil (macOS) or plistlib (Linux)
plist_has_key() {
  local key="$1" file="$2"
  if command -v plutil &>/dev/null; then
    plutil -extract "$key" raw -o - "$file" >/dev/null 2>&1
  else
    python3 -c "import plistlib,sys
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
sys.exit(0 if sys.argv[2] in p else 1)" "$file" "$key"
  fi
}

plist_array_count() {
  local key="$1" file="$2"
  if command -v plutil &>/dev/null; then
    plutil -extract "$key" json -o - "$file" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"
  else
    python3 -c "import plistlib,sys
with open(sys.argv[1],'rb') as f: p=plistlib.load(f)
print(len(p.get(sys.argv[2],[])))" "$file" "$key"
  fi
}

for plist in "${PLISTS[@]}"; do
  if [ ! -f "$plist" ]; then
    echo "❌ MISSING: $plist"
    FAILED=1
    continue
  fi

  if ! plist_has_key NSBonjourServices "$plist"; then
    echo "❌ $plist: NSBonjourServices key MISSING"
    FAILED=1
    continue
  fi

  COUNT=$(plist_array_count NSBonjourServices "$plist")
  if [ "$COUNT" -lt "$EXPECTED_COUNT" ]; then
    echo "❌ $plist: NSBonjourServices has $COUNT types (expected >= $EXPECTED_COUNT)"
    FAILED=1
  else
    echo "✅ $plist: $COUNT Bonjour types"
  fi

  if ! plist_has_key NSLocalNetworkUsageDescription "$plist"; then
    echo "❌ $plist: NSLocalNetworkUsageDescription MISSING"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "🚨 Bonjour keys check FAILED"
  exit 1
fi

echo "✅ All Bonjour keys verified"
