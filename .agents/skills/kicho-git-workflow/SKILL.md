---
name: kicho-git-workflow
description: Safely inspect, validate, commit, push, tag, and verify changes in the Kicho repository. Use for Kicho Git requests such as checking the working tree, preparing a commit, publishing a branch, confirming GitHub Actions, or creating a release tag.
---

# Kicho Git Workflow

Apply Kicho's project-specific checks and safety rules around ordinary Git and
GitHub operations. Keep implementation logic in Kicho itself; this skill only
coordinates existing development tools.

## Establish the Request Boundary

Translate the user's request into the narrowest authorized operation:

- **Inspect or review:** read repository state and report; do not stage, commit,
  push, tag, or edit files.
- **Commit:** validate, stage only the intended files, and commit; do not push.
- **Push:** validate, commit intended uncommitted work when clearly requested,
  push the current branch, and check CI.
- **Tag or release:** follow `RELEASING.md`; do not infer permission to create a
  tag, GitHub release, or other release artifact from a request to push.

Ask before proceeding when the intended files, branch, version, or release
scope cannot be determined safely. Never force-push unless the user explicitly
requests it and the exact consequences have been established.

## Inspect the Repository

1. Locate the repository root and work from it.
2. Read `AI.md`. Read `CONTRIBUTING.md` for contribution work and
   `RELEASING.md` for tags or releases.
3. Inspect the branch, upstream, and complete working-tree status.
4. Review both unstaged and staged diffs. Treat pre-existing changes as the
   user's work and preserve unrelated files.
5. Check recent commit subjects before choosing a new message.

Do not use broad cleanup or history-rewriting commands. In particular, do not
use `git reset --hard`, discard files, or stage everything without first proving
that every changed file belongs to the requested change.

## Validate Changes

Before committing or pushing:

1. Run `git diff --check` and also check the staged diff when files are already
   staged.
2. Run Kicho's full local test harness with macOS Bash 3.2:

   ```sh
   KICHO_TEST_BASH=/bin/bash /bin/bash tests/run.sh
   ```

3. Inspect failures and fix them only when the user's request includes changing
   the implementation. Otherwise report the failure and stop before publishing.
4. Reinspect status and diffs after tests because test commands may create files.

For documentation-only or Skill-only changes, still run the repository test
harness unless it is unavailable. Validate a changed Skill separately with the
Skill Creator validator when that tool is available.

## Commit Intentionally

1. Stage explicit paths that belong to the requested change. Leave unrelated
   modifications and untracked files untouched.
2. Review `git diff --cached --stat` and `git diff --cached`.
3. Confirm the staged result is coherent and contains no credentials, generated
   build artifacts, or accidental personal files.
4. Write a concise imperative commit subject consistent with recent history.
5. Create the commit, then confirm the new commit and clean or expected remaining
   status.

If nothing needs committing, say so rather than creating an empty commit.

## Push and Verify

Push only when explicitly authorized.

1. Confirm the current branch and upstream immediately before pushing.
2. Use a normal push. Set an upstream only for a new intended branch.
3. Confirm that the remote contains the new commit.
4. Inspect the GitHub Actions run triggered by the push and wait for a terminal
   result when practical.
5. Report the branch, commit identifier, and CI result. If CI fails, summarize
   the failing job and logs; do not make additional fixes unless authorized.

Do not open a pull request merely because a branch was pushed. Do not create or
resolve GitHub issues, reviews, or releases without a matching request.

## Tag and Release

Treat a release as a separate, higher-impact workflow:

1. Follow `RELEASING.md` exactly.
2. Confirm the requested version matches source files, documentation, and
   `CHANGELOG.md`.
3. Require a clean tree, passing tests, and successful CI on the release commit.
4. Confirm the exact annotated tag name with the user when it was not explicit.
5. Create and push only that tag, then verify it on GitHub.

Never move or replace an existing release tag without explicit authorization.

## Completion Report

State only actions that actually succeeded. Include:

- files or scope committed
- commit identifier and subject
- pushed branch or tag, if any
- local test result
- GitHub Actions result or a clear note that it is still pending
- unrelated changes deliberately left untouched
