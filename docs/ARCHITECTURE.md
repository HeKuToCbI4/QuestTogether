# Architecture

Why the addon is shaped the way it is: premise, constraints, decisions, data model, non-goals.

> Part of the Quest Together design docs — index: [`PLAN.md`](../PLAN.md). Sections are
> marked **Implemented**, **Partially implemented** or **Planned**; for current
> behaviour the code is authoritative.

---

## Executive summary

### Premise

> **Every participant installs the addon.**

This is the starting assumption of the design, not a limitation discovered along the
way. It follows directly from [C1](#hard-constraints): quest state is server-side
and is never sent to other clients, so there is no query to run against a groupmate.
Each client answers questions about its own character instead, over addon-to-addon
messages.

Everything below is designed inside that premise.

**What the premise does not eliminate.** A peer can still be *silent* — not running
the addon, running an incompatible revision, or simply not answering within the
timeout. The **unknown** state therefore remains a first-class part of the model, and
must never be rendered as "not completed". A false ✗ sends two players on a quest one
of them has already finished, which is the exact failure this addon exists to prevent.

### Verdict

| Aspect | Assessment |
|---|---|
| Technically feasible | **Yes**, via peer-to-peer addon messaging |
| Requires the addon on every participant | **Yes — by design.** Stated as the [premise](#premise), not treated as a defect |
| Depends on unavailable API | No — all required APIs are current and public |
| Killed by Forever's addon restrictions | **Probably not** — quest data is not combat data — but **unverified** |
| Hardest part | Not the protocol. The UI integration points and the unknown-state honesty |
| Estimated effort | ~9–11 focused days to a polished v1 |

---

## Problem statement

Two friends group up to quest together in a Classic-content world.

Player A picks up a quest. Player B has already completed it — perhaps months ago,
perhaps on this same character. Neither player can tell. The default UI shows
nothing about a groupmate's quest history. There is no query, no UI affordance, and
no addon that solves it, because the underlying data is not present client-side.

The result is a recurring, low-grade social friction:

- Wasted time running content one player has already finished.
- Awkwardness when someone has to *say* "I've already done this one" — which
  requires remembering, and remembering is unreliable.
- Group leaders guessing at who needs what when assembling a run.

The information exists on the server. It simply isn't shared with clients. Quest
Together's entire purpose is to route it the one way it can travel: voluntarily,
player to player.

---

## Hard constraints

These are not implementation choices. They are the shape of the problem.

| # | Constraint | Consequence for the design |
|---|---|---|
| C1 | **No API exposes another player's quest state.** Not in any client flavor, current or historical. | Peer-to-peer only. Every participant installs the addon — this is the [premise](#premise), not a gap to be worked around. |
| C2 | **Addon messages are group-only.** You cannot whisper an addon payload to an arbitrary player. | The feature works exactly where it's most useful — inside a party. Also: no cross-group or guild-wide sync in v1. |
| C3 | **Addon messages are throttled and size-capped.** Payloads are on the order of a couple hundred bytes, and the server rate-limits sends. | Rules out "just broadcast everyone's entire quest history." Forces an on-demand query model with a real send queue. |
| C4 | **There are thousands of quests.** A full completion set is far too large to ship eagerly on every join. | On-demand queries for the completion set; eager sync only for the small active-log set. |
| C5 | **Absence of an answer is ambiguous.** No reply could mean "not completed", "no addon", or "out of date". | The UI must render *unknown* distinctly from *not completed*. This is a core correctness requirement, not a polish item. |
| C6 | **Forever inherits Midnight's "secret values" restrictions.** | Quest data is believed unaffected. **Must be verified in M0** — see [R2](ROADMAP.md#risk-register). |
| C7 | **Quest IDs are per-flavor.** Era/Cata/Retail IDs for the "same" quest differ. | Store IDs, never assume cross-flavor portability. Display names come from the client, never from our data. |

### Design principle that falls out of C5

> **Unknown is a first-class state.** Every piece of state in the model is
> tri-valued: `true` / `false` / `nil`-meaning-unknown. Any code path that
> collapses `nil` into `false` is a bug, and the UI must make the distinction
> visually obvious at a glance.

### "Why not just…?" — alternatives considered and rejected

| Alternative | Why not |
|---|---|
| Query the achievements API | Quest completion and achievement criteria do not map cleanly; coverage is partial and inconsistent. Rejected. |
| Parse the combat log / chat for quest turn-ins | Only reveals events that happen while you're grouped and nearby. Useless for history. |
| Use the built-in quest *share* feature | Tells you what someone is currently on, requires them to manually share, and says nothing about history. |
| Broadcast everyone's full completion set on join | Violates C3/C4: thousands of IDs, massive message burst, heavy throttle. This is the fork we explicitly rejected in favour of on-demand. |
| **Cache completed quests in a local database** | **The client already is that database**, completely and for free, back to character creation. A local list is a strict subset, a drift risk, and a source of false negatives. Rejected in detail [below](#why-there-is-no-local-completed-quest-database). |
| A central server / web API | Non-starter. Blizzard addons cannot make arbitrary outbound network requests, and the whole point is in-game immediacy. |

---

## Architecture

### Component overview

```
┌──────────────────────── Player A (client) ────────────────────────┐
│                                                                   │
│   ┌──────────────┐   ┌───────────────┐   ┌────────────────────┐   │
│   │  UI Layer    │   │  Data Layer   │   │  Transport Layer   │   │
│   │              │   │               │   │                    │   │
│   │ QuestFrame   │◄──┤ QuestCache    │◄──┤ Receive queue      │   │
│   │ Quest log    │   │  peers[guid]  │   │  (CHAT_MSG_ADDON)  │   │
│   │ Gossip list  │   │  .completed{} │   │                    │   │
│   │ Status panel │   │  .log{}       │   │ Send queue         │   │
│   │              │   │  .known       │   │  (throttled,       │   │
│   └──────┬───────┘   └──────┬────────┘   │   coalesced)       │   │
│          │                  │            └─────────┬──────────┘   │
│          │           ┌──────▼────────┐             │              │
│          │           │ LocalOracle   │             │              │
│          │           │  (always      │             │              │
│          │           │   authoritative            │              │
│          │           │   about self) │             │              │
│          │           └───────────────┘             │              │
└──────────┼──────────────────────────────────────────┼─────────────┘
           │                                          │
           │                             addon messages, PARTY/RAID
           │                                          │
                 ┌────────────────────────────────────┐
                 │      Blizzard group channel        │
                 │      (prefix: QTOG)                │
                 └────────────────────────────────────┘
                                   │
┌──────────────────────── Player B (client) ────────────────────────┐
│                     … identical addon …                           │
└───────────────────────────────────────────────────────────────────┘
```

### Module map

How the components above map onto files. One concern per file, so that uncertainty in
one area cannot ripple into another.

| File | Component | Owns |
|---|---|---|
| `Compat.lua` | Client interface | API resolution, `IsSecret`, `SafeStr`, `SafeIsDone`, `LocalQuestID`, `GroupChannel` |
| `Peers.lua` | Data layer | The `peers` registry and `RecordAnswer` — **home of the tri-state invariant** |
| `Protocol.lua` | Transport layer | `PREFIX`, message grammar, `Send`, `HandleAddonMessage`, prefix registration |
| `Commands.lua` | UI layer (text) | `ns.Ask`, `/qt ask`, `/qt ping`, `/qt status` |
| `Diagnostics.lua` | — | Solo verification commands, and (for now) `/qt help`. **Almost deletable** — see below. |
| `UI.lua` | UI layer (panel) | The status popup, quest-frame show/hide hook, auto-ask on `QUEST_DETAIL` |
| `Core.lua` | Wiring | Bootstrap, event frame, slash dispatch |

Load order is `Compat → Peers → Protocol → Commands → Diagnostics → UI → Core`, as
listed in the `.toc`.

The component diagram above is the **target**. Not yet built: the send queue,
throttling and coalescing (`ns.Send` is a direct call), the `.log{}` peer dataset,
and every UI surface except the status panel.

Two boundaries are deliberate and worth preserving as this grows:

- **Transport knows nothing about quests** ([D4](#key-architectural-decisions)). It moves
  opaque payloads and enforces the rules; meaning lives above it.
- **Diagnostics is disposable.** It owns its own event frame and registers into the
  shared `ns.commands` table, so deleting the file removes all dev tooling and touches
  nothing else. If `Core.lua` ever grows a reference to `ns.tracing`, that property is
  broken and the file becomes permanent.
  **Currently violated in one place:** `/qt help` for *every* command is defined in
  `Diagnostics.lua`, and `UI.lua` wraps it. Deleting the file today leaves a help
  command that lists only `/qt ui`. Move the help text out first.

**The split also retires a bug class.** v0.1 crashed because `SafeStr` called
`IsSecret` before it was defined — `local function` does not hoist, so the name
resolved as a *global* and returned `nil`. Modules now communicate through `ns` and
only call across boundaries at runtime, so there is no cross-file definition-order
trap to fall into. The single rule that keeps this true: **never call across modules
at load time.**

**Known soft spot.** `UI.lua` *reads* `ns.onAnswer` and `ns.commands.help` at load
time to wrap them. It does not call them, so the rule holds to the letter — but the
wraps silently do nothing if `UI.lua` is ever listed before `Commands.lua` or
`Diagnostics.lua`. The file order is load-bearing there until the wrap chains are
replaced with registries.

### Key architectural decisions

**D1 — Self is always authoritative and never cached.**
The local player's completion state is answered live from the client every time.
We never store "am I done with X" — the client already knows, and a cache would
only create a way for our state to drift from the truth.

**D2 — Peers are cached, but only within a continuous group membership.**
A cache entry survives only while that peer stays in the group. They may have
completed quests since; on roster change, their entry is dropped and re-established.
This bounds staleness to "within one continuous group session" — a period during
which completing quests the *other* player already looked up is a narrow edge case.

**D3 — Two datasets, two sync strategies.**

| Dataset | Size | Strategy | Rationale |
|---|---|---|---|
| Completed quests | thousands | **On-demand** — answered per query | C3/C4. Most quests are never asked about. |
| Active quest log | ~25 | **Eager** — broadcast on change | Tiny. And it powers "who's already on it" for free. |

This split is the central efficiency idea of the design. The expensive set is
queried narrowly; the cheap set is synced broadly.

**D4 — The Transport layer knows nothing about quests.**
It moves opaque payloads and enforces throttling. This keeps the protocol
testable in isolation and makes the revision/versioning story tractable.

**D5 — No hard hooks into Blizzard frames in v1.**
The Forever UI is Mainline-derived and such frames are famously unstable across
patches. v1 leads with a standalone panel plus tooltip augmentation; inline
decoration of the quest frame is a later, isolated, defensively-written feature.
*As built (v0.0.2):* the panel anchors beside `QuestFrame` and uses
`HookScript("OnShow"/"OnHide")` when that global exists. That is a soft,
existence-guarded hook on the frame's name only — nothing inside the frame is
touched — and `/qt ui` is the fallback if the name changes ([Q5](MEASUREMENTS.md#open-questions)).

### Why there is no local completed-quest database

This is the most tempting wrong turn in the design, so it is worth killing explicitly.

The intuition is: "keep a list of completed quest IDs on disk, populate it lazily,
and answer from it — because the addon might have been installed *after* I completed
a quest, so it won't know about the older ones."

**The premise is false, and it is the reason not to build the database.**

The client already holds a complete record of the local player's quest completions.
`C_QuestLog.IsQuestFlaggedCompleted(questID)` resolves any quest ID instantly —
including quests completed years before the addon was installed. The client has
known since the character was created. There is no cold-start problem to solve.

A locally-built list can therefore only ever contain completions the addon personally
*observed*. Populating it fully would require brute-force scanning the quest ID space
or waiting for quests to be asked about. Either way it is a **strict subset** of what
the client already provides, immediately, at zero cost.

The costs are real, though:

| Cost | Detail |
|---|---|
| Drift | Two sources of truth that can disagree |
| Staleness | Cache says "not done" for a quest completed since the last write |
| Migration burden | A schema to version and migrate across releases |
| Disk I/O | Writing on every turn-in |
| **False negatives** | Any code path trusting the cache over the oracle emits a wrong ✗ |

That last row is disqualifying. The entire design exists to avoid confident wrong
answers — see [C5](#hard-constraints). A redundant cache is a mechanism for
manufacturing exactly the failure we are built to prevent.

**The one legitimate use of a local database** is metadata the client does *not*
expose: **when** a quest was completed. `IsQuestFlaggedCompleted` is a boolean with
no timestamp, so "Ana finished this three months ago" is not answerable from the
client. Recording that would require our own append-only log — which, note, could
only ever capture completions occurring while the addon was installed. That is a
defensible future feature and an explicit [non-goal](#non-goals) for v1.

**Conclusion:** the local client *is* the database. We query it, we don't shadow it.

---

## Data model

> **Status: Planned**, except where "As built" says otherwise. The second table below
> is the v1 target.

### As built (v0.0.2)

```lua
QuestTogetherDB = {}          -- SavedVariable; created empty, nothing reads it yet

ns.peers = {                  -- session-scoped, in Peers.lua
  ["Name-Realm"] = {          -- key: full normalised Name-Realm -- ns.PeerKey, see Q7
    name       = "Name",                -- display name; "Name-Realm" cross-realm
    compatible = true,                  -- protocol revision matched ours
    lastSeen   = 0,                     -- time() of the last message
    answered   = { [questID] = true },  -- true / false; absent key == UNKNOWN
    onIt       = { [questID] = true },  -- set only alongside answered == false
  },
}
```

Differences from the target that matter: there are **no settings** (so no privacy
toggles), peers are keyed by name-realm rather than GUID, and there is no `log` dataset
and no `pending` table. The key is built in exactly one place, `ns.PeerKey` in
`Compat.lua`, and `ns.GroupMembers` builds roster keys the same way — two key rules
would silently split the registry in half. A sender that arrives without a realm is
on our realm, so the player's own normalised realm is appended; if the client cannot
report it the key falls back to the bare name. Entries *are* dropped when a peer leaves the group — `ns.PrunePeers`
on every roster change — so [D2](#key-architectural-decisions) holds for the leaving half
of the case. A peer who completes quests *while still in the group* is still cached
until they leave.

### Target (v1)

```lua
QuestTogether = {
  version  = 1,              -- schema version, for SavedVariables migration
  settings = {
    enabled        = true,
    answerQueries  = true,   -- privacy toggle: respond to QREQ
    shareQuestLog  = true,   -- privacy toggle: broadcast LOGS
    showUnknown    = true,   -- render the ? state at all
  },
}

-- Session-scoped peer state. NOT persisted across sessions by design — see D2.
QuestTogether.session = {
  peers = {
    [guid] = {
      name       = "Name-Realm",
      revision   = 1,
      compatible = true,
      lastSeen   = 0,
      completed  = { [questID] = true },  -- absent key == UNKNOWN, not false
      log        = { [questID] = true },  -- currently in their quest log
      pending    = { [seq] = { ids = {...}, expires = t } },
    },
  },
}
```

### Storage

Addons cannot write arbitrary files. There is no `txt` or `json` output available —
the only persistence mechanism is **`SavedVariables`**, declared in the `.toc` and
serialised by the client into a Lua file under `WTF/`:

```
## SavedVariables: QuestTogetherDB
```

Two properties of `SavedVariables` shape what they can be used for:

1. **They are flushed on logout and `/reload`, not continuously.** They are not a
   live data store, and must never be on a hot path that expects a fresh read.
2. **They survive across sessions, therefore they go stale.** A timestamp written
   last week describes a world that has moved on.

**What we persist:** settings only.

**What we do not persist: peer data.** A peer's completion state cached from a
previous session may have been invalidated by anything they did since — and we would
have no way to know. Presenting that alongside a live answer, with the same visual
weight, would violate the tri-state contract in the worst possible direction: a
confident wrong answer rather than an honest unknown.

If peer persistence is ever added, it must be **visually degraded** — rendered as
"last confirmed *date*" rather than a bare ✓ — and re-verified on first contact with
that peer. [D2](#key-architectural-decisions)'s session-scoped cache is the
deliberate alternative: bounded staleness in exchange for no migration burden and no
silent drift.

### The tri-state contract

`completed[questID]` has exactly three meaningful readings:

| Value | Meaning | UI |
|---|---|---|
| `true` | Confirmed completed | ✓ |
| `false` | Confirmed **not** completed | ✗ |
| `nil` (absent) | No data — no addon, outdated, or not yet answered | `?` |

**A `false` is only ever written from an actual received bitmask.** No code path
defaults an absent key to `false`. This is enforced by keeping the write in exactly
one function — `ns.RecordAnswer` in `Peers.lua` (this plan originally called it
`Cache.applyReply`). An explicit unit test for the invariant is **planned**
([testing strategy](ROADMAP.md#testing-strategy)); no automated tests exist yet.

---

## Non-goals

Explicitly out of scope, to protect the schedule:

- **Not a quest guide.** No coordinates, no routing, no TomTom integration in v1.
  Questie owns this space; we annotate, we don't navigate.
- **Not automation.** The addon never accepts, completes, or turns in a quest.
- **Not a stranger-lookup tool.** Group-only by design, and by Blizzard's design.
- **No central server, no telemetry, no analytics.** There is no backend.
- **No cross-flavor data portability.** Quest IDs do not transfer between clients.
- **No guild-wide or cross-realm-history sync in v1.**
- **No completion timestamps in v1.** Recording *when* a quest was completed would
  justify a local append-only log, since the client exposes only a boolean. It is
  the one defensible use of local storage — but it can only ever capture completions
  occurring while the addon was installed, and it is not needed for any v1 feature.
- **No prerequisite/eligibility detection.** The client exposes no API for whether
  a quest is *available* to a player — measured 2026-09-21: `C_QuestInfoSystem`
  exists but holds only reward functions, and `GetQuestAvailability`/`IsQuestAvailable`
  are absent. Prerequisite data lives server-side. The one route to "friend is not
  eligible (missing prerequisite)" is a static quest database — [Grail](https://www.curseforge.com/wow/addons/grail)
  bundles exactly this and is a possible future dependency, deferred until it
  covers WoW Forever's quest set.
