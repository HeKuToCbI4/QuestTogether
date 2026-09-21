# Measurements

What was measured on the live client, open questions, and the API cheat sheet.

> Part of the Quest Together design docs — index: [`PLAN.md`](../PLAN.md). Sections are
> marked **Implemented**, **Partially implemented** or **Planned**; for current
> behaviour the code is authoritative.

---

## Measurements and open questions

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
  [R11](ROADMAP.md#risk-register).

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

**2. Instance (LFG) groups.** `ns.GroupChannel` now returns `"INSTANCE_CHAT"` when
`IsInGroup(<instance category>)` is true, but **neither the category constant nor the
argument form has been seen on this client** — the lookup is guarded, so a miss simply
leaves the old `"RAID"` / `"PARTY"` behaviour in place. `/qt channel` prints whether
`LE_PARTY_CATEGORY_INSTANCE` (or `Enum.PartyCategory.Instance`) exists and its value,
what `IsInGroup(<category>)`, `IsInGroup()` and `IsInRaid()` return, and the channel
that would be used. Run it **three times** — solo, in a normal party, and inside an
LFG/dungeon-finder group — and record all three outputs here. The instance run is the
one that matters: it must print an existing constant and `channel we would use:
INSTANCE_CHAT`. If the constant is absent, find the name this client uses before
relying on the branch.

**3. Everything requiring two grouped clients.** Every run so far has been solo
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
| Q7 | Is `name-realm` a stable peer key? | Open — narrowed | The code now keys by full normalised `Name-Realm` (`ns.PeerKey`), instead of the bare name that made two realms collide. Two things are still **unmeasured** on this client: whether `GetNormalizedRealmName` exists (the code falls back to a bare key if not), and what realm suffix `CHAT_MSG_ADDON` actually puts on `sender` for a same-realm and a cross-realm peer. Record both in the two-client test ([TESTING.md §B](TESTING.md#b-two-client-round-trip--the-m0-gate), "Observations"). |

---

## Appendix: API cheat sheet

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
