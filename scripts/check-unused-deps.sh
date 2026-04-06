#!/usr/bin/env bash
# check-unused-deps.sh — Detect unused imports/dependencies in Swift source files.
#
# Uses Periphery's built-in unused import analysis to find:
#   1. Unused module imports in source files (e.g., `import Foundation` where Foundation is never used)
#   2. Unused package dependencies at the project level
#
# Requirements: periphery (brew install periphery), xcodegen (brew install xcodegen)
#
# Usage:
#   scripts/check-unused-deps.sh          # Human-readable output
#   scripts/check-unused-deps.sh --ci     # GitHub Actions annotations
#
# Exit codes:
#   0 — No unused dependencies found
#   1 — Unused dependencies detected (warning-only in CI)

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

CI_MODE=false
if [[ "${1:-}" == "--ci" ]]; then
    CI_MODE=true
fi

# Ensure we're at repo root
cd "$(git rev-parse --show-toplevel)"

if ! command -v periphery &>/dev/null; then
    echo "error: periphery not installed — brew install periphery"
    exit 1
fi

if [[ ! -f "NetMonitor-2.0.xcodeproj/project.pbxproj" ]]; then
    if command -v xcodegen &>/dev/null; then
        xcodegen generate --quiet 2>/dev/null || true
    else
        echo "error: Xcode project not found and xcodegen not installed"
        exit 1
    fi
fi

echo "Scanning for unused imports and dependencies..."
echo ""

# Run Periphery and extract unused module imports
periphery_json=$(periphery scan --quiet --format json 2>/dev/null || echo "[]")

unused_imports=$(echo "$periphery_json" | python3 -c "
import json, sys

data = json.load(sys.stdin)
unused = [r for r in data if r.get('kind') == 'module' and 'unused' in r.get('hints', [])]

for r in unused:
    loc = r.get('location', '')
    name = r.get('name', '?')
    # Extract file:line from location string
    parts = loc.rsplit(':', 2)
    if len(parts) >= 2:
        filepath = parts[0]
        line = parts[1]
    else:
        filepath = loc
        line = '1'
    # Make path relative
    filepath = filepath.split('NetMonitor-2.0/')[-1] if 'NetMonitor-2.0/' in filepath else filepath
    print(f'{filepath}:{line}:import {name}')
" 2>/dev/null || true)

# Also check for unused package-level dependencies by cross-referencing
# project.yml dependencies with actual import usage in source files
check_package_deps() {
    local target_name="$1"
    local source_dir="$2"

    # Extract package dependencies from project.yml for this target
    local deps
    deps=$(python3 -c "
import yaml, sys

with open('project.yml', 'r') as f:
    proj = yaml.safe_load(f)

target = proj.get('targets', {}).get('$target_name', {})
deps = target.get('dependencies', [])
pkg_deps = [d['package'] for d in deps if 'package' in d]
for d in pkg_deps:
    print(d)
" 2>/dev/null || true)

    if [[ -z "$deps" ]]; then
        return
    fi

    while IFS= read -r pkg; do
        # Check if any Swift file in the source directory imports this package
        import_pattern="^import ${pkg}"
        if ! grep -rq --include="*.swift" "$import_pattern" "$source_dir" 2>/dev/null; then
            echo "${source_dir}/::package ${pkg} declared in project.yml but never imported in ${target_name}"
        fi
    done <<< "$deps"
}

# Check both app targets for unused package dependencies
pkg_unused=""
pkg_unused+=$(check_package_deps "NetMonitor-macOS" "NetMonitor-macOS" 2>/dev/null || true)
pkg_unused+=$(check_package_deps "NetMonitor-iOS" "NetMonitor-iOS" 2>/dev/null || true)

# Combine results
total_issues=0

if [[ -n "$unused_imports" ]]; then
    if [[ "$CI_MODE" == "true" ]]; then
        echo "## Unused Module Imports"
        echo ""
    else
        echo -e "${CYAN}── Unused Module Imports ──${NC}"
        echo ""
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        total_issues=$((total_issues + 1))
        filepath=$(echo "$line" | cut -d: -f1)
        lineno=$(echo "$line" | cut -d: -f2)
        detail=$(echo "$line" | cut -d: -f3-)

        if [[ "$CI_MODE" == "true" ]]; then
            echo "::warning file=${filepath},line=${lineno}::Unused ${detail} — remove to keep dependencies clean"
        else
            echo -e "  ${YELLOW}warning:${NC} ${filepath}:${lineno} — Unused ${detail}"
        fi
    done <<< "$unused_imports"
    echo ""
fi

if [[ -n "$pkg_unused" ]]; then
    if [[ "$CI_MODE" == "true" ]]; then
        echo "## Unused Package Dependencies"
        echo ""
    else
        echo -e "${CYAN}── Unused Package Dependencies ──${NC}"
        echo ""
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        total_issues=$((total_issues + 1))
        detail=$(echo "$line" | cut -d: -f3-)

        if [[ "$CI_MODE" == "true" ]]; then
            echo "::warning file=project.yml::Unused ${detail}"
        else
            echo -e "  ${YELLOW}warning:${NC} ${detail}"
        fi
    done <<< "$pkg_unused"
    echo ""
fi

# Summary
if [[ $total_issues -eq 0 ]]; then
    if [[ "$CI_MODE" == "true" ]]; then
        echo "No unused imports or dependencies detected."
    else
        echo -e "${GREEN}No unused imports or dependencies detected.${NC}"
    fi
    exit 0
else
    if [[ "$CI_MODE" == "true" ]]; then
        echo ""
        echo "Found ${total_issues} unused import(s)/dependency(ies)."
        echo "Remove unused imports to keep the dependency graph clean and build times fast."
    else
        echo -e "${YELLOW}Found ${total_issues} unused import(s)/dependency(ies).${NC}"
        echo "Remove unused imports to keep the dependency graph clean and build times fast."
    fi
    exit 1
fi
