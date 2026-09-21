# Wire protocol

The implemented revision-2 protocol, and the planned batched revision 3.

> Part of the Quest Together design docs — index: [`PLAN.md`](../PLAN.md). Sections are
> marked **Implemented**, **Partially implemented** or **Planned**; for current
> behaviour the code is authoritative.

---

## Wire protocol

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
  same-named characters from different realms and is tracked as a bug ([Q7](MEASUREMENTS.md#open-questions)).

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
