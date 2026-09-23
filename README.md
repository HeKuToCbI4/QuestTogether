# Quest Together Forever

> **See, before you pull, who in your party has already done this quest.**

You're grouped with a friend. You walk up to an NPC and there's a quest. Do they
need it too, or are you about to drag them through content they finished months ago?

Quest Together Forever answers that. It asks everyone in your group about the quest you are
looking at, and shows you who has already completed it.

> **Status:** v0.0.3 — early prototype. Chat-driven, plus a minimal status popup.
> The addon-message round-trip between two real clients is **not yet verified**
> (see [`docs/TESTING.md`](docs/TESTING.md)). What works today and what is only
> planned are listed separately [below](#what-it-does).

---

## How it works, in one paragraph

Quest completion is stored server-side and is never sent to other players' clients,
so there is nothing to query about a groupmate's quest history. Quest Together Forever works
the only way it can: **each client answers questions about its own character**, over
addon-to-addon messages, within the group.

**Everyone in the group runs the addon.** That is the premise of the design, not a
caveat attached to it.

**"We don't know" is never rendered as "no."** A false ✗ would send you and a friend
on a quest one of you has already finished — the exact failure this addon exists to
prevent.

What you see for a group member:

| Situation | v0.0.3 (today) | Planned |
|---|---|---|
| Peer running the addon, answered | `yes` / `no` / `on it now` | ✓ / ✗ / ◈ glyphs |
| Peer running the addon, no answer (yet, or timed out) | `?  (no answer)` | `?` with a "no response" hint |
| Peer on an incompatible protocol revision | `?  (incompatible addon version)` | same, with an "outdated" hint |
| Peer **not** running the addon | `?  (no addon heard from)` | `?` with a "no addon" hint |
| Peer who has left the group | Dropped on roster change | same |
| Nobody else in the group has the addon | Every member `?`, above the hint "None of your group has Quest Together Forever." | same |
| You're solo | Popup shows your own state only, under "Not in a group." | same |

The list is driven by the **group roster**, so every member of your group gets a
line whether or not they run the addon — and each "?" is worded differently, so
you can always tell *why* an answer is missing. None of them is ever rendered
as "no".

---

## What it does

### Works today (v0.0.3)

- **Status popup beside the quest frame.** Open a quest at an NPC: the popup shows
  your own completion state (live from the client) and one line per group member,
  taken from the roster so that nobody is silently missing.
- **Auto-ask.** Opening a quest — offered, in progress or ready to turn in — asks the
  group about it, silently: the answers appear in the popup, not in chat. Every
  opening asks afresh, so the popup shows what is true *now*, not a cached answer.
- **Chat output.** For `/qt` only: answers print live as they arrive. After 3 seconds
  the members who did *not* answer are listed — nobody is printed twice.
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

Copy `QuestTogetherForever.toc` and the `.lua` files it lists into

```
<World of Warcraft>\_classic_beta_\Interface\AddOns\QuestTogetherForever\
```

The folder **must** be named `QuestTogetherForever` — the client loads `<FolderName>.toc`
and nothing else, and fails silently when they differ. The path was confirmed on the
live beta client on 2026-09-21 ([Q2](docs/MEASUREMENTS.md#open-questions)); the
`_classic_beta_` part will change when the game leaves beta.

Then `/reload`, and enable **Quest Together Forever** in the AddOns list.

---

## Usage

Open a quest at an NPC and the status popup appears beside it — the group is
asked automatically, without printing anything to chat. `/qt` re-asks on demand
and reports in chat, and `/qt ui` toggles the popup solo for testing.

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
| `/qt channel` | Probe instance-group detection and the channel messages would use |
| `/qt sendtest` | Print what `SendAddonMessage` returns here (run solo and grouped) |
| `/qt realm` | Print what the client reports as your name and realm |
| `/qt roster` | Print how the client spells the other group members (run grouped) |

For a `/qt` you typed, answers print live as they arrive; after 3 seconds the members
who did not answer are listed (nothing, if everybody answered); the automatic ask when you open a quest prints nothing at all.
Peers that never answer stay `?` — never "no".

---

## Privacy

Quest Together Forever broadcasts information about your character to the people you group
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
    group roster changes, and in reply to another member's announcement if you have
    not sent one recently. Bursts are coalesced into one message every few seconds.
  - A completion answer is sent **automatically** whenever any group member asks
    (their `/qt`, or them simply opening a quest). You are not prompted.
- **Control: there is none yet.** v0.0.3 has no settings. The only way to stop
  answering is to disable the addon — peers then see no entry for you. Two
  independent toggles (answer queries / share quest log) are planned
  ([data model](docs/ARCHITECTURE.md#data-model)) and tracked as an issue.

Nothing is transmitted to any third party, no server, no analytics.

---

## Compatibility

Quest Together Forever is built for **WoW Forever**. Verified against the live client on
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
QuestTogetherForever/
├── QuestTogetherForever.toc  # filename MUST equal the folder name
├── Compat.lua           # client API surface, secret guards, the completion oracle
├── Peers.lua            # peer registry; home of the tri-state invariant
├── Protocol.lua         # wire format and transport
├── Query.lua            # asking the group about a quest, and reporting answers
├── Commands.lua         # user-facing slash commands, incl. /qt help
├── Config.lua           # settings panel, settings, "Copy debug info"
├── Diagnostics.lua      # solo verification tools (deletable before release)
├── UI.lua               # the status popup panel
├── Core.lua             # bootstrap, events, slash dispatch
├── README.md
├── CLAUDE.md            # rules of the road for AI agents (and new contributors)
├── PLAN.md              # index of the design docs
├── CHANGELOG.md
├── .pkgmeta             # packaging manifest for the release zip
├── .github/
│   └── workflows/       # CI (luacheck, tests, link check) and tag-driven releases
├── docs/
│   ├── ARCHITECTURE.md  # premise, constraints C1-C7, decisions D1-D5, data model
│   ├── PROTOCOL.md      # wire protocol: revision 2 (built), revision 3 (planned)
│   ├── UX.md            # target presentation
│   ├── ROADMAP.md       # milestones M0-M5, risks R1-R11, testing strategy
│   ├── MEASUREMENTS.md  # live-client measurements, open questions Q1-Q7, API sheet
│   └── TESTING.md       # manual test checklists (incl. the two-client M0 gate)
├── tests/               # offline suite: `lua5.1 tests/run.lua`, no dependencies
│   ├── harness.lua      # a fake WoW client; loads the modules in .toc order
│   ├── run.lua          # discovers test_*.lua, runs them, exits non-zero on failure
│   └── test_*.lua       # parser, tri-state invariant, revisions, answers, dispatch
└── tools/
    └── linkcheck.py     # verifies markdown links and anchors
```

`tests/` is not listed in the `.toc`, so the client never loads it.

### Releases

Push a tag (`git tag vX.Y.Z && git push origin vX.Y.Z`) and
`.github/workflows/release.yml` packages the addon with the BigWigs packager, attaching
a zip to a GitHub release and uploading it to CurseForge. The zip holds only what the
client loads — the `.toc` and the nine `.lua` files — per `.pkgmeta`.

The CurseForge upload needs one repository secret, `CF_API_KEY`: a CurseForge API
token (not your password or an Overwolf token) with permission to upload files to
project `1706296`. Add it under **Settings → Secrets and variables → Actions**, then
push a tag. Without the secret the upload is skipped and the release is GitHub-only.

### Load order

`Compat → Peers → Protocol → Query → Commands → Config → Diagnostics → UI → Core`, as listed
in the `.toc`.

The rule: modules reach each other through `ns` and must only ever **call** across
module boundaries at runtime. A cross-file call during load is the same
forward-reference trap that crashed the first prototype.

Only `Compat.lua` has to be first: it declares the registries (`ns.commands`,
`ns.answerListeners` via `ns.OnAnswer`, `ns.helpLines` via `ns.AddHelp`,
`ns.debugSections` via `ns.AddDebugSection`) that the
other modules add themselves to at load. Every other file can be reordered, or
deleted, without anything else noticing.

### Why these nine files

| Module | Owns | Changes when |
|---|---|---|
| `Compat` | Every assumption about the client's API | The client's API changes |
| `Peers` | What we know about group members | Cache policy changes |
| `Protocol` | Wire format, send/receive | The protocol revision bumps |
| `Query` | `ns.Ask`, pending asks, the live lines and the summary | Asking or reporting changes |
| `Commands` | Slash commands that do real work, and `/qt help` | Command UX changes |
| `Config` | Settings, the settings panel, the debug report | A setting is added |
| `Diagnostics` | Local verification tools | A new surface needs measuring |
| `UI` | The status popup panel | The panel's presentation changes |
| `Core` | Bootstrap and event wiring | Wiring changes |

**`Diagnostics.lua` is deletable.** No other module calls into it, it owns its own
event frame, and its commands and help lines are registered rather than wired in.
Delete the file and its `.toc` line and everything else — `/qt help` included —
keeps working, minus the two probes.

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
