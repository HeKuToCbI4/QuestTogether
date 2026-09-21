# Quest Together

> **See, before you pull, who in your party has already done this quest.**

You're grouped with a friend. You walk up to an NPC and there's a quest. Do they
need it too, or are you about to drag them through content they finished months ago?

Quest Together answers that. It asks everyone in your group about the quest you are
looking at, and shows you who has already completed it.

> **Status:** v0.0.2 — early prototype. Chat-driven, plus a minimal status popup.
> The addon-message round-trip between two real clients is **not yet verified**
> (see [`docs/TESTING.md`](docs/TESTING.md)). What works today and what is only
> planned are listed separately [below](#what-it-does).

---

## How it works, in one paragraph

Quest completion is stored server-side and is never sent to other players' clients,
so there is nothing to query about a groupmate's quest history. Quest Together works
the only way it can: **each client answers questions about its own character**, over
addon-to-addon messages, within the group.

**Everyone in the group runs the addon.** That is the premise of the design, not a
caveat attached to it.

**"We don't know" is never rendered as "no."** A false ✗ would send you and a friend
on a quest one of you has already finished — the exact failure this addon exists to
prevent.

What you see for a group member:

| Situation | v0.0.2 (today) | Planned |
|---|---|---|
| Peer running the addon, answered | `yes` / `no` / `on it now` | ✓ / ✗ / ◈ glyphs |
| Peer running the addon, no answer (yet, or timed out) | `?  (no answer)` | `?` with a "no response" hint |
| Peer on an incompatible protocol revision | `?  (incompatible addon version)` | same, with an "outdated" hint |
| Peer **not** running the addon | **Not listed at all** — the popup only knows peers it has heard from | Listed as `?` |
| Peer who has left the group | Dropped on roster change | same |
| You're solo | Popup shows your own state only | same |

One gap remains — a member without the addon is not listed at all; it is tracked as
an issue. A group member missing from the popup therefore means "no addon heard
from" — **not** "no".

---

## What it does

### Works today (v0.0.2)

- **Status popup beside the quest frame.** Open a quest at an NPC: the popup shows
  your own completion state (live from the client) and every peer heard from.
- **Auto-ask.** Opening a quest asks the group about it once per quest ID.
- **Chat output.** Answers print live as they arrive; a summary follows after
  3 seconds.
- **"On it now".** A peer who has the quest in their log but has not completed it is
  reported separately from a plain "no".
- **Version check.** Peers on a different protocol revision are marked incompatible
  and never answered or parsed.

### Planned (not implemented)

Specified in [`docs/UX.md`](docs/UX.md#ux-specification); none of this exists yet:

- **Quest log annotations** — every quest in your log, labelled with who still needs it.
- **Available-quest lists** — all quests an NPC offers annotated at once.
- **Eager quest-log sync** — "who's on it" without asking.
- **Tooltips, glyph markers, settings panel, privacy toggles.**

---

## Install

Drop the addon folder into your client's `Interface/AddOns/` directory. The folder
**must** be named `QuestTogether` — the client loads `<FolderName>.toc` and nothing
else, and fails silently when they differ.

> **Note:** the exact install path for WoW Forever is unconfirmed — see
> [Open Questions](docs/MEASUREMENTS.md#open-questions) (Q2). Reports indicate Forever reads the
> Mainline addon directory. Verify before publishing install instructions.

Then `/reload`, and enable **Quest Together** in the AddOns list.

---

## Usage

Open a quest at an NPC and the status popup appears beside it — the group is
asked automatically. `/qt` re-asks on demand, and `/qt ui` toggles the popup
solo for testing.

| Command | Effect |
|---|---|
| `/qt` | Ask your group about the quest currently open |
| `/qt ask <questID>` | Ask about a specific quest ID |
| `/qt ping` | Announce yourself to the group |
| `/qt status` | List peers heard from, and how much we know about them |
| `/qt ui` | Toggle the status popup (works solo) |
| `/qt help` | List commands |

Solo verification tools — these run with one client and nobody else online:

| Command | Effect |
|---|---|
| `/qt events` | Toggle tracing of quest events and their arguments |
| `/qt frames` | List the UI objects M4 would hook |

Answers print live as they arrive, then a summary follows after 3 seconds. Peers
that never answer stay `?` — never "no".

---

## Privacy

Quest Together broadcasts information about your character to the people you group
with. That is the entire mechanism, so it deserves to be said out loud rather than
buried:

- **What is shared:** for any quest ID a group member asks about — whether you have
  completed it, and whether it is currently in your log. Also the bare fact that you
  run the addon, and its protocol revision.
- **Who receives it:** only members of your current group, over the group-only
  addon channel. Replies are broadcast to the whole group, not only to the asker.
  Messages are never sent to a public channel and never leave your group.
- **When:**
  - A presence announcement is sent **automatically** when you enter the world, on
    group roster changes, and in reply to a group member you had not heard from
    before. Bursts are coalesced, so it is at most one message every few seconds.
  - A completion answer is sent **automatically** whenever any group member asks
    (their `/qt`, or them simply opening a quest). You are not prompted.
- **Control: there is none yet.** v0.0.2 has no settings. The only way to stop
  answering is to disable the addon — peers then see no entry for you. Two
  independent toggles (answer queries / share quest log) are planned
  ([data model](docs/ARCHITECTURE.md#data-model)) and tracked as an issue.

Nothing is transmitted to any third party, no server, no analytics.

---

## Compatibility

Quest Together is built for **WoW Forever**. Verified against the live client on
2026-09-20 (version `1.60.1`, build `69893`, `tocversion` `16001`):

- The full modern addon API is available — `C_ChatInfo`, `C_QuestLog`, `C_GossipInfo`,
  `C_Timer`, `issecretvalue`. The protocol and UI here are written against it.
- **Every legacy global is gone.** `SendAddonMessage`, `RegisterAddonMessagePrefix`
  and `IsQuestFlaggedCompleted` do not exist as globals.
- Quest completion data is **not** affected by the secret-values restrictions:
  `IsQuestFlaggedCompleted` returns a plain boolean.
- **There is no built-in party quest progress.** `GetQuestPartyProgress`,
  `QuestHasPartyProgress` and `GetQuestLogPartyMembers` are all absent, so this addon
  isn't duplicating native UI — the feature genuinely doesn't exist without it.

### ⚠️ Do not branch on the client version

Forever reports itself as `1.60.1`. That looks like a Classic-era version number, and
it is not one — the client carries a fully modern API surface with the legacy globals
removed.

Any addon written with the usual idiom:

```lua
if select(4, GetBuildInfo()) < 80000 then
    -- "old client" code path
end
```

will take the classic branch on Forever and be **wrong about everything**. Branch on
API presence (`if C_ChatInfo and C_ChatInfo.SendAddonMessage then`), never on the
version number.

Full measurements and the still-open items are in
[`docs/MEASUREMENTS.md`](docs/MEASUREMENTS.md#measurement--2026-09-20).

Classic Era / Wrath / Cataclysm Classic are **not** currently targets. Quest IDs
differ between those worlds, so raw data is not portable between them — though the
protocol itself is flavor-agnostic and a shim is plausible later.

---

## For developers

```
QuestTogether/
├── QuestTogether.toc    # filename MUST equal the folder name
├── Compat.lua           # client API surface, secret guards, the completion oracle
├── Peers.lua            # peer registry; home of the tri-state invariant
├── Protocol.lua         # wire format and transport
├── Commands.lua         # user-facing slash commands
├── Diagnostics.lua      # solo verification tools + /qt help
├── UI.lua               # the status popup panel
├── Core.lua             # bootstrap, events, slash dispatch
├── README.md
├── CLAUDE.md            # rules of the road for AI agents (and new contributors)
├── PLAN.md              # index of the design docs
├── CHANGELOG.md
├── docs/
│   ├── ARCHITECTURE.md  # premise, constraints C1-C7, decisions D1-D5, data model
│   ├── PROTOCOL.md      # wire protocol: revision 2 (built), revision 3 (planned)
│   ├── UX.md            # target presentation
│   ├── ROADMAP.md       # milestones M0-M5, risks R1-R11, testing strategy
│   ├── MEASUREMENTS.md  # live-client measurements, open questions Q1-Q7, API sheet
│   └── TESTING.md       # manual test checklists (incl. the two-client M0 gate)
└── tools/
    └── linkcheck.py     # verifies markdown links and anchors
```

### Load order

`Compat → Peers → Protocol → Commands → Diagnostics → UI → Core`, as listed in the `.toc`.

The rule: modules reach each other through `ns` and must only ever **call** across
module boundaries at runtime. A cross-file call during load is the same
forward-reference trap that crashed the first prototype.

**Known exception:** `UI.lua` *reads* `ns.onAnswer` (set by `Commands.lua`) and
`ns.commands.help` (set by `Diagnostics.lua`) at load time in order to wrap them.
That makes `UI.lua`'s position after both of them load-bearing. Replacing the wrap
chains with registries is tracked as an issue.

### Why these seven files

| Module | Owns | Changes when |
|---|---|---|
| `Compat` | Every assumption about the client's API | The client's API changes |
| `Peers` | What we know about group members | Cache policy changes |
| `Protocol` | Wire format, send/receive | The protocol revision bumps |
| `Commands` | Slash commands that do real work | Command UX changes |
| `Diagnostics` | Local verification tools, and `/qt help` | A new surface needs measuring |
| `UI` | The status popup panel | The panel's presentation changes |
| `Core` | Bootstrap and event wiring | Wiring changes |

**`Diagnostics.lua` is *almost* deletable.** No other module calls into it and it
owns its own event frame — but it also defines `/qt help` for every command, so
deleting it today leaves `/qt help` listing only `/qt ui`. Move the help text out
before removing the file for release.

---

## Documentation

| Document | Contents |
|---|---|
| [`PLAN.md`](PLAN.md) | Index of the design docs below |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Premise, constraints, decisions, data model, non-goals |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | Wire protocol — revision 2 (implemented) and revision 3 (planned) |
| [`docs/UX.md`](docs/UX.md) | Target presentation |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Milestones, risks, testing strategy |
| [`docs/MEASUREMENTS.md`](docs/MEASUREMENTS.md) | Live-client measurements, open questions, API cheat sheet |
| [`CLAUDE.md`](CLAUDE.md) | Working rules for AI agents and new contributors; how to run the checks |
| [`docs/TESTING.md`](docs/TESTING.md) | Manual test checklists — solo smoke test and the two-client M0 gate |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

Where the documents and the code disagree, **the code is authoritative** for current
behaviour; the design docs mark each section as *implemented* or *planned*.

---

## Sources

The WoW Forever platform facts above are drawn from press and community reporting
on the beta that opened 2026-09-17:

- [WoW: Forever Will Have Addon Changes from Midnight — Wowhead](https://www.wowhead.com/wotlk/news/wow-forever-will-have-addon-changes-from-midnight-382921)
- [Addons in WoW Forever? Blizzard Devs Just Addressed the Big Question — Icy Veins](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/)
- [WoW Forever Loads Your Retail Addons & Keybinds — Warcraft Tavern](https://www.warcrafttavern.com/forever/news/wow-forever-loads-your-retail-addons-keybinds/)
- [API GetBuildInfo — Warcraft Wiki](https://wowpedia.fandom.com/wiki/API_GetBuildInfo)

These are secondary sources describing a beta client. Treat the API specifics as
claims to verify in-game, not as documentation — `docs/MEASUREMENTS.md` tracks
which ones are still open.
