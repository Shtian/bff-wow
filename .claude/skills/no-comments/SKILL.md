---
name: no-comments
description: "Spawn Comment Sicko, fix accepted findings, and offer encodings for claimed constraints."
disable-model-invocation: true
---

# No comments

Spawn Comment Sicko. Act on accepted findings.

Defer to Comment Sicko's fresh perspective.

## Scope

Use the caller's files or diff. Otherwise use the current diff against the base branch, default `main`, including the working tree.

## Steps

1. Spawn `Agent` with `subagent_type: "comment-sicko"` (`.claude/agents/comment-sicko.md`). Pass the scope. Split a large scope into disjoint file sets, one agent each. Do not restate its rules.
2. Inspect its report and diff. Reject application-code edits, scope escapes, exception-protected deletions, misstated `MUST KILL` reasons, and flags that treat kept intentional code as guilty. Reshape flags on our-code surprises stay actionable. Do not restore those comments. A keep survives only with proof it is about something we cannot change (the WoW client, Lua 5.1, `Libs/`). Audit missed `-- luacheck:` suppressions. Correctness or safety suppressions stay actionable `MUST KILL`s. Restore deletions only with exact exceptions and scoped proof. Before accepting thin `IMPORTANT` or `do not remove` kills or keeps, trace their symbol (`git log -S`, `git blame`, callers). If a kill is ambiguous, do not restore. If a keep is refuted or still ambiguous, delete it. Revert and rerun one rejected report with the failure named. Reject a second, report it open, and fail `/no-comments`.
3. Fix trivial accepted flags directly by renaming, naming a constant, deleting a dead path, dropping a parameter, or using the real API. If any fix needs a shape, use the `codebase-design` skill once for the accepted set and surrounding code. Stop at the sketch. Design shapes. Step 4 implements.
4. Implement the smallest root-cause fix in scope. Remove every named workaround. If the root cause is out of scope, land the smallest in-scope fix and report the rest open. Never widen the fence or fix instances outside it. Never bolt on symptom guards.
5. Constraint comments say `do not remove`, `do not change wording`, `keep in sync`, or `talk to X before changing`. Leave keeps about things we cannot change. Offer the cheapest in-scope busted spec, runtime assert, or lint in `scripts/`. Wait for interactive approval. Unattended runs need caller pre-approval. If approved, encode then delete. Otherwise delete, report the constraint open, and sketch out-of-scope work.
6. Run `scripts/check.sh`. Report the deletion count, restored comments, reruns, design sketch, fixes, encoding offers, encodings, unenforced constraints, and other open work.
