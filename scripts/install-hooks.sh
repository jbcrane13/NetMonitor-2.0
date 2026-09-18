#!/usr/bin/env bash
# Install quality git hooks for NetMonitor-2.0
# Usage: ./scripts/install-hooks.sh [--skip-tests]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

echo "Installing quality git hooks..."

cp "$SCRIPT_DIR/pre-commit-quality" "$HOOKS_DIR/pre-commit-quality"
chmod +x "$HOOKS_DIR/pre-commit-quality"

cp "$SCRIPT_DIR/pre-push-quality" "$HOOKS_DIR/pre-push-quality"
chmod +x "$HOOKS_DIR/pre-push-quality"

cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/usr/bin/env sh
# NetMonitor-2.0 pre-commit quality checks
HOOK_DIR="$(dirname "$0")"
if [ -f "$HOOK_DIR/pre-commit-quality" ]; then
    "$HOOK_DIR/pre-commit-quality" "$@" || exit 1
fi
EOF
chmod +x "$HOOKS_DIR/pre-commit"

cat > "$HOOKS_DIR/pre-push" << 'EOF'
#!/usr/bin/env sh
# NetMonitor-2.0 pre-push build verification
HOOK_DIR="$(dirname "$0")"
if [ -f "$HOOK_DIR/pre-push-quality" ]; then
    "$HOOK_DIR/pre-push-quality" "$@" || exit 1
fi
EOF
chmod +x "$HOOKS_DIR/pre-push"

echo "✓ Quality git hooks installed"
echo ""
echo "Pre-commit runs: SwiftLint → SwiftFormat"
echo "Pre-push runs: build verification"
