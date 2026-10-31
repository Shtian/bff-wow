# BFF – Best Friends in Forever

A World of Warcraft: Forever addon that keeps a group of friends connected when they don't play at the same time: a shared friends panel, a "while you were away" feed, and later competitions and a level-overlap finder.

- **Target API:** WoW: Forever is its own game type (`camelot`, `WOW_PROJECT_CAMELOT`, `## Interface: 16001` as of beta) with a Midnight-style addon API and restrictions. Don't use "is retail" checks. Midnight restricts combat-related APIs and addon comms in combat and instances (`C_ChatInfo.InChatMessagingLockdown()`).
- **Lua version:** WoW runs Lua 5.1. Offline tests run under LuaJIT (`brew install luajit`).
- **Architecture:** see `docs/design/architecture.html`.
- **Releases:** a change to shipped files (`changedFilePatterns` in `.bumpy/_config.json`) needs a bumpy bump file in `.bumpy/`. Use the `add-change` skill. See `docs/design/settings-and-release.md`.

## Agent skills

### Issue tracker

Issues are tracked in GitHub Issues on `Shtian/bff-wow` via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the five default triage labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
