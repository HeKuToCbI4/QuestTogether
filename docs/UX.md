# UX specification

Target presentation. Mostly planned; the "as built" note says what exists.

> Part of the Quest Together design docs — index: [`PLAN.md`](../PLAN.md). Sections are
> marked **Implemented**, **Partially implemented** or **Planned**; for current
> behaviour the code is authoritative.

---

## UX specification

> **Status: Planned.** As built, v0.0.2 has one surface: a fixed (not movable) text
> popup beside the quest frame, toggled with `/qt ui` — `/qt` itself *asks*. It prints
> quest IDs rather than titles and words ("yes" / "no" / "on it now" / "?") rather
> than glyphs. It *does* list the whole group roster, and it distinguishes "Not in a
> group." from "None of your group has Quest Together." as the table below specifies.

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
| Member without the addon | `?  (no addon heard from)` — *implemented* (words, not a tooltip). |
| Peer outdated | `?` for that member, tooltip explains the version mismatch. |
| Request in flight | Brief spinner/ellipsis, resolving to a real state within 3 s. |
| Answer timed out | `?`, with tooltip "No response" — distinct from "no addon". |

*As built:* the first three rows are implemented as plain words rather than glyphs
and tooltips. "Answer timed out" reads `?  (no answer)`, which is already distinct
from `?  (no addon heard from)`. When the roster cannot be read at all, the panel
falls back to listing only the peers it has heard from — an unreadable roster is
unknown, not empty.

That last row is a good example of the tri-state discipline: the user can tell the
difference between *they don't have the addon*, *they have it but didn't answer*,
and *the answer is genuinely no*.
