#!/usr/bin/env bash
# Prepare this checkout after a worktree manager creates it.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cd "$repo_root"

missing_tools=()
for tool in xcodebuild xcodegen swiftlint swiftformat gh; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        missing_tools+=("$tool")
    fi
done

if (( ${#missing_tools[@]} > 0 )); then
    printf 'Missing required tools: %s\n' "${missing_tools[*]}" >&2
    echo "Install Xcode and run: brew install xcodegen swiftlint swiftformat gh" >&2
    exit 1
fi

# Catch incomplete Xcode installation/license setup before changing the checkout.
if ! xcodebuild -version; then
    echo "Complete Xcode's first-launch setup, then rerun this script." >&2
    exit 1
fi

for hook in .githooks/pre-commit .githooks/pre-push; do
    if [[ ! -x "$hook" ]]; then
        echo "Required Git hook is missing or not executable: $hook" >&2
        exit 1
    fi
done

# XcodeGen writes the project, Info.plists, and entitlements from project.yml.
generated_paths=(
    NetMonitor-2.0.xcodeproj
    NetMonitor-macOS/Resources/Info.plist
    NetMonitor-macOS/Resources/NetMonitor-macOS.entitlements
    NetMonitor-iOS/Resources/Info.plist
    NetMonitor-iOS/Resources/NetMonitor-iOS.entitlements
    NetMonitor-iOS/Widget/Info.plist
    NetMonitor-iOS/Widget/NetMonitorWidgetExtension.entitlements
    Packages/NetMonitorCore/Package.resolved
)

if ! git diff --quiet -- "${generated_paths[@]}" ||
    ! git diff --cached --quiet -- "${generated_paths[@]}"; then
    echo "Generated files or package locks already have uncommitted changes." >&2
    echo "Commit or otherwise preserve those edits before running setup." >&2
    git status --short --untracked-files=no -- "${generated_paths[@]}"
    exit 1
fi

# Use per-worktree configuration so sibling worktrees retain their hook settings.
if [[ "$(git config --bool --get extensions.worktreeConfig || true)" != "true" ]]; then
    if git config --local --get core.worktree >/dev/null ||
        [[ "$(git config --local --bool --get core.bare || true)" == "true" ]]; then
        echo "Enable extensions.worktreeConfig after migrating core.worktree/core.bare" >&2
        echo "to the main worktree's config.worktree, then rerun setup." >&2
        exit 1
    fi
    git config --local extensions.worktreeConfig true
fi
git config --worktree core.hooksPath .githooks

echo "Generating the Xcode project..."
xcodegen generate

echo "Resolving pinned Swift package dependencies..."
xcodebuild \
    -resolvePackageDependencies \
    -project NetMonitor-2.0.xcodeproj \
    -scheme NetMonitor-macOS \
    -onlyUsePackageVersionsFromResolvedFile

if ! git diff --quiet -- "${generated_paths[@]}" ||
    ! git diff --cached --quiet -- "${generated_paths[@]}"; then
    echo "Setup changed tracked generated files or package locks." >&2
    echo "Review the diff and tool versions; no changes have been discarded." >&2
    git status --short --untracked-files=no -- "${generated_paths[@]}"
    exit 1
fi

if ! git symbolic-ref --quiet --short HEAD >/dev/null; then
    echo "Warning: detached HEAD. Create a codex/<issue-or-task> branch before committing."
fi

echo "Worktree ready. Run tests separately on mac-mini via SSH."
git status --short --branch
