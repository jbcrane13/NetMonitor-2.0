#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== NetMonitor 2.0 — WiFi Heatmap Mission Init ==="

# Regenerate Xcode project from project.yml
if command -v xcodegen &>/dev/null; then
  echo "Regenerating Xcode project..."
  xcodegen generate 2>&1 | tail -3
else
  echo "WARNING: xcodegen not found. Install with: brew install xcodegen"
fi

# Verify builds compile
echo "Verifying macOS build..."
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -5

echo "Verifying iOS build..."
xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | tail -5

echo "=== Init complete ==="
