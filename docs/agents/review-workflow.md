# Review and merge workflow

Use this to review and merge a pull request in NetMonitor-2.0. GitHub Actions gives little signal today: SwiftLint and SwiftFormat already fail on `main`, and the coverage job stops at a compile error before it runs any tests. The **gates** below are the real merge bar.

Roles:

- **Worker:** builds the change in its own worktree and opens the PR.
- **Lead:** the orchestrating session. Reviews, decides and merges.
- **Reviewers:** independent read-only agents the lead starts.

A worker's own inline review is welcome, but it never counts as the review.

## 1. Pin the review point

Record the PR's base and head commit hashes. Every reviewer diffs exactly `base...head`.

When the head moves after a review (fix commits, PR-agent pushes, a rebase), anything not re-checked is stale: re-check the new commits before merging.

Done when: both hashes are written down.

## 2. Two-axis review

Use `pocock-github-workflow:pocock-code-review`. Start **two independent reviewers** in parallel, each in a fresh context and strictly **read-only**: `git diff` and `git show` only. Reviewers never run `git checkout`, `switch`, `reset` or `stash`. One reviewer once detached a worker's branch that way.

**Standards reviewer**

- Checks the diff against `AGENTS.md`, `~/.claude/apple.md` and the code-smell baseline.
- Name the risk areas for this PR in its brief. Examples: Swift 6 isolation, test isolation from the user's real data, UI-test code in production paths, raw IPs, MACs or hostnames in logs.

**Spec reviewer**

- Checks the diff against the issue and its comments, the worker's brief, Blake's recorded decisions, and the worker's report of deviations.
- Asks for each requirement: done, partial, or wrong, with a concrete failing case.
- For any model-written text, checks whether the model can still state a wrong pairing or contradict the app's verdict.

The lead reads both reports, makes each call, and sends one consolidated fix list to the worker.

**Codex review:**
- **`/codex:review`** is the per-PR Codex layer. The lead runs it on the head pinned in step 1, and again on each new head after fixes: `~/.claude/scripts/codex-review.sh review <worktree> --base origin/main`. A worker can't run the slash command itself. It takes no brief and reviews the diff as is; its findings are handled like any other review thread.
- **`/codex:adversarial-review`** is run on demand when a PR carries risk: concurrency, data integrity or migration, privacy or security, the companion protocol, or model output that the user sees as fact. The lead runs `~/.claude/scripts/codex-review.sh adversarial-review <worktree> --base origin/main "<brief>"`.
  - It accepts a text brief and needs one. Give it the PR's intent, Blake's recorded decisions, the accepted deviations and the risk areas to attack, the same context the spec reviewer gets.
- **The `codex-review` gate is not a per-PR review.** It is a Claude Code Stop hook that reviews each turn's edits when the turn stops, and it must be active in every worktree. `scripts/setup-worktree.sh` enables it through `~/.claude/scripts/enable-review-gate.sh` and prints the hook's `state.json` path. A new worktree isn't ready for work until that line appears.

None of these replaces the two-axis review; they add to it.

Done when: both reports are in, and every finding is fixed, filed as an issue, or explicitly accepted with a reason.

## 3. Verify the fix round

When the fixes land, give a verification reviewer the item-by-item fix list against `previous-head..new-head`. Small rounds can be checked by the lead directly.

Done when: every item is confirmed or sent back.

## 4. Gates on the PR's final code

Pick the test host by the Test Execution Policy in `AGENTS.md`: mini-pro-2 first, mini-pro-1 only as that policy allows. On mini-pro-1, run under `lockf -t 7200 /tmp/nm-mini1-test.lock timeout 1200 …`. Run these:

- Use private DerivedData outside the source tree, and a throwaway simulator.
- Core: `swift test --no-parallel`.
- The full macOS and iOS unit suites.
- The PR's user-flow tests:
  - iOS: XCUITest with screenshots.
  - macOS: the AX scripts in `scripts/ax/`.
  - Look at every screenshot.
- `swiftlint lint --strict` and `swiftformat --lint` clean on **every changed file**, including errors that were already there.
- Grep the test logs for `Test run with`, `Restarting after unexpected` and `Fatal error`.

Timing failures under a load average above about 100 are not evidence (#524). Rerun when the load is below 40.

A worker's focused rerun after a rebase is not enough: the full suites must pass on the final code.

Done when: every gate passes on the PR head being merged.

## 5. CI and threads

- **CI:** each failing check fails the same way on `main`, and none of its findings is in a file the PR changes. An infrastructure failure, such as a runner that couldn't reach GitHub, is rerun.
- **Threads:** every review thread is answered and resolved.

Only one writer pushes to a PR branch at a time. Pause the PR comment agent (`launchctl bootout gui/$(id -u)/com.blake.netmonitor-pr-agent`) while a worker owns the branch, and re-enable it afterwards. Workers fetch and rebase on their own remote branch before pushing, and force-push only with `--force-with-lease=<branch>:<sha>` after a rebase.

Done when: no thread is unresolved and no CI failure is new.

## 6. Merge

1. When `main` has moved since the PR's base, merge it onto current `main` locally and build both app test targets first. If the PRs merged since the base touched the same modules or shared files as this PR, also run the affected test suites on the combined code. Two PRs merged one after the other broke `main` twice in November 2026: once on a protocol requirement, once on a dropped `UITestBootstrap` block.
2. Squash-merge, then confirm each issue the PR closes (`Closes #n`) is closed. An issue the PR only partly delivers (`Part of #n`) stays open.
3. Retire the worker's pane and worktree, and delete the branch. Keep the `pr-evidence/*` branches: the PR bodies link to their screenshots.

Done when: `main` has the merge commit and the issue state is correct.

## Decisions

- **Ask Blake:** new scope, privacy, and anything hard to reverse.
- **Decide yourself:** a small, reversible fork inside a decision he already made. Pick the option closest to his intent, record it on the issue and in the PR, and tell him how to override it.
