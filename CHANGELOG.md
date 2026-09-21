# Changelog

Version numbers follow the `## Version` field of `QuestTogether.toc`.

## Unreleased

### Fixed
- Presence announcements (`H`) are debounced: `GROUP_ROSTER_UPDATE` fires far more
  often than people join or leave, and every one of them used to send a message.
  A burst now costs one announcement (trailing edge, ~3 s window). `/qt ping` is
  still immediate.
- A presence announcement is now answered, after a short random delay, by every
  group member who has been quiet for the last ten seconds. A client whose peer list
  is empty — after a `/reload`, say — therefore fills `/qt status` and the popup back
  in within a few seconds, with nobody typing anything. Answering makes us not quiet,
  so clients cannot ping-pong announcements at each other. The wire format is
  unchanged.
- Quest IDs from another client are validated before use: `0`, negatives, fractions,
  `inf`/`NaN` and values above `2^31` are ignored instead of reaching the completion
  oracle or the peer cache — on inbound `Q`/`A` and on `/qt ask` alike. Zero was the
  sharp one: the oracle answers `false` for it rather than raising, so an unvalidated
  `0` broadcast a confident "not completed" for something that is not a quest.
- Peers are dropped when they leave the group (decision D2), so a cached answer can no
  longer outlive the group membership it came from. `/qt status` and the panel stop
  listing members who are gone. When the roster cannot be read at all, nobody is
  dropped — unknown is never "no", applied to the roster too.

### Documentation
- README now separates what works today from what is planned, and the Privacy
  section describes the actual behaviour (automatic presence announcements and
  automatic answers; no opt-out yet).
- PLAN.md documents the implemented revision-2 wire protocol; the batched protocol
  is marked as planned and renumbered to revision 3.
- PLAN.md: data model, UX spec and testing strategy marked as targets with
  "as built" notes; milestone checkboxes, R7, R11 and the M0 gate note corrected;
  `UI.lua` added to the module map and load order; broken anchors fixed.
- Added `docs/TESTING.md` (solo smoke test and the two-client M0 gate checklist).
- Stale source comments corrected (load order, auto-ask, retired probes).
- PLAN.md split by concern into `docs/ARCHITECTURE.md`, `PROTOCOL.md`, `UX.md`,
  `ROADMAP.md` and `MEASUREMENTS.md`; PLAN.md is now the index.

### Tooling
- `CLAUDE.md`, `.luacheckrc`, `.luarc.json`, `.gitignore`, `tools/linkcheck.py` and a
  GitHub Actions workflow running luacheck and the link check.
- LuaLS type annotations on the public `ns` API (comments only).

## 0.0.2

- Minimal status popup beside the quest frame (`UI.lua`), `/qt ui` to toggle it solo.
- Auto-ask: opening a quest asks the group about it, once per quest ID.
- Wire protocol revision 2: `H` / `Q` / `A`, with an "on it now" answer status.
- One-shot measurement probes (`/qt env`, `/qt probe`, `/qt log`, `/qt scan`) retired;
  their results are recorded in docs/MEASUREMENTS.md. `/qt events` and `/qt frames` remain.

## Earlier prototypes ("v0.1" in the design docs)

- Single-file prototype used to measure the WoW Forever client (API presence, the
  completion oracle, the `GetInfo` schema).
- Crashed once with `attempt to call a nil value`: `SafeStr` called `IsSecret` above
  its `local function` definition. Led to the split into modules that communicate
  through `ns` and only call each other at runtime.
- Repository hygiene from that period: the addon folder was renamed from
  `WowQuestAddon` to `QuestTogether` to match the `.toc` (the client silently skips
  an addon whose folder and `.toc` names differ), and the never-loaded stub
  `QuestWithFirends.toc` was deleted.
