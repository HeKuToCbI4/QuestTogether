# CurseForge project description

Draft text for the CurseForge project page. The published name is **Quest Together
Forever**, matching the addon folder, `.toc` and GitHub repository
(`quest-together-forever-wow-addon`). CurseForge project ID `1706296` (unlisted — the
public page does not resolve yet).

Edit this file first, then paste into the CurseForge project editor (the description
field renders Markdown).

> **Do not publish yet.** Milestone M0 is open: no addon message has crossed between
> two real clients, so the core mechanism is unverified. The upload tooling is now
> wired — a pushed tag uploads a build to this (still unlisted) project via the
> `CF_API_KEY` secret — but the project page itself stays unpublished until the
> two-client round-trip passes (`docs/TESTING.md` §B). Everything below is written for
> the day that closes.

---

## Summary field

> See which of your party members have already done a quest — before you pull them
> through it again.

(CurseForge truncates the summary; keep it to that one sentence.)

---

## Description

# Quest Together Forever

**See, before you pull, who in your party has already done this quest.**

You're grouped with a friend. You walk up to an NPC and there's a quest. Do they need
it too, or are you about to drag them through content they finished months ago?

Quest Together Forever asks your group about the quest you're looking at and shows you who
has already completed it — right next to the quest frame, without anyone typing
anything.

## How it works

Quest completion is stored server-side and is never sent to other players' clients, so
there is nothing to ask the game about a groupmate's quest history. Each client can
only answer for its own character — so that is what it does, over addon messages
within your group.

**Everyone in the group runs the addon.** That is the premise of the design.

**"We don't know" is never shown as "no".** A false ✗ would send you and a friend on a
quest one of you has already finished — the exact mistake this addon exists to prevent.
A member who hasn't answered, runs a different version, or doesn't have the addon at all
shows `?`, worded so you can tell which of those it is. Everyone in your group gets a
line, whether or not they run the addon.

## What you get today (v0.0.4)

- **Status popup beside the quest frame** — it slides out from under the quest window
  on the same parchment, with your own completion state, read live from the client,
  and one line per group member.
- **Automatic asking** — opening a quest asks the group about it silently. Once per
  quest, and again after someone joins your group.
- **"On it now"** — a member who has the quest in their log but hasn't finished it is
  reported separately from a plain "no".
- **Chat mode** — `/qtf` asks on demand and reports answers in chat.
- **Version check** — peers on an incompatible protocol revision are marked as such and
  never answered or parsed.
- **Settings page** — Esc → Options → AddOns, or `/qtf config`. For now: two test
  checkboxes and **Copy debug info** (also `/qtf debug`), a report to paste into bug
  reports.

Open a quest and the popup appears. `/qtf help` lists the commands.

## Requirements

- **WoW Forever.** Built and measured against the live client (version `1.60.1`).
  Classic Era, Wrath and Cataclysm Classic are not targets yet — quest IDs differ
  between those worlds.
- **Everyone in your group needs the addon.** Members without it show as `?`.

## Privacy

The addon broadcasts information about your character to the people you group with.
That is the whole mechanism, so it is worth stating plainly:

- **Shared:** whether you have completed a quest a group member asked about, whether it
  is in your log, and the bare fact that you run the addon and its protocol version.
- **Who receives it:** only your current group, over the group-only addon channel.
  Never a public channel, never anyone outside the group.
- **When:** a presence announcement goes out when you enter the world and on group
  changes; a completion answer goes out whenever any group member opens a quest or
  types `/qtf`. You are not prompted.
- **No opt-out yet.** v0.0.4 has a settings page but no real settings — the only way to stop answering is to
  disable the addon. Two independent toggles (answer queries / share quest log) are
  planned.

Nothing is sent to any third party, no server, no analytics.

## Status

An early prototype, published for testing with a group that is willing to try it.
The quest-completion reading itself is verified against the live client; the
addon-message round-trip between two clients is still being confirmed before the
feature set grows. Expect the wire format to change, and expect a small number of
commands to exist purely for measuring the client.

## Planned

- Quest log annotations — every quest in your log, labelled with who still needs it.
- Available-quest lists — all quests an NPC offers, annotated at once.
- Tooltips and settings, including the privacy toggles.

## Links

- Source and full design docs: https://github.com/HeKuToCbI4/quest-together-forever-wow-addon
- Issues and feedback are welcome there — especially if you can run it with a full
  group and tell us what the panel showed.

---

## Naming

The addon is named **Quest Together Forever**, matching the GitHub repository
`quest-together-forever-wow-addon`. The folder, the `.toc` filename and `## Title`
always move together, in one change — the client loads `<FolderName>.toc` and
silently skips the addon when the two differ (this already happened once:
`QuestWithFirends.toc` was an early stub, and the folder was renamed from
`WowQuestAddon` for the same reason).

History: `QuestTogether` → `QuestWithAFriend` ("Quest With A Friend", shipped in the
v0.0.2 GitHub release zip) → `QuestTogetherForever`. Anyone who installed the v0.0.2
zip must delete the old `QuestWithAFriend` folder, or both copies load.

`SavedVariables` is now `QuestTogetherForeverDB`. It is unrelated to the display name,
but was renamed alongside everything else because nothing is saved yet; renaming it
later would silently drop people's saved data.

Do not rename again after the first upload — a folder that changes name after people
have installed it loads twice and double-answers.
