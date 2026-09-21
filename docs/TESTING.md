# Manual testing

There are no automated tests yet (see [testing strategy](ROADMAP.md#testing-strategy)).
These checklists are the test suite. Record results — including the date, client
build and any surprising output — in [`MEASUREMENTS.md`](MEASUREMENTS.md#measurements-and-open-questions).

Expected chat lines are prefixed with `Quest Together` in green; that prefix is
omitted below.

---

## A. Solo smoke test (one client, ~2 minutes)

Run after every change, before anything else.

| # | Step | Expected |
|---|---|---|
| A1 | `/reload`, then check the AddOns list | **Quest Together** is listed and enabled. No Lua error on load. |
| A2 | `/qt help` | The command list, ending with the `/qt ui` line. |
| A3 | `/qt ui` | Popup appears: `No quest open.` `/qt ui` again hides it. |
| A4 | `/qt` with no quest open | `No quest selected. Open a quest at an NPC, or use /qt ask <questID>.` |
| A5 | `/qt ask 92460` while solo | `Cannot ask: not in a group` |
| A6 | `/qt status` | `No peers heard from yet. Try /qt ping while grouped.` |
| A7 | Open any quest at an NPC | Popup appears beside the quest frame with `Quest <id>` and a `You: …` line. Nothing is printed to chat (solo stays quiet). Closing the quest frame hides the popup. |
| A8 | A quest you **have** completed vs one you have **not** | `You: yes - already completed` / `You: no - has not completed it` respectively. |
| A9 | `/qt events`, accept a quest, `/qt events` | Trace lines for `QUEST_ACCEPTED` etc. with their arguments. **Record the `QUEST_ACCEPTED` arguments** — this closes "Still unverified" item 1. |
| A10 | `/qt frames` | A yes/NO line per frame name. Record it (feeds Q5). |
| A11 | `/qt ask 0`, `/qt ask 1.5`, `/qt ask -3` | `Cannot ask: invalid quest ID` — rejected before anything is sent. `/qt ask 92460` while solo still reads `Cannot ask: not in a group`, so the guard did not swallow valid IDs. |

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
| B2 | A: `/qt ping` | A: `Announced to the group…`. B: `<A> has the addon.` (if not already printed). | `Prefix is not registered` → registration failed; record it. No line on B → **the gate has failed**; record exactly what each client printed, then try B2 from B → A. |
| B3 | Both: `/qt status` | Each lists the other as `compatible  (0 answers cached)`. | |
| B4 | A: `/qt ask Q1` | A: `Asking your group about quest Q1...`, then a live line `<B>: no - has not completed it` (or `yes - already completed`), then after 3 s the summary with the same answer. | `?  (no answer)` in the summary → B received nothing or could not answer. On B, `/qt status` shows whether B heard A at all. |
| B5 | Compare with the truth | The answer in B4 matches what B's own popup says for `Q1` (B: open the quest or `/qt ui`). | A mismatch is a **correctness bug** — stop and report. |
| B6 | A: `/qt ask Q2` | `<B>: on it now` | |
| B7 | B: `/qt ask Q1` | B sees A's true state — the reverse direction works. | |
| B8 | A opens a quest at an NPC | A's popup appears and, without typing anything, fills in B's line (auto-ask). | |
| B9 | B: `/reload`. Then A: `/qt ask Q1` | B still answers after the reload. | |
| B10 | B: `/reload`, then **type nothing on either client**. Watch B's chat for ~10 s, then B: `/qt status` | Within a few seconds and with nobody typing: `<A> has the addon.` on B, and `/qt status` on B lists A as `compatible`. B announces on entering the world and A, having been quiet, answers. | Nothing on B → either B's announcement never left (check `/qt ping` on B, then A's chat) or A did not answer it. On A, `/qt status` shows whether A heard B at all. Record which. |
| B11 | With both grouped, cause a burst of roster events (promote/demote B, mark assist, swap subgroups, or invite and remove a third character) as fast as you can for ~10 s, then leave both clients idle for a minute | During the burst: no repeated `<other> has the addon.` lines, no chat spam, no disconnect — announcements are coalesced to at most one per ~3 s per client. While idle afterwards: nothing more is sent, i.e. the two clients are not answering each other in a loop. | There is no visible trace of an individual `H`; to watch the coalescing and the idle silence directly, temporarily add an `ns.Print` inside `ns.Announce` and count the lines — far fewer than the number of roster events, and none at all once everything is idle. |

**Passing B2, B4, B5 and B7 closes the gate.** Tick the last M0 box in [`ROADMAP.md`](ROADMAP.md#milestones),
close Q4 if nothing looked throttled, and update R3.

### Observations to record even on a pass

- Latency between the ask and the live answer line.
- Sender name format as shown in `<B> has the addon.` — `Name` or `Name-Realm`? (feeds Q7)
- Whether anything differs when the pair is **cross-realm**.
- Whether `/qt status` on A shows cached answers growing on a third client C that
  never asked (passive caching via broadcast replies).

---

## C. Failure matrix (after the gate is closed)

Each of these must produce an honest, non-misleading state — never a false "no".
Several are **known to fail today**; the expected column is the target.

| # | Scenario | Target | v0.0.2 |
|---|---|---|---|
| C1 | B has the addon disabled | B shown as `?` | B is not listed at all; popup may read `(not in a group)` |
| C2 | B on a different `ns.PROTOCOL` (edit the constant locally) | `?  (incompatible addon version)`; B's queries unanswered | Expected to work |
| C3 | B leaves the group | B disappears from A's popup and from `/qt status` | Dropped on roster change |
| C4 | B turns the quest in after answering "no" | A's next ask shows "yes" | Works only on a **re-ask**; the cached "no" stays until then |
| C5 | A opens the same quest twice | One ask, not two | Deduped by quest ID — but never re-asked for a member who joined later |
| C6 | Rapid clicking through 5+ quests | No disconnect, no missing answers | No throttle on `Q`/`A` exists — only `H` is debounced. Observe and record |
| C7 | Instance / LFG group | Round-trip works | `INSTANCE_CHAT` is not handled — expected to fail |
| C8 | Cross-realm peer with the **same character name** as another peer, or as you | Distinct entries | Collide (keyed by bare name) |
| C9 | A peer sends a zero, fractional, negative or out-of-range quest ID | Ignored silently: no answer is sent for it, nothing is cached for it | Expected to work |
| C10 | B leaves, then A re-ask about the same quest | B is `?` again, never a stale `yes`/`no` from before they left | Expected to work |
| C11 | Both clients change zone at the same time | Peers may briefly read `?`, then fill back in within a few seconds as every client re-announces on `PLAYER_ENTERING_WORLD` (debounced) | Expected to work |
