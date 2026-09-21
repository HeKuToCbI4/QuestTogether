# CLAUDE.md

World of Warcraft addon (Lua 5.1 dialect, WoW Forever client). It shows which group
members have already completed a quest, by having each client answer for its own
character over group-only addon messages. Status: v0.0.2 prototype.

## Rules that must never be broken

1. **Unknown is never "no".** Completion state is tri-valued: `true` / `false` /
   `nil` = unknown. Never write `x or false`, `not not x`, or a default of `false`
   for a peer's answer or for `ns.SafeIsDone`. A false "no" is the one failure this
   addon exists to prevent.
2. **One writer.** `ns.RecordAnswer` (`Peers.lua`) is the only function that writes
   `peer.answered` / `peer.onIt`, and only from a message actually received.
3. **Never call across modules at load time.** Files share the `ns` table. Defining
   `ns.X` at load is fine; *calling* another module's `ns.Y` at file scope is not —
   it makes `.toc` order load-bearing and fails at runtime, not at load.
   The one exception: registering into the lists `Compat.lua` declares
   (`ns.OnAnswer`, `ns.AddHelp`, `ns.commands`). `Compat.lua` is first in the
   `.toc`, so those exist before anyone registers, and a registration appends a
   value rather than running another module's behaviour.
4. **Branch on API presence, never on client version.** This client reports
   `1.60.1` but has the modern `C_*` API and no legacy globals. All client API
   access goes through `Compat.lua` (`ns.api`, `ns.Safe*`).
5. **Everything from another client is hostile input.** `HandleAddonMessage` runs
   under `pcall`; validate every field before use. Values from quest/unit APIs may
   be "secret" — check with `ns.IsSecret` before comparing or concatenating.
6. **`Protocol.lua` knows nothing about quests or presentation**; `Core.lua` stays
   thin wiring; `Diagnostics.lua` must stay deletable (nothing may depend on it).
7. **A wire-format change bumps `ns.PROTOCOL`** and updates `docs/PROTOCOL.md` in the
   same change.

## Project gate

Milestone M0 is **not closed**: no addon message has yet crossed between two real
clients. Do not build new features until it is — bug fixes, tooling and docs only.
See `docs/ROADMAP.md` and the checklist in `docs/TESTING.md` §B.

## Where things are

| Need | Read |
|---|---|
| Module responsibilities, load order | `README.md` → "For developers" |
| Why a decision was made (C1–C7, D1–D5) | `docs/ARCHITECTURE.md` |
| Wire format — rev 2 is built, rev 3 is only planned | `docs/PROTOCOL.md` |
| Milestones (M\*), risks (R\*) | `docs/ROADMAP.md` |
| What was *measured* on the live client; open questions (Q\*) | `docs/MEASUREMENTS.md` |
| Manual test checklists | `docs/TESTING.md` |

Load order (`QuestTogether.toc`): `Compat → Peers → Protocol → Query → Commands →
Diagnostics → UI → Core`. Only `Compat` has to be first (it declares the
registries); the rest may be reordered or deleted freely.

The design docs describe a **target**. Sections are tagged *Implemented* / *Planned*.
When docs and code disagree about current behaviour, the code wins — then fix the doc.

## Checking your work

You cannot run the addon — there is no WoW client here — but the pure parts run
offline.

```bash
lua5.1 tests/run.lua         # offline test suite; stock Lua, no dependencies
luacheck .                   # static analysis; config in .luacheckrc
python tools/linkcheck.py    # markdown links and #anchors
```

All three run in CI (`.github/workflows/lint.yml`). If `lua5.1` or `luacheck` is
not installed locally, say so rather than claiming the check passed. `luac -p` is
*not* a substitute for `luacheck`: it cannot see the forward-reference bug class
(see R11 in the roadmap).

The suite fakes the client (`tests/harness.lua`) and loads the real modules in
`.toc` order, so it covers the wire format, the tri-state invariant and hostile
input — but not the client itself. It cannot tell you an API exists.

Anything behavioural needs a human in the game. When you change behaviour, name the
rows of `docs/TESTING.md` that must be re-run, and add rows for new behaviour.

## Pull requests

- Fill in `.github/pull_request_template.md`. Plain English, short bullets, no walls
  of text.
- Request review from `HeKuToCbI4` (`gh pr create --reviewer HeKuToCbI4`).
- If the PR is for an issue, mention it (`Closes #N` / `Refs #N`).

## Conventions

- 4-space indent; keep each file's header comment accurate — it is the module's spec.
- Public functions live on `ns` and carry LuaLS annotations (`---@param`,
  `---@return`). Shared types (`QT.Peer`, `QT.Namespace`, `QT.AnswerStatus`) are
  declared at the top of `Compat.lua`. Spell the tri-state as `boolean?`.
- Read WoW globals as `_G.Name` or via `ns.api`, guarded for absence. A new global
  must be added to `.luacheckrc`.
- Facts about the client are **measured, not inferred**: record how and when in
  `docs/MEASUREMENTS.md`. Your training data does not cover this client — do not
  assume an API exists or behaves as on Retail/Classic; ask for a `/qt` probe instead.
- User-facing changes get a line in `CHANGELOG.md`. The version lives in the `.toc`.
