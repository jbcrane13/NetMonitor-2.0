#!/usr/bin/env bash
# Install NetMonitor-2.0 git hooks by pointing core.hooksPath at .githooks/.
# Run once per clone: scripts/hooks/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.githooks"

if [[ ! -d "$REPO_ROOT/.git" ]]; then
    echo "error: must be run from inside a git repository" >&2
    exit 1
fi

if [[ ! -d "$HOOKS_DIR" ]]; then
    echo "error: .githooks/ directory not found at $HOOKS_DIR" >&2
    exit 1
fi

git -C "$REPO_ROOT" config core.hooksPath .githooks
echo "Git hooks installed — core.hooksPath set to .githooks/"

# Verify SwiftLint is available
if ! command -v swiftlint &>/dev/null; then
    echo "warning: swiftlint not found. Install with: brew install swiftlint"
else
    echo "SwiftLint $(swiftlint version) detected."
fi

echo "Done."
