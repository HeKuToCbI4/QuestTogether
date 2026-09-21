# Quest Together — Design & Implementation Plan

**Target client:** WoW Forever (Mainline-derived UI architecture)
**Document status:** Draft v2 — 2026-09-21 (synced with the v0.0.2 code)
**Companion:** [`README.md`](README.md) · [`docs/TESTING.md`](docs/TESTING.md) · [`CHANGELOG.md`](CHANGELOG.md)

> **How to read this document.** It is mostly a *design target*, not a description
> of the code. Sections are marked **Implemented**, **Partially implemented** or
> **Planned**. For current behaviour the code is authoritative.
>
> **Version names.** The shipped addon is `0.0.2` (see the `.toc`). "v0.1" in the
> measurement log below refers to the first single-file prototype, before the code
> was split into modules. "v0.2" means the next planned release. "v1" is the polished
> target this plan describes.

---

## Contents

1. [Executive summary](#1-executive-summary)
2. [Problem statement](#2-problem-statement)
3. [Hard constraints](#3-hard-constraints)
4. [Architecture](#4-architecture)
5. [Wire protocol](#5-wire-protocol)
6. [Data model](#6-data-model)
7. [UX specification](#7-ux-specification)
8. [Milestones](#8-milestones)
9. [Non-goals](#9-non-goals)
10. [Risk register](#10-risk-register)
11. [Testing strategy](#11-testing-strategy)
12. [Open questions](#12-open-questions)
13. [Appendix: API cheat sheet](#13-appendix-api-cheat-sheet)

---

## 1. Executive summary

### Premise

> **Every participant installs the addon.**

This is the starting assumption of the design, not a limitation discovered along the
way. It follows directly from [C1](#3-hard-constraints): quest state is server-side
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

## 2. Problem statement

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

## 3. Hard constraints

These are not implementation choices. They are the shape of the problem.

| # | Constraint | Consequence for the design |
|---|---|---|
| C1 | **No API exposes another player's quest state.** Not in any client flavor, current or historical. | Peer-to-peer only. Every participant installs the addon — this is the [premise](#premise), not a gap to be worked around. |
| C2 | **Addon messages are group-only.** You cannot whisper an addon payload to an arbitrary player. | The feature works exactly where it's most useful — inside a party. Also: no cross-group or guild-wide sync in v1. |
| C3 | **Addon messages are throttled and size-capped.** Payloads are on the order of a couple hundred bytes, and the server rate-limits sends. | Rules out "just broadcast everyone's entire quest history." Forces an on-demand query model with a real send queue. |
| C4 | **There are thousands of quests.** A full completion set is far too large to ship eagerly on every join. | On-demand queries for the completion set; eager sync only for the small active-log set. |
| C5 | **Absence of an answer is ambiguous.** No reply could mean "not completed", "no addon", or "out of date". | The UI must render *unknown* distinctly from *not completed*. This is a core correctness requirement, not a polish item. |
| C6 | **Forever inherits Midnight's "secret values" restrictions.** | Quest data is believed unaffected. **Must be verified in M0** — see [R2](#10-risk-register). |
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
| **Cache completed quests in a local database** | **The client already is that database**, completely and for free, back to character creation. A local list is a strict subset, a drift risk, and a source of false negatives. Rejected in detail in [§4](#why-there-is-no-local-completed-quest-database). |
| A central server / web API | Non-starter. Blizzard addons cannot make arbitrary outbound network requests, and the whole point is in-game immediacy. |

---

## 4. Architecture

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
touched — and `/qt ui` is the fallback if the name changes ([Q5](#open-questions)).

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
answers — see [C5](#3-hard-constraints). A redundant cache is a mechanism for
manufacturing exactly the failure we are built to prevent.

**The one legitimate use of a local database** is metadata the client does *not*
expose: **when** a quest was completed. `IsQuestFlaggedCompleted` is a boolean with
no timestamp, so "Ana finished this three months ago" is not answerable from the
client. Recording that would require our own append-only log — which, note, could
only ever capture completions occurring while the addon was installed. That is a
defensible future feature and an explicit [non-goal](#9-non-goals) for v1.

**Conclusion:** the local client *is* the database. We query it, we don't shadow it.

---

## 5. Wire protocol

### Transport — *Implemented*

- **Prefix:** `QTOG`, registered once via `C_ChatInfo.RegisterAddonMessagePrefix`.
- **Channel:** `"PARTY"` when in a party, `"RAID"` when in a raid. Replies go back
  on the channel the request arrived on. (`"INSTANCE_CHAT"` for instance groups is
  not handled yet.)
- **Payload:** ASCII, `|`-delimited fields, first field is the protocol revision.
- **Maximum:** inbound payloads over 200 characters are dropped unparsed.

### Revision 2 — the current protocol — *Implemented (v0.0.2)*

This is what `Protocol.lua` speaks today. It is deliberately minimal, so that the
first two-client test has as little in it to go wrong as possible.

| Message | Direction | Meaning |
|---|---|---|
| `2\|H` | broadcast | Presence announcement. Sent on `PLAYER_ENTERING_WORLD` and on every `GROUP_ROSTER_UPDATE` while grouped, and by `/qt ping`. **Not replied to.** |
| `2\|Q\|<questID>` | broadcast | "Have you completed this quest?" One quest per message. |
| `2\|A\|<questID>\|<status>` | broadcast | Answer. `status`: `0` = not completed, `1` = completed, `2` = not completed but in my log right now ("on it"). |

Behaviour that is part of the contract:

- **Every inbound message marks its sender as a peer**, whatever its type. A message
  whose first field is not `2` marks the peer *incompatible* and is otherwise ignored:
  not parsed, not answered.
- **A peer that cannot answer stays silent.** If the completion oracle returns
  anything but a plain boolean, no `A` is sent and the asker keeps showing `?`.
- **Answers are broadcast and everyone records them**, including members who did not
  ask (see [below](#the-channel-is-a-broadcast-medium-a-free-optimisation)). There is
  no `seq`; an answer is correlated by quest ID alone.
- **The asker waits `REPLY_WINDOW` = 3 s** and then prints a summary. Peers that have
  not answered are reported as `?`, never as "no".
- **Peers are keyed by bare character name** (realm stripped). This collides for two
  same-named characters from different realms and is tracked as a bug ([Q7](#open-questions)).

Not in revision 2: batching, `seq` correlation, throttling, coalescing, quest-log
sync, and any reply to `H`.

### Revision 3 — the batched protocol — *Planned*

Everything from here to the end of "Throttling" describes the **target** protocol. It
was originally drafted as "revision 1", before the minimal protocol above took
revision 2; it will ship as **revision 3**, and the examples below are numbered
accordingly. None of it is implemented.

#### Message grammar

```
<rev>|<TYPE>|<field>|<field>|…
```

#### Message types

| Type | Direction | Payload | Purpose |
|---|---|---|---|
| `HELLO` | broadcast | `3\|HELLO\|<rev>` | Announce presence. Sent on join and in reply to an unknown peer. |
| `LOGS` | broadcast | `3\|LOGS\|<count>\|<packed>` | Full active quest log (delta-packed IDs; **headers excluded**, `questID > 0` only). Sent on change, debounced. |
| `QREQ` | → peers | `3\|QREQ\|<seq>\|<count>\|<packed>` | "Have you completed these?" |
| `QREP` | ← peer | `3\|QREP\|<seq>\|<count>\|<mask>` | Bitmask reply over the request's ID order. |

#### Encoding

Two packing primitives, both built on a 6-bit alphabet chosen to avoid every
character that is meaningful to the chat layer or our delimiter:

```
alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
```

**`packBits(bitstring)`** — take the bitstring MSB-first, emit one alphabet
character per 6 bits, zero-padding the final group.

**`packIDs(sortedIDs)`** — delta-encode the sorted ID list as 7-bit varints
(continuation-bit style), concatenate the bitstream, then `packBits`. Deltas are
small and clusters dense, so real-world compression is excellent.

**Worked sizing.** A typical NPC offering 8 quests. Note that observed IDs run at
least to the 92 000s (`92460` was probed on the live client), so budget five digits
per ID rather than assuming a small range:

| Message | Content | Approx. size |
|---|---|---|
| `QREQ` | 8 delta-packed IDs + seq + count | ~20 chars |
| `QREP` | 8-bit mask + count | ~4 chars |

Even an atypically large batch of 40 quests stays near 100 characters — comfortably
inside budget.

#### Sequencing and correlation

- `seq` is a wrapping `0–255` counter, monotonically increasing per sender.
- A `QREP` is matched to its originating `QREQ` by `seq`. Replies with an unknown
  or already-completed `seq` are discarded.
- Each in-flight request carries a **3-second timeout**. On expiry, unresolved
  peers are marked **unknown** for those quests, *not* "not completed" (see C5).

#### Throttling

A single send queue governs all outbound traffic:

- Maximum **4 messages per second**, measured over a sliding window.
- **Coalescing:** requests for the same peer set arriving within a **250 ms**
  window are merged into one `QREQ`. This matters because the natural user
  behaviour — clicking through several quests quickly — would otherwise produce a
  burst of near-identical requests.
- Dropped or deferred messages are logged at debug level, never silently discarded
  without a trace.

### The channel is a broadcast medium (a free optimisation)

Addon messages are not point-to-point. A `QREQ` sent to `"PARTY"` is delivered to
every member, and **so is every `QREP` in response to it.**

This has a valuable consequence: when A asks about a quest and B answers, C and D
also receive B's answer. Adjacent peers therefore populate their caches *passively*,
as a side effect of traffic they were not the author of.

**Cost implication:** an N-member party converges on complete mutual knowledge in
**N messages, not N²**. No extra code is required to achieve this — only the
discipline not to discard a reply just because its `seq` does not match a request
*we* originated. Replies are matched against the request they answer, whoever sent
that request.

### Sync state, not events

A design principle this protocol follows everywhere:

> **Broadcast state snapshots; do not broadcast event streams.**

The tempting alternative to `LOGS` is "tell the group when I accept a quest." It is
strictly worse, for a reason unrelated to bandwidth: **events are lossy.**

- A peer joins the group mid-session and never sees the events that already fired.
- A message dropped under throttle is gone permanently; the divergence never heals.
- Reconnect, reload, or a missed `QUEST_LOG_UPDATE` silently desynchronises a peer's
  view forever, with no signal that anything is wrong.

A state snapshot is **self-healing**. Miss one, and the next one corrects you. This
is why the roster handler re-handshakes wholesale on `GROUP_ROSTER_UPDATE` rather
than trying to reason about who joined when.

### Version negotiation — *Implemented*

Every message carries the sender's protocol revision as its first field (in
revision 3, `HELLO` repeats it explicitly). On mismatch:

- Peer is marked `known = true, compatible = false`.
- They are shown as **unknown** for all quests, with an "outdated addon" hint.
- Their queries are **not** answered. A format we do not know cannot be parsed
  safely, and guessing risks sending a reply they would misread. Cross-revision
  answering only becomes meaningful once a second revision exists and the older
  format is still known to us — at which point this becomes a compatibility table
  rather than a guess.

---

## 6. Data model

> **Status: Planned**, except where "As built" says otherwise. The second table below
> is the v1 target.

### As built (v0.0.2)

```lua
QuestTogetherDB = {}          -- SavedVariable; created empty, nothing reads it yet

ns.peers = {                  -- session-scoped, in Peers.lua
  ["Name"] = {                -- key: BARE character name (realm stripped) -- see Q7
    name       = "Name-Realm",          -- display name, as the sender arrived
    compatible = true,                  -- protocol revision matched ours
    lastSeen   = 0,                     -- time() of the last message
    answered   = { [questID] = true },  -- true / false; absent key == UNKNOWN
    onIt       = { [questID] = true },  -- set only alongside answered == false
  },
}
```

Differences from the target that matter: there are **no settings** (so no privacy
toggles), peers are keyed by bare name rather than GUID, there is no `log` dataset and
no `pending` table, and **entries are never dropped** when a peer leaves the group —
[D2](#key-architectural-decisions) is not implemented yet.

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
([§11](#11-testing-strategy)); no automated tests exist yet.

---

## 7. UX specification

> **Status: Planned.** As built, v0.0.2 has one surface: a fixed (not movable) text
> popup beside the quest frame, toggled with `/qt ui` — `/qt` itself *asks*. It prints
> quest IDs rather than titles, words ("yes" / "no" / "on it now" / "?") rather than
> glyphs, lists only peers it has heard from rather than the whole roster, and shows
> "(not in a group)" whenever that list is empty.

### Primary surface — party status panel

A small movable panel toggled with `/qt`. For the quest currently under
consideration, it lists each group member:

```
┌─────────────────────────────┐
│  The Defias Brotherhood     │
│                             │
│   ✓ Ana          completed  │
│   ✓ Ben          completed  │
│   ✗ Cass         needs it   │
│   ? Dee          no data    │
│   ◈ Eve          on it now  │
└─────────────────────────────┘
```

Markers are deliberately distinct in **both** shape and colour, so the states are
separable without relying on colour perception:

| Glyph | State | Colour |
|---|---|---|
| `✓` | completed | green |
| `✗` | confirmed not completed | amber |
| `◈` | currently in their quest log | blue |
| `?` | unknown | grey |

### Secondary surfaces

- **Quest log rows** — a compact marker string per row, e.g. `✓✓✗◈`, one glyph per
  party member in roster order. Hovering expands to names.
- **NPC quest lists** — the same annotation applied to every offered quest, so a
  player can pick the one the group actually needs. All IDs on screen are requested
  in a single coalesced `QREQ`.
- **Tooltips** — quest tooltips gain a "Quest Together" section. This is the
  lowest-risk integration (tooltip hooks are stable) and likely becomes the
  workhorse surface.

### Failure and degradation states

| State | Presentation |
|---|---|
| Solo | Panel says "Not in a group." No requests are sent. |
| No peers have the addon | Every member `?`, with a one-line hint: "None of your group has Quest Together." |
| Peer outdated | `?` for that member, tooltip explains the version mismatch. |
| Request in flight | Brief spinner/ellipsis, resolving to a real state within 3 s. |
| Answer timed out | `?`, with tooltip "No response" — distinct from "no addon". |

That last row is a good example of the tri-state discipline: the user can tell the
difference between *they don't have the addon*, *they have it but didn't answer*,
and *the answer is genuinely no*.

---

## 8. Milestones

### M0 — Ground truth · ~0.5 day · **GO / NO-GO GATE**

**This milestone can kill the project, which is exactly why it runs first.**

- [x] Confirm the client's real identity — `1.60.1`, build `69893`, `tocversion`
      `16001`. The "discrepancy" was a false alarm: `1.60.1` packs to `16001`.
- [x] Confirm `C_ChatInfo.RegisterAddonMessagePrefix("QTOG")` succeeds.
- [x] Confirm `C_QuestLog.IsQuestFlaggedCompleted(id)` returns sane values — verified
      bidirectionally against a real quest turn-in. See
      [the fourth run](#fourth-run--the-oracle-is-confirmed).
- [x] Verify no secret-value restriction touches **quest** APIs — quest data is clean;
      the oracle returns a plain boolean. Residual concern is group identity while
      instanced, which needs two clients.
- [ ] **Confirm addon messages round-trip between two grouped clients.**
      ← the only item still open, and the only one that can kill the project.

> **Instrumented by v0.1.** The measurement probes that closed the first four items
> (`/qt env`, `/qt probe`) were retired on 2026-09-21 — their results are recorded in
> [§12](#12-open-questions). The one remaining item — the fifth, the round-trip —
> needs two grouped clients; the step-by-step procedure is in
> [`docs/TESTING.md`](docs/TESTING.md).

> **Gate:** if addon comms are blocked, or quest APIs return secrets, the design is
> dead and we stop and rethink. Do not proceed past M0 without a clean answer on
> each of these five points.

> **Deviation, recorded honestly.** v0.0.2 went past the gate: the status popup,
> auto-ask and the revision-2 protocol were built while the round-trip was still
> unverified. They are small, and they make the two-client test convenient to run,
> but everything below the gate is at risk until it closes.
> **No further feature work before the round-trip test.**

### M1 — Local oracle · ~1 day

- [ ] Quest log enumeration via the modern `C_QuestLog` API.
- [x] Completion oracle wrapping `IsQuestFlaggedCompleted`, local-only — `ns.SafeIsDone`.
- [x] Standalone status panel rendering the local player's state — `UI.lua` (minimal:
      text only, not movable).
- [ ] Optional dependencies declared (`## OptionalDeps`) — no hard deps in v1.

*No networking yet. Fully testable solo.*

### M2 — Presence and active-log sync · ~1.5 days

- [ ] Transport layer: send queue, throttle, receive dispatch, prefix registration.
      *Partial:* receive dispatch and prefix registration exist; no queue, no throttle.
- [ ] `HELLO` / `LOGS` handling and roster tracking. *Partial:* presence (`H`) only;
      peers are never dropped.
- [ ] Peer panel showing "who's on it" for the quest you're viewing.
- [ ] Graceful handling of peers joining and leaving mid-session.

### M3 — Completion query protocol · ~2 days

- [ ] Bitstream codec: `packBits` / `packIDs` with round-trip tests.
- [ ] `QREQ` / `QREP` with sequence correlation and 3-second timeouts. *Partial:*
      the single-quest revision-2 `Q` / `A` exchange with a 3-second reply window.
- [ ] Request coalescing and the sliding-window throttle.
- [x] The tri-state cache, including the "never write `false` from absence" invariant
      — `ns.RecordAnswer`. (Its unit test is still owed.)
- [x] `/qt status` debug output.

### M4 — UI integration · ~2.5 days

- [ ] Quest log row annotations.
- [ ] NPC gossip/available-quest list annotations (single coalesced request).
- [ ] Tooltip integration.
- [ ] Settings panel bound to the privacy toggles.

### M5 — Hardening and release · ~2 days

- [x] `pcall` discipline on every inbound message handler — malformed input from a
      peer must never produce a Lua error in *your* session. (Field *validation* is
      still incomplete: quest IDs are not checked for integer / `> 0`.)
- [ ] SavedVariables settings persistence with schema migration.
- [ ] Localisation scaffolding (`enUS` first).
- [ ] Full bug sweep with two live clients.
- [ ] CurseForge packaging, version stringing, changelog.

**Total: ~9–11 focused days to a polished v1.**

---

## 9. Non-goals

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

---

## 10. Risk register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | No API for peers' quest state (C1) | Fatal to the naive design | Certain | **Already designed around.** P2P via addon messaging. |
| R2 | Forever's secret-value restrictions block quest or identity APIs | Fatal | **Largely retired** | Measured 2026-09-20: `issecretvalue` exists, but `IsQuestFlaggedCompleted` returns a plain boolean. Quest data is clean. Residual: group identity while instanced — test while grouped; fall back to `name-realm` if `UnitGUID` misbehaves. |
| R3 | Addon comms restricted or throttled harder than expected | Fatal | **Unresolved — the last gate** | Prefix registration succeeds, but no message has yet crossed between two clients. **Test grouped before building any further.** If throttled, cut `LOGS` frequency and widen the coalescing window. |
| R4 | Unknown rendered as "not completed" | Silently wrong advice | **Medium** | Tri-state model, single write path, explicit unit test, distinct glyphs. |
| R5 | Blizzard frame hooks break on patch | Feature loss | High (long term) | v1 avoids hard hooks; tooltips + standalone panel are resilient surfaces. |
| R6 | A **silent** peer in an otherwise-enabled group — no addon, incompatible revision, or no reply | Degraded view for that one member | Certain | The [premise](#premise) covers the common case; participants are expected to have it. Residual silence renders as `?`, with a hint distinguishing "no addon" from "no response". |
| R7 | TOC `Interface` number unknown / `16001` inconsistent | Addon won't load | **Retired** | Closed by [Q1](#open-questions): `16001` is correct and the addon loads. Re-check on every client patch. |
| R8 | Stale cache from a peer who completed quests mid-session | Rarely wrong advice | Low | Cache is session-scoped, cleared on roster change (D2). |
| R9 | Privacy discomfort | Trust damage | Medium | Two independent toggles, plain-language README section. |
| R10 | Quest data volume on exotic queries | Throttle stalls | Low | Coalescing + batching + a hard cap per request. |
| R11 | **No Lua toolchain on the dev machine** — syntax, scope and hoisting errors reach the client before any check catches them | Bugs found by crash, not by tooling | **Certain, and already realised once** | Install a Lua interpreter to machine-check the file (see below), or accept `/reload` as the test loop and keep the crash surface small. |

**R11 in practice.** v0.1 shipped with an `attempt to call a nil value` crash caused
by a forward reference: `SafeStr` called `IsSecret` above its `local function`
definition, so the name resolved as a global. Be precise about which tool catches
that:

| Check | Catches syntax errors | Catches the v0.1 forward reference |
|---|---|---|
| `luac -p` (parse only) | yes | **no** — the code is syntactically valid |
| Loading the file in a bare interpreter | yes | **no** — it fails only when the function is *called* |
| `luacheck` (static analysis) | yes | **yes** — reported as access to an undefined global |

So the tool this risk actually calls for is **`luacheck`**, with the WoW globals
declared. It is not set up yet.

**Partially resolved 2026-09-21.** The modules were parse-checked with Lua 5.5's
`luac -p`. That check is not reproducible from the repository — no script, no CI, and
the interpreter path is machine-specific — and it does not cover the bug class above.
Until `luacheck` runs in CI, the cross-module "call only at runtime" rule carries that
weight alone.

---

## 11. Testing strategy

> **Status: Planned.** No automated tests exist yet, and `/qt test` is not
> implemented. What exists today is Layer 4 as a written manual checklist:
> [`docs/TESTING.md`](docs/TESTING.md).

**Layer 1 — Pure functions, offline.** The codec is the most bug-prone component and
the easiest to test. `packBits`/`packIDs` get round-trip property tests plus
hand-computed vectors, including edge cases: empty set, single ID, deltas crossing
varint boundaries, and a full 64-value alphabet cycle.

**Layer 2 — In-game unit harness.** A `/qt test` entry point runs assertions against
a mocked peer table and prints a pass/fail summary. Covers the tri-state cache
invariants, sequence correlation, and timeout expiry.

**Layer 3 — Protocol hardening.** Feed malformed, truncated, oversized, and
adversarial payloads into the receive dispatcher. **Success criterion: no Lua error,
ever** — every handler wrapped in `pcall`, every field validated before use. A
malicious or buggy peer must not be able to break your client.

**Layer 4 — Two-client manual test.** Two accounts, grouped, live realm. The only
way to validate the throttle, coalescing, and roster-change behaviour meaningfully.
A written checklist per milestone, executed before that milestone is called done.

**Layer 5 — Adversarial UX review.** Deliberately test the failure matrix: peer
without addon, peer outdated, peer leaving mid-request, request timeout, and rapid
quest-frame clicking. Each must produce an honest, non-misleading state.

---

## 12. Open questions

Tracked here so they stay visible until closed.

### Measurement — 2026-09-20

`/qt env` was run on the live client. Results:

| Probe | Result |
|---|---|
| Client version | `1.60.1`, build `69893`, dated Sep 16 2026 |
| `tocversion` | `16001` |
| `C_ChatInfo.SendAddonMessage` | present |
| `C_ChatInfo.RegisterAddonMessagePrefix` | present |
| legacy `SendAddonMessage` | **absent** |
| legacy `RegisterAddonMessagePrefix` | **absent** |
| `C_QuestLog.IsQuestFlaggedCompleted` | present |
| legacy `IsQuestFlaggedCompleted` | **absent** |
| `C_GossipInfo`, `GetQuestID` | present |
| `issecretvalue` | present |
| `C_Timer.After` | present |
| Prefix registration | succeeds |
| Completion oracle | returned `false` for quest `92460` — **a real boolean, not a secret** |

Two conclusions worth stating plainly.

**1. The version string is a trap.** Forever reports `1.60.1` — a 1.x version — while
exposing a fully modern API surface with every legacy global removed. The version
number says nothing about the API generation. Any addon that branches on client
version (a common idiom: `if tocversion < 80000 then …`) will misidentify this client
badly. **Branch on API presence, never on version.**

**2. The Mainline-architecture report is confirmed by measurement**, not merely
repeated from press. The modern namespace is complete; the legacy globals are gone.

### Measurement, second run — solo API sweep

A second `/qt env`, with the expanded probes, closed nearly every remaining presence
question. **Everything v0.2 needs is present on this client:**

| Probe | Result |
|---|---|
| `C_QuestLog.GetNumQuestLogEntries` | present |
| `C_QuestLog.GetInfo` | present |
| `C_QuestLog.GetQuestIDForLogIndex` | present |
| `C_QuestLog.GetLogIndexForQuestID` | present |
| `C_GossipInfo.GetAvailableQuests` | present |
| `C_GossipInfo.GetActiveQuests` | present |
| `IsInGroup` / `IsInRaid` | present |
| `GetNumGroupMembers` | present |
| `UnitExists`, `UnitName`, `UnitGUID`, `UnitIsUnit` | present |
| `canaccesssecrets` / `canaccessvalue` | present |
| `C_QuestLog.GetQuestPartyProgress` | **absent** |
| `C_QuestLog.QuestHasPartyProgress` | **absent** |
| `C_QuestLog.GetQuestLogPartyMembers` | **absent** |

**There is no native party-quest-progress API, and this validates the premise.** All
three candidate names are missing, which is strong evidence that Blizzard exposes no
such data and that the default quest log cannot be displaying it — UI functionality
requires a backing API, and none exists. So we are not duplicating built-in
functionality, and the protocol is not redundant. That was the largest open product
risk and it has resolved in our favour.

Honest limit on the claim: three candidate *names* were probed, not the whole
namespace. That is strong evidence, not proof. The definitive check is visual and
takes ten seconds — group up, open the quest log, look for party progress
([Q6](#open-questions)).

### Third run — a bug of ours, and a lesson worth keeping

**We shipped a Lua bug.** `Core.lua` crashed with `attempt to call a nil value`
inside `SafeStr`, because `IsSecret` was defined *below* its first use. Lua's
`local function` does not hoist: the name resolved as a *global* lookup, returned
`nil`, and failed at runtime rather than at load time.

The generalisable lesson, worth more than the fix: **in Lua, definition order is
load-bearing, and getting it wrong fails late and quietly rather than loudly at
load.** Two mitigations are worth carrying forward:

- At the time, helper order in `Core.lua` was made deliberate, with a forward
  declaration. *Superseded:* the helpers now live in `Compat.lua` as fields of `ns`,
  which are looked up at call time, so the ordering trap no longer exists for them.
- There is no Lua interpreter on the development machine, so nothing verifies
  syntax or scope before the client does. **This is now a named risk** — see
  [R11](#10-risk-register).

**We also got the event payload, by accident.** The crash lost us the
`QUEST_ACCEPTED` trace line, but the error's locals carried `v=92460` while the chat
log read *"Quest accepted: Coming of Age"*. So **`QUEST_ACCEPTED` passes the quest ID
as `arg1`** — inferred from a crash's local state rather than observed cleanly. Re-run
`/qt events` after the fix to confirm it properly. It is a useful result obtained by
an embarrassing route.

### Fourth run — the oracle is confirmed

The decisive test, in its strongest form. **The same quest ID returned different
answers across a real change of state:**

| Moment | Call | Result |
|---|---|---|
| Quest `92460` accepted, not yet turned in | `/qt probe 92460` | `false` |
| After turning it in | `/qt probe 92460` | **`true`** |

This is stronger than merely "we saw a `true`". A function returning a constant would
have been caught by either observation alone; watching the *same input* yield `false`
and then `true` across a genuine state change proves the oracle is both live and
correct. `C_QuestLog.IsQuestFlaggedCompleted` is **verified as the completion oracle**,
and with it goes the last assumption underpinning the design.

The sweeps that preceded this were inconclusive, and the reason is worth keeping: they
scanned `1..20000`, a range that appears to hold no real quest IDs (every observed ID
sits around 92k), against a character that had completed nothing. **A targeted probe
against one known quest beat a twenty-thousand-ID sweep.** Ask the specific question
before reaching for the brute-force one.

**Probes retired (2026-09-21).** With the completion oracle, API surface and
`GetInfo` schema all measured and recorded above, the one-shot probes that took
those measurements — `/qt env`, `/qt probe`, `/qt log`, `/qt scan` — have been
removed from `Diagnostics.lua`. `/qt events` stays (event payloads are still
unverified) and `/qt frames` stays (for M4). Re-add a probe only when a new
surface needs measuring.

### Still unverified

**1. Event payloads.** `QUEST_ACCEPTED` is believed to pass the quest ID as `arg1` —
inferred from a crash's local state rather than observed cleanly. `/qt events` traces
the real arguments. Cheap to settle; do it before v0.2 relies on it.

**2. Everything requiring two grouped clients.** Every run so far has been solo
(`channel : no (solo)`). The addon-message round-trip, group identity under the secret
rules, and cross-client quest queries all remain open.

> **This is the last M0 gate.** Everything else in M0 is closed. The only fatal risk
> remaining is whether an addon message crosses between two clients at all.

### Open questions

| # | Question | Status | Resolution |
|---|---|---|---|
| Q1 | Correct `## Interface` value? | **Closed** | `16001`. Version `1.60.1` packs as major/minor/patch → `16001`. There was never a conflict; the version string simply does not describe the API generation. |
| Q2 | Which directory does Forever load addons from? | Open | The addon loaded, so the folder in use is correct — record which one that was before writing install instructions. |
| Q3 | Does a native party-quest-progress API exist? | **Closed — negative** | `GetQuestPartyProgress`, `QuestHasPartyProgress` and `GetQuestLogPartyMembers` are all absent. No native support, so nothing is duplicated. |
| Q4 | Are addon messages rate-limited differently here? | Open | **The remaining gate.** Needs two grouped clients. |
| Q5 | Do quest frame objects keep Mainline names and structure? | Open | M4 |
| Q6 | Does the default quest log already show party progress? | **Effectively closed** | No backing API exists ([Q3](#open-questions)), and UI cannot show what no API provides. Confirm visually while grouped. |
| Q7 | Is `name-realm` a stable peer key? | Open | M2. Note the code currently keys by **bare name** (`ns.BaseName` strips the realm), which is strictly worse: same-named characters from two realms collide, and a cross-realm namesake of the local player is ignored as "self". |

---

## 13. Appendix: API cheat sheet

Working reference. **Every entry to be verified in M0 before being relied upon.**

### Quest completion (local player only)

| API | Use |
|---|---|
| `C_QuestLog.IsQuestFlaggedCompleted(questID)` | The completion oracle. Local player only. |
| `C_QuestLog.GetNumQuestLogEntries()` | Entry count — **includes headers**, so it is not a quest count. |
| `C_QuestLog.GetInfo(index)` | Quest log entry metadata (table; schema below). |
| `C_QuestLog.GetQuestIDForLogIndex(index)` | Quest ID ↔ log index mapping. |
| `C_QuestLog.GetLogIndexForQuestID(questID)` | Reverse mapping. |

#### `GetInfo` — measured schema on the live client

Measured 2026-09-20, client 1.60.1. The returned table carries:

```
difficultyLevel, hasLocalPOI, headerSortKey, isAbandonOnDisable, isAutoComplete,
isBounty, isCollapsed, isHeader, isHidden, isInternalOnly, isOnMap, isScaling,
isStory, isTask, level, overridesSortOrder, questClassification, questID,
questLogIndex, readyForTranslation, sortAsNormalQuest, startEvent,
suggestedGroup, title, useMinimalHeader
```

Three findings, two of which are corrections to what the plan assumed:

- **`isComplete` does not exist.** The plan assumed it. Completion is not a property
  of the log entry — it comes from `IsQuestFlaggedCompleted`, which is consistent
  with the whole design (the oracle is the single source of completion truth).
- **`isHeader` exists, and headers are enumerated.** A log containing exactly one
  real quest reported **2 entries**: the quest, plus a `Zephras Isle` zone header
  with `questID = 0`. Confirmed against the client UI, which shows a single quest.
- **The oracle answers for garbage.** `IsQuestFlaggedCompleted(0)` returns `false`
  rather than raising, so a header mistaken for a quest yields a plausible-looking
  wrong answer. This is the tri-state hazard wearing a different costume.

**Requirement for v0.2:** before building any `LOGS` payload, skip entries whose
`isHeader` is true and require `questID > 0`. The check is free; the failure it
prevents is silent.

### Quest IDs from the UI

| API | Use |
|---|---|
| `GetQuestID()` | ID of the quest in the quest frame. |
| `C_GossipInfo.GetAvailableQuests()` | Quests an NPC can offer. |
| `C_GossipInfo.GetActiveQuests()` | Quests an NPC can turn in. |

### Messaging

| API | Use |
|---|---|
| `C_ChatInfo.RegisterAddonMessagePrefix("QTOG")` | Required before sending. |
| `C_ChatInfo.SendAddonMessage("QTOG", payload, "PARTY")` | Send to group. |
| `CHAT_MSG_ADDON` event | Receive; handler args carry prefix, payload, channel, sender. |

### Events

| Event | Use |
|---|---|
| `GROUP_ROSTER_UPDATE` | Roster changed → re-handshake, invalidate peer cache. |
| `PLAYER_ENTERING_WORLD` | Re-announce presence. |
| `QUEST_LOG_UPDATE` | Local log changed → debounce → broadcast `LOGS`. |
| `QUEST_ACCEPTED` / `QUEST_TURNED_IN` | Immediate log-change triggers, where available. |

### Secret-value detection (Forever / Midnight restrictions)

| API | Use |
|---|---|
| `issecretvalue(v)` | Does this value carry a secret? |
| `canaccesssecrets()` | May this execution path read secrets? |
| `canaccessvalue(v)` | Combined check. |

---

*End of plan.*
