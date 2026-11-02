# Coding standards

Read during review. Each rule here needs judgement; anything luacheck enforces (`.luacheckrc`, e.g. no WoW globals in `Core/`) isn't repeated.

## Naming

- **Domain words come from `CONTEXT.md`.** Name things with the glossary's terms, used in the glossary's sense. A new identifier, table or event that reuses a glossary word for something else is a violation (e.g. a table of setting hooks named `REACTIONS`, when a Reaction is a Member's Cheer or Respects).
- **Architecture words** (module, interface, seam, adapter, depth) mean what the `codebase-design` skill says.

## Tests

- **The interface is the test surface.** Tests create Cores and check what Core's interface returns or announces. They may seed `db` (e.g. a legacy layout) but never read `db`, Ledger or Gossip back. Rationale and the exception for pure helper files: `docs/design/code-structure.md`, "Tests".

## Structure

- **Core decides; UI renders.** A rule about what happens (whether something is announced, where it goes, what counts as a change) belongs in Core. UI and App act on what Core says, and don't read settings to decide behaviour themselves. Module boundaries: `docs/design/code-structure.md`, "Modules".
- **Docs move with the code.** A change to Core's interface, its events or a setting updates the matching file in `docs/design/` in the same change.
