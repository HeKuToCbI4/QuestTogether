# Changelog

Version numbers follow the `## Version` field of `QuestWithAFriend.toc`.

## Unreleased

### Fixed
- The popup no longer shows a stale answer. Re-opening a quest asks the group again
  (it used to ask once per quest ID and then trust the cache), and quests that are in
  progress or ready to turn in are asked about too, not only offered ones. Your own
  line now says `on it now` when the quest is in your log.
- `/qt` no longer prints every answer twice. Answers print live; after 3 seconds only
  the members who did *not* answer are listed, and nothing at all if everybody did.
- A group member whose name contains a space is now matched correctly. The live
  answer used to be followed by a summary saying `?  (no addon heard from)`, and the
  peer was dropped on every roster change: the roster spells such a name
  `First-Last`, which was read as `Name-Realm`. Peer keys no longer depend on where
  a name is split (#24). New probe `/qt roster` prints the spellings the client uses.

### Measured on the live client (2026-09-21)
- The addon loads from `_classic_beta_\Interface\AddOns\` — install instructions in the
  README are now definite (Q2 closed).
- `SendAddonMessage` returns a numeric result code here (`5` = `NotInGroup` when solo),
  which `ns.Send` already reads as a failure. `LE_PARTY_CATEGORY_INSTANCE` exists (`2`).
- New probe `/qt realm`: `/dump` prints nothing on this client, so the realm APIs that
  peer keys depend on are measured by our own command instead.

### Changed
- Auto-ask (opening a quest) is now silent: the popup shows the answers, so chat no
  longer repeats them with an "Asking your group…" line, a line per answer and a
  summary three seconds later. `/qt` and `/qt ask <id>` still report in chat.
- `/qt help` is built from what each module registers for its own commands, and its
  version header is read from the `.toc` instead of being hard-coded.
- The addon is renamed to **Quest With A Friend**. The folder, the `.toc` filename and
  `## Title` move together (the client silently skips an addon whose folder and `.toc`
  differ), and `SavedVariables` becomes `QuestWithAFriendDB` (v0.0.2 saved nothing, so
  no data is lost). The wire prefix `QTOG` and the `/qt` command are unchanged.

### Fixed
- Every member of your group is now listed, whether or not they run Quest With A Friend.
  The popup and the `/qt` summary are driven by the group roster instead of "peers we
  have heard from", so a member without the addon reads `?  (no addon heard from)`
  rather than being silently absent. Grouped-but-nobody-has-it now says "None of your
  group has Quest With A Friend." instead of the false "(not in a group)". When the roster
  cannot be read at all, the old list is shown — an unreadable roster is unknown, not
  empty, and nothing is ever invented as a "no".
- Peers are identified by their full `Name-Realm` instead of the bare character name.
  Two group members with the same name on different realms no longer share one entry
  (which could show one member's answer as the other's), and a cross-realm character
  with your own name is no longer ignored as "you". The key is built in one place
  (`ns.PeerKey`) and used by the registry, the roster walk and pruning alike. If the
  client cannot report the realm, keys fall back to the bare name as before.
- A group member who joins after a quest was opened is asked about it: the auto-ask
  dedupe is cleared on every roster change, instead of remembering one quest ID
  forever. Previously the newcomer stayed `?` until someone typed `/qt`.
- Asking about several quests in quick succession no longer prints stale summaries
  or swallows live answer lines: asks are tracked per quest ID, with one reply timer
  each, instead of a single "current ask".
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
- Instance (LFG) groups: addon messages now go to `INSTANCE_CHAT` instead of `PARTY`,
  where they reached nobody. The category constant this depends on has **not been
  verified on this client**, so the lookup is guarded — when it is missing, behaviour
  is unchanged. `/qt channel` is a new solo probe that measures it.
- A refused send is no longer reported as a successful ask. `ns.Send` now reads what
  `SendAddonMessage` returns instead of assuming that "it did not throw" means "it was
  sent", so `/qt ask` says `Cannot ask: send refused` and does not start the 3-second
  summary timer for a question nobody was asked. The client's return convention is
  still unmeasured, so the reading is deliberately conservative: only an explicit
  `false` or a non-zero result code counts as failure — `true`, `0` and anything
  unrecognised stay success, because a wrong guess here would break working sends.
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

### Internal
- Load-time wrap chains replaced with registries declared in `Compat.lua`:
  `ns.OnAnswer(fn)` for answer listeners (each called inside its own `pcall`) and
  `ns.AddHelp(cmd, text)` for help lines. No file but `Compat.lua` needs a
  particular position in the `.toc` any more.
- `Diagnostics.lua` is now genuinely deletable — `/qt help` moved to `Commands.lua`,
  and the two probes register their own help lines.
- New `Query.lua` owns `ns.Ask` and the pending asks; the unused `ns.namespaces`
  table was removed.

### Tooling
- Offline test suite in `tests/`, run with `lua5.1 tests/run.lua` and in CI. It fakes
  the client, loads the real modules in `.toc` order and covers the wire format, the
  tri-state invariant, the answering rules and hostile input. Stock Lua only — no
  luarocks, no busted. To make it possible, the receive path was split into a pure
  `ns.ParseMessage` and a thin dispatcher; behaviour is unchanged.
- New probe `/qt sendtest`: calls the raw send API with a presence payload and prints
  every value it returns, with the count and each type, plus
  `Enum.SendAddonMessageResult` if that table exists. Run it solo and grouped to settle
  the return convention and to look for a throttle (Q4).
- `CLAUDE.md`, `.luacheckrc`, `.luarc.json`, `.gitignore`, `tools/linkcheck.py` and a
  GitHub Actions workflow running luacheck, the test suite and the link check.
- Tag-driven GitHub releases: `.pkgmeta` plus a BigWigs-packager workflow
  (`.github/workflows/release.yml`) packages a zip of just the addon and attaches it to
  a GitHub release on every pushed tag. Zip-only for now — CurseForge upload is stubbed
  out for M5.
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
