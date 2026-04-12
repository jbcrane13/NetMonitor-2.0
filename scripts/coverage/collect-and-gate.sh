#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build/coverage}"

IOS_SCHEME="${IOS_SCHEME:-NetMonitor-iOS}"
MACOS_SCHEME="${MACOS_SCHEME:-NetMonitor-macOS}"
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,OS=latest,name=iPhone 17}"
MACOS_DESTINATION="${MACOS_DESTINATION:-platform=macOS}"

IOS_APP_FLOOR="${IOS_APP_FLOOR:-30}"
MACOS_APP_FLOOR="${MACOS_APP_FLOOR:-20}"
NETMONITORCORE_FLOOR="${NETMONITORCORE_FLOOR:-40}"
NETWORKSCANKIT_FLOOR="${NETWORKSCANKIT_FLOOR:-38}"

SKIP_XCODE_TESTS="${SKIP_XCODE_TESTS:-0}"
SKIP_PACKAGE_TESTS="${SKIP_PACKAGE_TESTS:-0}"

IOS_RESULT="$BUILD_DIR/${IOS_SCHEME}.xcresult"
MACOS_RESULT="$BUILD_DIR/${MACOS_SCHEME}.xcresult"

IOS_COVERAGE_JSON="$BUILD_DIR/${IOS_SCHEME}-coverage.json"
MACOS_COVERAGE_JSON="$BUILD_DIR/${MACOS_SCHEME}-coverage.json"
NETMONITORCORE_COVERAGE_JSON="$BUILD_DIR/NetMonitorCore-coverage.json"
NETWORKSCANKIT_COVERAGE_JSON="$BUILD_DIR/NetworkScanKit-coverage.json"

SUMMARY_JSON="$BUILD_DIR/coverage-summary.json"
SUMMARY_MD="$BUILD_DIR/coverage-summary.md"

mkdir -p "$BUILD_DIR"

run_xcode_tests() {
  rm -rf "$IOS_RESULT" "$MACOS_RESULT"

  # Production builds use SWIFT_STRICT_CONCURRENCY=complete, but test code
  # has Swift 6 actor-isolation issues with XCUIApplication's @MainActor API
  # that can't be fixed at source level. Override to minimal for test builds.
  xcodebuild test \
    -scheme "$IOS_SCHEME" \
    -destination "$IOS_DESTINATION" \
    -enableCodeCoverage YES \
    -resultBundlePath "$IOS_RESULT" \
    SWIFT_STRICT_CONCURRENCY=minimal

  xcodebuild test \
    -scheme "$MACOS_SCHEME" \
    -destination "$MACOS_DESTINATION" \
    -enableCodeCoverage YES \
    -resultBundlePath "$MACOS_RESULT" \
    SWIFT_STRICT_CONCURRENCY=minimal
}

collect_xccov_reports() {
  xcrun xccov view --report --json "$IOS_RESULT" > "$IOS_COVERAGE_JSON"
  xcrun xccov view --report --json "$MACOS_RESULT" > "$MACOS_COVERAGE_JSON"
}

run_package_coverage_tests() {
  # --no-parallel prevents concurrent test suite execution which triggers
  # EXC_BREAKPOINT crashes in Foundation's Swift URLSession on macOS 26 beta
  # when SpeedTestService creates real ephemeral sessions concurrently with
  # mock sessions from other suites. Remove if the bug is fixed in a later OS.
  #
  # NOTE: swift test --enable-code-coverage may crash with signal 5 (SIGTRAP)
  # when using Swift Testing framework on Swift 6. If this happens, generate a
  # placeholder coverage file so the gate doesn't fail entirely.
  (
    cd "$ROOT_DIR/Packages/NetMonitorCore"
    if swift test --enable-code-coverage --no-parallel 2>&1 | tee "$BUILD_DIR/NetMonitorCore-swift-test.log"; then
      cp "$(swift test --show-codecov-path)" "$NETMONITORCORE_COVERAGE_JSON"
    else
      echo "warning: NetMonitorCore swift test crashed (signal 5 known issue with Swift Testing)"
      echo '{"data":[{"totals":{"lines":{"percent":0}}}]}' > "$NETMONITORCORE_COVERAGE_JSON"
    fi
  )

  (
    cd "$ROOT_DIR/Packages/NetworkScanKit"
    if swift test --enable-code-coverage --no-parallel 2>&1 | tee "$BUILD_DIR/NetworkScanKit-swift-test.log"; then
      cp "$(swift test --show-codecov-path)" "$NETWORKSCANKIT_COVERAGE_JSON"
    else
      echo "warning: NetworkScanKit swift test crashed (signal 5 known issue with Swift Testing)"
      echo '{"data":[{"totals":{"lines":{"percent":0}}}]}' > "$NETWORKSCANKIT_COVERAGE_JSON"
    fi
  )
}

extract_xccov_target_percent() {
  local report_json="$1"
  local target_name="$2"
  python3 - "$report_json" "$target_name" <<'PY'
import json
import sys

report_path = sys.argv[1]
target_name = sys.argv[2]

with open(report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

targets = payload.get("targets", [])
target = None
for candidate in targets:
    if candidate.get("name") == target_name:
        target = candidate
        break

if target is None:
    raise SystemExit(f"Target '{target_name}' not found in {report_path}")

covered = float(target.get("coveredLines", 0))
executable = float(target.get("executableLines", 0))
percent = (covered / executable * 100.0) if executable else 0.0
print(f"{percent:.2f}")
PY
}

extract_llvm_line_percent() {
  local report_json="$1"
  python3 - "$report_json" <<'PY'
import json
import sys

report_path = sys.argv[1]
with open(report_path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

try:
    percent = float(payload["data"][0]["totals"]["lines"]["percent"])
except (KeyError, IndexError, TypeError):
    raise SystemExit(f"Unable to locate line coverage in {report_path}")

print(f"{percent:.2f}")
PY
}

is_at_least_floor() {
  local actual="$1"
  local floor="$2"
  python3 - "$actual" "$floor" <<'PY'
import sys
actual = float(sys.argv[1])
floor = float(sys.argv[2])
sys.exit(0 if actual >= floor else 1)
PY
}

check_floor() {
  local label="$1"
  local actual="$2"
  local floor="$3"

  if is_at_least_floor "$actual" "$floor"; then
    echo "PASS ${label}: ${actual}% >= ${floor}%"
    return 0
  fi

  echo "FAIL ${label}: ${actual}% < ${floor}%"
  return 1
}

if [[ "$SKIP_XCODE_TESTS" != "1" ]]; then
  run_xcode_tests
  collect_xccov_reports
fi

if [[ "$SKIP_PACKAGE_TESTS" != "1" ]]; then
  run_package_coverage_tests
fi

for required_file in \
  "$IOS_COVERAGE_JSON" \
  "$MACOS_COVERAGE_JSON" \
  "$NETMONITORCORE_COVERAGE_JSON" \
  "$NETWORKSCANKIT_COVERAGE_JSON"
do
  if [[ ! -f "$required_file" ]]; then
    echo "Missing required coverage artifact: $required_file"
    exit 1
  fi
done

ios_app_percent="$(extract_xccov_target_percent "$IOS_COVERAGE_JSON" "NetMonitor-iOS.app")"
macos_app_percent="$(extract_xccov_target_percent "$MACOS_COVERAGE_JSON" "NetMonitor-macOS.app")"
netmonitorcore_percent="$(extract_llvm_line_percent "$NETMONITORCORE_COVERAGE_JSON")"
networkscankit_percent="$(extract_llvm_line_percent "$NETWORKSCANKIT_COVERAGE_JSON")"

echo
echo "Coverage summary:"
echo "  NetMonitor-iOS.app:  ${ios_app_percent}%"
echo "  NetMonitor-macOS.app: ${macos_app_percent}%"
echo "  NetMonitorCore:       ${netmonitorcore_percent}%"
echo "  NetworkScanKit:       ${networkscankit_percent}%"
echo

failures=0

check_floor "NetMonitor-iOS.app" "$ios_app_percent" "$IOS_APP_FLOOR" || failures=$((failures + 1))
check_floor "NetMonitor-macOS.app" "$macos_app_percent" "$MACOS_APP_FLOOR" || failures=$((failures + 1))
check_floor "NetMonitorCore" "$netmonitorcore_percent" "$NETMONITORCORE_FLOOR" || failures=$((failures + 1))
check_floor "NetworkScanKit" "$networkscankit_percent" "$NETWORKSCANKIT_FLOOR" || failures=$((failures + 1))

ios_status="FAIL"
macos_status="FAIL"
core_status="FAIL"
scan_status="FAIL"

if is_at_least_floor "$ios_app_percent" "$IOS_APP_FLOOR"; then ios_status="PASS"; fi
if is_at_least_floor "$macos_app_percent" "$MACOS_APP_FLOOR"; then macos_status="PASS"; fi
if is_at_least_floor "$netmonitorcore_percent" "$NETMONITORCORE_FLOOR"; then core_status="PASS"; fi
if is_at_least_floor "$networkscankit_percent" "$NETWORKSCANKIT_FLOOR"; then scan_status="PASS"; fi

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - \
  "$SUMMARY_JSON" \
  "$generated_at" \
  "$ios_app_percent" "$IOS_APP_FLOOR" "$ios_status" \
  "$macos_app_percent" "$MACOS_APP_FLOOR" "$macos_status" \
  "$netmonitorcore_percent" "$NETMONITORCORE_FLOOR" "$core_status" \
  "$networkscankit_percent" "$NETWORKSCANKIT_FLOOR" "$scan_status" <<'PY'
import json
import sys

output_path = sys.argv[1]
generated_at = sys.argv[2]

payload = {
    "generatedAt": generated_at,
    "targets": [
        {
            "name": "NetMonitor-iOS.app",
            "coverage": float(sys.argv[3]),
            "floor": float(sys.argv[4]),
            "status": sys.argv[5],
        },
        {
            "name": "NetMonitor-macOS.app",
            "coverage": float(sys.argv[6]),
            "floor": float(sys.argv[7]),
            "status": sys.argv[8],
        },
        {
            "name": "NetMonitorCore",
            "coverage": float(sys.argv[9]),
            "floor": float(sys.argv[10]),
            "status": sys.argv[11],
        },
        {
            "name": "NetworkScanKit",
            "coverage": float(sys.argv[12]),
            "floor": float(sys.argv[13]),
            "status": sys.argv[14],
        },
    ],
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2, sort_keys=False)
    handle.write("\n")
PY

cat > "$SUMMARY_MD" <<EOF
# Coverage Summary

Generated: ${generated_at}

| Target | Coverage | Floor | Status |
| --- | ---: | ---: | --- |
| NetMonitor-iOS.app | ${ios_app_percent}% | ${IOS_APP_FLOOR}% | ${ios_status} |
| NetMonitor-macOS.app | ${macos_app_percent}% | ${MACOS_APP_FLOOR}% | ${macos_status} |
| NetMonitorCore | ${netmonitorcore_percent}% | ${NETMONITORCORE_FLOOR}% | ${core_status} |
| NetworkScanKit | ${networkscankit_percent}% | ${NETWORKSCANKIT_FLOOR}% | ${scan_status} |
EOF

echo
echo "Wrote coverage artifacts:"
echo "  $SUMMARY_JSON"
echo "  $SUMMARY_MD"

if [[ "$failures" -gt 0 ]]; then
  echo
  echo "Coverage gate failed with ${failures} threshold violation(s)."
  exit 1
fi

echo
echo "Coverage gate passed."
