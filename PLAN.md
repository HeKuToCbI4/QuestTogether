# Quest With A Friend — Design & Implementation Plan

**Target client:** WoW Forever (Mainline-derived UI architecture)
**Document status:** Draft v2 — 2026-09-21 (synced with the v0.0.2 code)
**Companion:** [`README.md`](README.md) · [`docs/TESTING.md`](docs/TESTING.md) · [`CHANGELOG.md`](CHANGELOG.md)

> **How to read these documents.** They are mostly a *design target*, not a description
> of the code. Sections are marked **Implemented**, **Partially implemented** or
> **Planned**. For current behaviour the code is authoritative.
>
> **Version names.** The shipped addon is `0.0.2` (see the `.toc`). "v0.1" in the
> measurement log refers to the first single-file prototype, before the code
> was split into modules. "v0.2" means the next planned release. "v1" is the polished
> target this plan describes.

---

The plan is split by concern, so you only need to read the part you are changing:

| Document | Contents |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Why the addon is shaped the way it is: premise, constraints, decisions, data model, non-goals. |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | The implemented revision-2 protocol, and the planned batched revision 3. |
| [`docs/UX.md`](docs/UX.md) | Target presentation. Mostly planned; the "as built" note says what exists. |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Milestones, the M0 go/no-go gate, risk register and testing strategy. |
| [`docs/MEASUREMENTS.md`](docs/MEASUREMENTS.md) | What was measured on the live client, open questions, and the API cheat sheet. |
| [`docs/TESTING.md`](docs/TESTING.md) | Manual test checklists — solo smoke test, the two-client M0 gate, failure matrix. |

Identifiers used across code and docs: **C1–C7** constraints and **D1–D5** decisions
live in ARCHITECTURE; **M0–M5** milestones and **R1–R11** risks in ROADMAP; **Q1–Q7**
open questions in MEASUREMENTS.
