# Roadmap

Milestones, the M0 go/no-go gate, risk register and testing strategy.

> Part of the Quest Together Forever design docs — index: [`PLAN.md`](../PLAN.md). Sections are
> marked **Implemented**, **Partially implemented** or **Planned**; for current
> behaviour the code is authoritative.

---

## Milestones

### M0 — Ground truth · ~0.5 day · **GO / NO-GO GATE**

**This milestone can kill the project, which is exactly why it runs first.**

- [x] Confirm the client's real identity — `1.60.1`, build `69893`, `tocversion`
      `16001`. The "discrepancy" was a false alarm: `1.60.1` packs to `16001`.
- [x] Confirm `C_ChatInfo.RegisterAddonMessagePrefix("QTOG")` succeeds.
- [x] Confirm `C_QuestLog.IsQuestFlaggedCompleted(id)` returns sane values — verified
      bidirectionally against a real quest turn-in. See
      [the fourth run](MEASUREMENTS.md#fourth-run--the-oracle-is-confirmed).
- [x] Verify no secret-value restriction touches **quest** APIs — quest data is clean;
      the oracle returns a plain boolean. Residual concern is group identity while
      instanced, which needs two clients.
- [ ] **Confirm addon messages round-trip between two grouped clients.**
      ← the only item still open, and the only one that can kill the project.

> **Instrumented by v0.1.** The measurement probes that closed the first four items
> (`/qt env`, `/qt probe`) were retired on 2026-09-21 — their results are recorded in
> [`MEASUREMENTS.md`](MEASUREMENTS.md#measurements-and-open-questions). The one remaining item — the fifth, the round-trip —
> needs two grouped clients; the step-by-step procedure is in
> [`docs/TESTING.md`](TESTING.md).

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
- [x] Graceful handling of peers joining and leaving mid-session. *(Leaving: `ns.PrunePeers`
      on roster change. Joining: the first message from a peer marks them.)*

### M3 — Completion query protocol · ~2 days

- [ ] Bitstream codec: `packBits` / `packIDs` with round-trip tests.
- [ ] `QREQ` / `QREP` with sequence correlation and 3-second timeouts. *Partial:*
      the single-quest revision-2 `Q` / `A` exchange with a 3-second reply window.
- [ ] Request coalescing and the sliding-window throttle.
- [x] The tri-state cache, including the "never write `false` from absence" invariant
      — `ns.RecordAnswer`, with its unit test in `tests/test_tristate.lua`.
- [x] `/qt status` debug output.

### M4 — UI integration · ~2.5 days

- [ ] Quest log row annotations.
- [ ] NPC gossip/available-quest list annotations (single coalesced request).
- [ ] Tooltip integration.
- [ ] Settings panel bound to the privacy toggles. *Partial:* the panel exists
      (Options → AddOns, `/qt config`) with two test checkboxes that do nothing, and a
      "Copy debug info" button. **Built before the M0 gate closed**, at the user's
      request: a scaffold only — no setting changes behaviour yet.

### M5 — Hardening and release · ~2 days

- [x] `pcall` discipline on every inbound message handler — malformed input from a
      peer must never produce a Lua error in *your* session. Field validation now
      covers quest IDs (`ns.ValidQuestID`: positive integer below `2^31`); `status`
      and `rev` were already checked.
- [ ] SavedVariables settings persistence with schema migration.
- [ ] Localisation scaffolding (`enUS` first).
- [ ] Full bug sweep with two live clients.
- [x] GitHub tag-release packaging: `.pkgmeta` + BigWigs-packager workflow.
- [x] CurseForge upload (project ID `1706296`), wired on every pushed tag via a
      `CF_API_KEY` secret. Wago upload is still stubbed out.

**Total: ~9–11 focused days to a polished v1.**

---

## Risk register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | No API for peers' quest state (C1) | Fatal to the naive design | Certain | **Already designed around.** P2P via addon messaging. |
| R2 | Forever's secret-value restrictions block quest or identity APIs | Fatal | **Largely retired** | Measured 2026-09-20: `issecretvalue` exists, but `IsQuestFlaggedCompleted` returns a plain boolean. Quest data is clean. Residual: group identity while instanced — test while grouped; fall back to `name-realm` if `UnitGUID` misbehaves. |
| R3 | Addon comms restricted or throttled harder than expected | Fatal | **Unresolved — the last gate** | Prefix registration succeeds, but no message has yet crossed between two clients. **Test grouped before building any further.** If throttled, cut `LOGS` frequency and widen the coalescing window. |
| R4 | Unknown rendered as "not completed" | Silently wrong advice | **Medium** | Tri-state model, single write path, explicit unit test, distinct glyphs. |
| R5 | Blizzard frame hooks break on patch | Feature loss | High (long term) | v1 avoids hard hooks; tooltips + standalone panel are resilient surfaces. |
| R6 | A **silent** peer in an otherwise-enabled group — no addon, incompatible revision, or no reply | Degraded view for that one member | Certain | The [premise](ARCHITECTURE.md#premise) covers the common case; participants are expected to have it. Residual silence renders as `?`, with a hint distinguishing "no addon" from "no response". |
| R7 | TOC `Interface` number unknown / `16001` inconsistent | Addon won't load | **Retired** | Closed by [Q1](MEASUREMENTS.md#open-questions): `16001` is correct and the addon loads. Re-check on every client patch. |
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
declared. It is configured in `.luacheckrc` and runs in CI (`.github/workflows/lint.yml`).

**Resolved 2026-09-21 — for static checks.** Earlier the modules were only
parse-checked with a machine-local `luac -p`, which is not reproducible and does not
cover the bug class above. `luacheck` in CI replaces it.

**Largely resolved — for runtime behaviour too.** `lua5.1 tests/run.lua` loads every
module in `.toc` order against a fake client and exercises the receive path, so the
cross-module "call only at runtime" rule is now checked by something other than a
`/reload`: a load-time call into another module fails the suite. What the suite
still cannot see is the client itself — whether an API exists, what an event
carries, whether a message crosses between two clients. That is what
[`TESTING.md`](TESTING.md) is for.

---

## Testing strategy

> **Status: Partially implemented.** Layers 1 and 3 run offline in CI
> (`lua5.1 tests/run.lua`). Layer 2 is unnecessary for what the suite already
> reaches — `/qt test` is not implemented and may never need to be. Layer 4 is
> the written manual checklist in [`docs/TESTING.md`](TESTING.md).

**Layer 1 — Pure functions, offline.** *Implemented for the revision-2 format.*
`ns.ParseMessage` is pure (text in, table or nil out) and is covered by
`tests/test_parser.lua`. `tests/harness.lua` fakes the client and loads the real
modules in `.toc` order, so the tri-state invariant and the answering rules are
tested through the real receive path too.

The codec is still the most bug-prone component ahead and the easiest to test.
`packBits`/`packIDs` get round-trip property tests plus hand-computed vectors,
including edge cases: empty set, single ID, deltas crossing varint boundaries, and
a full 64-value alphabet cycle. Write them test-first on top of the harness.

**Layer 2 — In-game unit harness.** A `/qt test` entry point runs assertions against
a mocked peer table and prints a pass/fail summary. Covers the tri-state cache
invariants, sequence correlation, and timeout expiry.

**Layer 3 — Protocol hardening.** *Implemented:* `tests/test_dispatch.lua` feeds
malformed, truncated, oversized and adversarial payloads into the receive
dispatcher. **Success criterion: no Lua error, ever** — every handler wrapped in
`pcall`, every field validated before use. A malicious or buggy peer must not be
able to break your client.

**Layer 4 — Two-client manual test.** Two accounts, grouped, live realm. The only
way to validate the throttle, coalescing, and roster-change behaviour meaningfully.
A written checklist per milestone, executed before that milestone is called done.

**Layer 5 — Adversarial UX review.** Deliberately test the failure matrix: peer
without addon, peer outdated, peer leaving mid-request, request timeout, and rapid
quest-frame clicking. Each must produce an honest, non-misleading state.
