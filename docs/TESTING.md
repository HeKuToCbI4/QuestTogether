# Manual testing

The offline suite (`lua5.1 tests/run.lua`) covers the wire format, the tri-state
invariant and hostile input — see [testing strategy](ROADMAP.md#testing-strategy).
Everything below is what it cannot reach: the client itself. Run these by hand and
record the results — including the date, client build and any surprising output —
in [`MEASUREMENTS.md`](MEASUREMENTS.md#measurements-and-open-questions).

Expected chat lines are prefixed with `Quest Together Forever` in green; that prefix is
omitted below.

---

## A. Solo smoke test (one client, ~2 minutes)

Run after every change, before anything else.

| # | Step | Expected |
|---|---|---|
| A1 | `/reload`, then check the AddOns list | **Quest Together Forever** is listed and enabled. No Lua error on load. |
| A2 | `/qtf help` | Header `v0.0.2 -- commands:` (the version comes from the `.toc`), then `/qtf`, `/qtf ask <id>`, `/qtf ping`, `/qtf status`, `/qtf help`, `/qtf config`, `/qtf debug`, `/qtf ui`, then `-- still-open probes --` with `/qtf events`, `/qtf frames`, `/qtf channel`, `/qtf sendtest`, `/qtf realm`, `/qtf roster` and `/qtf parchment`. |
| A3 | `/qtf ui` | Popup appears: `No quest open.` `/qtf ui` again hides it. |
| A4 | `/qtf` with no quest open | `No quest selected. Open a quest at an NPC, or use /qtf ask <questID>.` |
| A5 | `/qtf ask 92460` while solo | `Cannot ask: not in a group` |
| A6 | `/qtf status` | `No peers heard from yet. Try /qtf ping while grouped.` |
| A7 | Open any quest at an NPC | Popup appears beside the quest frame with a gold `Quest Together Forever` title, `Quest <id>` in grey on the right, a `You: …` line and, while solo, `Not in a group.` Nothing is printed to chat (solo stays quiet). Closing the quest frame hides the popup. |
| A8 | A quest you **have** completed vs one you have **not** | `You: yes - already completed` / `You: no - has not completed it` respectively. |
| A9 | `/qtf events`, accept a quest, `/qtf events` | Trace lines for `QUEST_ACCEPTED` etc. with their arguments. **Record the `QUEST_ACCEPTED` arguments** — this closes "Still unverified" item 1. |
| A10 | `/qtf frames` | A yes/NO line per frame name. Record it (feeds Q5). |
| A11 | `/qtf ask 0`, `/qtf ask 1.5`, `/qtf ask -3` | `Cannot ask: invalid quest ID` — rejected before anything is sent. `/qtf ask 92460` while solo still reads `Cannot ask: not in a group`, so the guard did not swallow valid IDs. |
| A12 | `/qtf realm` (`/dump` prints nothing on this client, so it cannot be used) | **Record the whole output.** For `GetNormalizedRealmName`, a realm string means peer keys are full `Name-Realm`; `nil` or an error means the API is absent and keys fall back to the bare name (still correct, just no better than before). Feeds [Q7](MEASUREMENTS.md#open-questions). |
| A13 | `/qtf channel` while solo | A block of probe lines. `channel we would use:  nil` (solo). **Record whether `LE_PARTY_CATEGORY_INSTANCE` or `Enum.PartyCategory.Instance` exists and its value** — this is the measurement the instance-group fix is waiting on ("Still unverified" item 2). No Lua error even when the constant is absent. |
| A14 | `/qtf sendtest` while solo | Says whether `Enum.SendAddonMessageResult` exists (and lists it if so), then prints the count, value and type of everything the raw send returned. **Record the whole output** — this is the solo half of "Still unverified" item 3 in [`MEASUREMENTS.md`](MEASUREMENTS.md#still-unverified). No Lua error, whatever it prints. |
| A15 | Open a quest at an NPC, close it, open another | The popup has a **bronze** tooltip border and is filled with the **same parchment as the quest text**, equally dark; its text uses the **same font, size and colour as the quest description**; `/qtf parchment` names where the parchment came from. It **slides out from under the quest frame's right edge** while fading in, in about a quarter of a second, ending just under that edge. Switching quests with the popup up does not replay the slide. States are coloured: `yes` green, `no` amber, `on it now` blue, `?` grey; hints (`Not in a group.`) muted brown. **If not:** dark blue-black fill instead of parchment → no parchment found; record the whole `/qtf parchment` output. Small or wrong font → no quest font string found (`font borrowed: nil`); record the output too. Plain black box → `BackdropTemplate` is missing here. Popup appears instantly on top of the quest frame → `QuestFrame` did not report a strata/level. Popup slides across the **face** of the quest frame → the level trick does not hold on this client. Record which in MEASUREMENTS.md, "Still unverified" item 4. |
| A16 | Esc → Options → **AddOns** tab. Then close it and type `/qtf config`, then `/qtf settings` | **Quest Together Forever** is listed on the left, under the other addons. Its page shows the title, `Version … - protocol revision 2`, two checkboxes (**Test option A** ticked, **Test option B** not, both "(does nothing yet)") and a **Copy debug info** button. `/qtf config` and `/qtf settings` both open the window on that page. Tick B, untick A, `/reload`, reopen: the ticks are as you left them. In combat, `/qtf config` says it cannot open the window. **If not:** not listed, or `/qtf config` prints `not available` → run `/qtf debug` and record its `## settings panel` and `## client` sections in MEASUREMENTS.md, "Still unverified" item 5. |
| A17 | Press **Copy debug info** (or type `/qtf debug`), press Ctrl+C, paste anywhere (a text file) | A movable window with the whole report, already selected. Ctrl+C copies it; the paste starts with `Quest Together Forever debug info` and has the `## addon`, `## client`, `## player and group`, `## peers`, `## open quest`, `## settings panel`, the four probe sections and `## status panel`, with no `|c` colour codes. Typing into the window changes nothing. Esc or the X closes it. **Paste the report into bug reports and test notes from now on.** |

---

## B. Two-client round-trip — **the M0 gate**

The one test that can still kill the project: does an addon message cross between
two grouped clients at all?

**Setup.** Two accounts, two clients (A and B), same addon version on both, both
characters in the open world (not instanced), both with no Lua errors on load.
Pick a quest ID `Q1` that **A has completed and B has not** (or the reverse), and a
quest `Q2` that B currently has **in their log, uncompleted**.

| # | Step | Expected | If it fails |
|---|---|---|---|
| B1 | A invites B; B accepts | On **both** clients: `<other> has the addon.` within about five seconds (presence is announced on roster change, debounced by ~3 s, plus up to 2 s of jitter on a reply). | Wait the full five seconds, then go to B2 before concluding anything. |
| B2 | A: `/qtf ping` | A: `Announced to the group…`. B: `<A> has the addon.` (if not already printed). | `Prefix is not registered` → registration failed; record it. No line on B → **the gate has failed**; record exactly what each client printed, then try B2 from B → A. |
| B3 | Both: `/qtf status` | Each lists the other as `compatible  (0 answers cached)`. | |
| B4 | A: `/qtf ask Q1` | A: `Asking your group about quest Q1...`, then a live line `<B>: no - has not completed it` (or `yes - already completed`). **Nothing more after 3 s** — B already answered, and nobody is printed twice. | A heading `Quest Q1 -- no answer from:` with B as `?  (no answer)` → B received nothing or could not answer. On B, `/qtf status` shows whether B heard A at all. |
| B5 | Compare with the truth | The answer in B4 matches what B's own popup says for `Q1` (B: open the quest or `/qtf ui`). | A mismatch is a **correctness bug** — stop and report. |
| B6 | A: `/qtf ask Q2` | `<B>: on it now` | |
| B7 | B: `/qtf ask Q1` | B sees A's true state — the reverse direction works. | |
| B8 | A opens a quest at an NPC | A's popup appears and, without typing anything, fills in B's line (auto-ask). **Chat stays completely silent** on A — no `Asking your group…`, no answer lines, no summary. | Any chat line here is bug #8 back again. |
| B9 | B: `/reload`. Then A: `/qtf ask Q1` | B still answers after the reload. | |
| B10 | B: disable Quest Together Forever, `/reload`, stay grouped. A: open a quest | A's popup lists B **by name** as `?  (no addon heard from)`. A: `/qtf ask Q1` prints, after 3 s, `Quest Q1 -- no answer from:` and the same line for B. | B missing from the list → the roster walk failed; record what `/qtf status` shows. |
| B11 | Re-enable on B; A: `/qtf ask Q1`, then B leaves the group, then A: `/qtf ask Q1` again | First ask names B with a real answer; after B leaves, B is gone from the list entirely (not a stale `yes`/`no`). | B still listed → pruning and the registry disagree about the key. |
| B12 | A opens `Q1` (B's line fills in). B leaves the group, then A re-invites B. A opens `Q1` again. | B is asked again and fills in — not left on `?`. | Stuck on `?` → the auto-ask dedupe is not being cleared on roster change. |
| B13 | A clicks through 3 different quests quickly (open, close, open the next) | A's popup tracks the quest on screen. Chat stays silent. B answers all three (check with `/qtf status` on A: the answer count grows). | |
| B14 | A: `/qtf ask Q1`, then `/qtf ask Q2`, then `/qtf ask Q1` again, all within 3 seconds | Three `Asking your group…` lines. Live answer lines for **both** quests, each answer printed **once**. No `no answer from` heading, since B answered both. | A missing live line, or an answer repeated 3 s later → pending asks are not keyed by quest ID, or the summary repeats live lines again. |
| B15 | B: `/reload`, then **type nothing on either client**. Watch B's chat for ~10 s, then B: `/qtf status` | Within a few seconds and with nobody typing: `<A> has the addon.` on B, and `/qtf status` on B lists A as `compatible`. B announces on entering the world and A, having been quiet, answers. | Nothing on B → either B's announcement never left (check `/qtf ping` on B, then A's chat) or A did not answer it. On A, `/qtf status` shows whether A heard B at all. Record which. |
| B16 | With both grouped, cause a burst of roster events (promote/demote B, mark assist, swap subgroups, or invite and remove a third character) as fast as you can for ~10 s, then leave both clients idle for a minute | During the burst: no repeated `<other> has the addon.` lines, no chat spam, no disconnect — announcements are coalesced to at most one per ~3 s per client. While idle afterwards: nothing more is sent, i.e. the two clients are not answering each other in a loop. | There is no visible trace of an individual `H`; to watch the coalescing and the idle silence directly, temporarily add an `ns.Print` inside `ns.Announce` and count the lines — far fewer than the number of roster events, and none at all once everything is idle. |
| B17 | One of the two characters has a **space in the name**. A: `/qtf ask Q1` | One live line naming B with a real answer, and **no** `no answer from` heading after 3 s. B is not dropped from `/qtf status` when the roster changes. | `?  (no addon heard from)` for B right after a live answer → the roster and the sender disagree about the key again (issue #24). Run `/qtf roster` and record it. |
| B18 | A opens `Q1` at the NPC: popup says `<B>: no - has not completed it`. A closes it. **B accepts `Q1`.** A opens `Q1` again (more than 5 s later) | A's popup now says `<B>: on it now`, with nothing typed. If A has the quest too, A's own line reads `You: on it now`. | Still `no` → the auto-ask did not go out again; the popup is showing a cached answer. |

**Passing B2, B4, B5 and B7 closes the gate.** Tick the last M0 box in [`ROADMAP.md`](ROADMAP.md#milestones),
close Q4 if nothing looked throttled, and update R3.

### Observations to record even on a pass

- Latency between the ask and the live answer line.
- **`/qtf roster` on both clients**, after the other one has sent anything (`/qtf ping`).
  Record the whole output: how `UnitName` / `UnitFullName` spell the other member, and
  the raw addon-message sender. Most useful with a character whose name contains a
  space. Every line must end in `known peer: yes`. (feeds Q7, issue #24)
- Whether anything differs when the pair is **cross-realm**, and whether a cross-realm
  peer is shown as `Name-Realm`. (feeds Q7)
- Whether `/qtf status` on A shows cached answers growing on a third client C that
  never asked (passive caching via broadcast replies).
- **`/qtf sendtest` while grouped** — run it once, then about ten times in a row.
  Record the count, value and type it prints each time, and whether the value
  changes under the spam. That is the grouped half of "Still unverified" item 3 in
  [`MEASUREMENTS.md`](MEASUREMENTS.md#still-unverified) and the evidence for
  [Q4](MEASUREMENTS.md#open-questions). Compare it with the solo output from A14:
  the two together say which return convention this client uses.

---

## C. Failure matrix (after the gate is closed)

Each of these must produce an honest, non-misleading state — never a false "no".
Several are **known to fail today**; the expected column is the target.

| # | Scenario | Target | v0.0.2 |
|---|---|---|---|
| C1 | B has the addon disabled | B shown as `?` | `?  (no addon heard from)` — the list is driven by the roster |
| C2 | B on a different `ns.PROTOCOL` (edit the constant locally) | `?  (incompatible addon version)`; B's queries unanswered | Expected to work |
| C3 | B leaves the group | B disappears from A's popup and from `/qtf status` | Dropped on roster change |
| C4 | B turns the quest in after answering "no" | A sees "yes" the next time A opens the quest | Expected to work — every opening asks again (after a 5 s dedupe window). While the popup **stays open** it does not refresh by itself |
| C5 | A opens the same quest twice | Two asks, unless within 5 s of each other | Expected to work — the dedupe only absorbs a re-fired event for one opening |
| C6 | Rapid clicking through 5+ quests | No disconnect, no missing answers | One query per quest opened, none printed to chat — no throttle on `Q`/`A` exists (only `H` is debounced), so observe and record |
| C7 | Instance / LFG group. Run `/qtf channel` in a normal party **and** in the instance group before the round-trip | `/qtf channel` prints `PARTY` in the party and `INSTANCE_CHAT` in the instance group; the round-trip then works | `INSTANCE_CHAT` is now chosen — **but the category constant is unverified on this client.** If `/qtf channel` reports it absent, the channel stays `PARTY` and the round-trip still fails; record the output in MEASUREMENTS.md |
| C8 | Cross-realm peer with the **same character name** as another peer, or as you | Distinct entries | Expected to work — keyed by full `Name-Realm` (`ns.PeerKey`). Needs a cross-realm group to confirm |
| C12 | Grouped, nobody else has the addon | Every member `?  (no addon heard from)` | Expected to work |
| C13 | Grouped with 4 others, only one has the addon | All four listed; one answers, three read `?  (no addon heard from)` | Expected to work |
| C14 | B leaves the group, then A `/qtf status` and opens a quest | B gone from both | Expected to work — pruning now uses the same key as the registry |
| C9 | A peer sends a zero, fractional, negative or out-of-range quest ID | Ignored silently: no answer is sent for it, nothing is cached for it | Expected to work |
| C10 | B leaves, then A re-ask about the same quest | B is `?` again, never a stale `yes`/`no` from before they left | Expected to work |
| C11 | Both clients change zone at the same time | Peers may briefly read `?`, then fill back in within a few seconds as every client re-announces on `PLAYER_ENTERING_WORLD` (debounced) | Expected to work |
