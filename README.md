# Quest Together

> **See, before you pull, who in your party has already done this quest.**

You're grouped with a friend. You walk up to an NPC and there's a quest. Do they
need it too, or are you about to drag them through content they finished months ago?

Quest Together answers that. It annotates the quests you look at with the
completion status of everyone in your group.

> **Status:** v0.0.2 — chat-driven, plus a minimal status popup. See
> [`PLAN.md`](PLAN.md) for what v0.2+ adds.

---

## How it works, in one paragraph

Quest completion is stored server-side and is never sent to other players' clients,
so there is nothing to query about a groupmate's quest history. Quest Together works
the only way it can: **each client answers questions about its own character**, over
addon-to-addon messages, within the group.

**Everyone in the group runs the addon.** That is the premise of the design, not a
caveat attached to it.

When there's no answer for someone, we say so:

| Situation | What you see |
|---|---|
| Peer running the addon | ✓ / ✗ shown for them |
| Peer not running the addon | `?` — unknown |
| Peer on an incompatible version | `?` plus an "outdated" hint |
| Answer in flight, or timed out | `?` |
| You're solo | Everything works; nobody to compare against |

**"We don't know" is never rendered as "no."** A false ✗ would send you and a friend
on a quest one of you has already finished — the exact failure this addon exists to
prevent.

---

## What it does

**Quest detail view** — open any quest at an NPC and see, per party member, whether
they've already turned it in. This is the primary use case.

**Quest log annotations** — every quest in your own log, labelled with who in the
group still needs it. Turns "let's go do some quests" into "let's go finish *these*."

**Available-quest lists** — when an NPC offers several quests, all of them are
annotated at once, so you can pick the one you both actually need.

**Who's already on it** — party members who currently have the quest in their log
are marked separately from those who've completed it. This is cheap to compute
(quest logs are ~25 entries) so it's synced eagerly rather than on demand.

---

## Install

Drop the addon folder into your client's `Interface/AddOns/` directory.

> **Note:** the exact install path for WoW Forever is unconfirmed — see
> [Open Questions](PLAN.md#open-questions). Reports indicate Forever reads the
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

Solo verification tools — these run with one client and nobody else online:

| Command | Effect |
|---|---|
| `/qt events` | Toggle tracing of quest events and their arguments |
| `/qt frames` | List the UI objects v0.2 would hook |

Answers print live as they arrive, then a summary follows after 3 seconds. Peers
that never answer stay `?` — never `✗`.

A minimal status popup ships now; the full panel and quest-log annotations are
specified in [`PLAN.md`](PLAN.md#ux-specification) and still to come.

---

## Privacy

Quest Together broadcasts information about your character to the people you group
with. That is the entire mechanism, so it deserves to be said out loud rather than
buried:

- **What is shared:** which quests you have completed, and which quests are
  currently in your log.
- **Who receives it:** only members of your current group, over the group-only
  addon channel. Messages are never sent to a public channel and never leave your
  group.
- **When:** completion data is sent only when you ask — explicitly with `/qt`, or
  automatically when you open a quest (v0.0.2). Nothing is broadcast unprompted.
  (v0.2 plans to additionally broadcast your active quest log when it changes —
  about 25 quest IDs — behind a separate toggle.)
- **Control:** both behaviours can be disabled independently in settings. If you
  stop responding, peers see `?` for you — the same state as not having the addon.

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
[`PLAN.md`](PLAN.md#measurement--2026-09-20).

Classic Era / Wrath / Cataclysm Classic are **not** currently targets. Quest IDs
differ between those worlds, so raw data is not portable between them — though the
protocol itself is flavor-agnostic and a shim is plausible later.

---

## Repository state

```
QuestTogether/
├── QuestTogether.toc    # filename MUST equal the folder name
├── Compat.lua           # client API surface, secret guards, the completion oracle
├── Peers.lua            # peer registry; home of the tri-state invariant
├── Protocol.lua         # wire format and transport
├── Commands.lua         # user-facing slash commands
├── Diagnostics.lua      # solo verification tools — dev only, deletable
├── UI.lua               # the status popup panel
├── Core.lua             # bootstrap, events, slash dispatch
├── README.md
└── PLAN.md
```

### ⚠️ Rename the folder before your next `/reload`

The client loads `<FolderName>.toc` and nothing else. The folder is currently
`WowQuestAddon` while the `.toc` is `QuestTogether.toc`, **so the addon will not load
at all** until the folder is renamed to match. It fails *silently* — no error, the
addon simply isn't in the list.

If your `Interface/AddOns/WowQuestAddon/` is a copy or a symlink, re-point it at the
renamed folder too.

### Load order

`Compat → Peers → Protocol → Commands → Diagnostics → UI → Core`, as listed in the `.toc`.
Order matters only for *definitions*: modules reach each other through `ns` and must
only ever **call** across module boundaries at runtime. A cross-file call during load
is the same forward-reference trap that crashed v0.1.

### Why these seven files

| Module | Owns | Changes when |
|---|---|---|
| `Compat` | Every assumption about the client's API | The client's API changes |
| `Peers` | What we know about group members | Cache policy changes |
| `Protocol` | Wire format, send/receive | The protocol revision bumps |
| `Commands` | Slash commands that do real work | Command UX changes |
| `Diagnostics` | Local verification tools only | Never — it's disposable |
| `UI` | The status popup panel | The panel's presentation changes |
| `Core` | Bootstrap and event wiring | Wiring changes |

**`Diagnostics.lua` can be deleted before release.** Nothing else depends on it, and
it owns its own event frame precisely so that stays true.

### The old stub `.toc` is gone

`QuestWithFirends.toc` has been deleted. It was never read — the filename didn't match
the folder (`Firends`, transposed) — and it carried a placeholder
`## Interface: 99999`, an empty `## SavedVariables:`, an empty `## RequiredDeps:`
directive, and a bogus `X-Curse-Project-ID: 999999`.

---

## Documentation

| Document | Contents |
|---|---|
| [`PLAN.md`](PLAN.md) | Architecture, wire protocol, milestones, risks, testing strategy |

---

## Sources

The WoW Forever platform facts above are drawn from press and community reporting
on the beta that opened 2026-09-17:

- [WoW: Forever Will Have Addon Changes from Midnight — Wowhead](https://www.wowhead.com/wotlk/news/wow-forever-will-have-addon-changes-from-midnight-382921)
- [Addons in WoW Forever? Blizzard Devs Just Addressed the Big Question — Icy Veins](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/)
- [WoW Forever Loads Your Retail Addons & Keybinds — Warcraft Tavern](https://www.warcrafttavern.com/forever/news/wow-forever-loads-your-retail-addons-keybinds/)
- [API GetBuildInfo — Warcraft Wiki](https://wowpedia.fandom.com/wiki/API_GetBuildInfo)

These are secondary sources describing a beta client. Treat the API specifics as
claims to verify in-game, not as documentation — `PLAN.md` tracks which ones are
still open.
