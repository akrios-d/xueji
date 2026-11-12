# Xueji — status and backlog

Updated 12 Nov 2026. "Unverified" means written but not yet compiled or run by the author of the code
(there is no Swift toolchain in the authoring environment); the owner builds and reports back.

## Where we are

A working prototype on in-memory sample data. The rules engine is complete and tested; the interface covers
the board, calendar, approval inbox, team, themes and shortcuts. Nothing is saved to disk, and no agent can
talk to the app yet, so the central loop (an external agent proposes, the student decides) is not closed.

| Area | State |
|---|---|
| Core rules: members, tracks, approval, stages, leases, reviews with rounds, comments, events | Done, tested |
| Deadlines, milestones, agenda, overdue | Done, tested, unverified build |
| Item types and fields (4 built-in, custom types, validation) | Done, tested, unverified build |
| Keyboard navigation logic | Done, tested |
| Screens: Board, Calendar, Inbox, Settings, Shortcuts (the Team screen was removed: one person for now) | Done, unverified build |
| Six themes (shared with CogNote), English and Simplified Chinese | Done (Chinese needs native review) |
| App icon | Artwork done; Dock icon wired for the SwiftPM build; real icon needs the Xcode project |
| Xcode project | `project.yml` ready for XcodeGen; not yet generated or opened |

## Backlog

### A. Close the loop (without these it is a demo)
1. **Verify the build and tests** (owner). Blocker for everything below.
2. **Xcode app project** from `project.yml`: real icon, bundle id, signing, entitlements.
3. **Persistence** (SQLite, GRDB): every entity, migrations, event history. Sample data only on first run.
4. **Local REST API** on 127.0.0.1 with per-agent tokens (Keychain): schema, items, claim/complete, reviews, comments. Validation at the boundary.
5. **Reference agent** (external runner) doing the source triage: find, verify links, classify, extract statements.
6. **Create things from the UI**: tracks, members, agents (and their tokens). Today there is one sample track.

### B. Make cards real
7. **Card panel**: all fields of the type, notes written in place, comments, history. First version written (unverified build); still to do: show it from the calendar and the inbox.
8. **Type editor**: create types, fields and options; translate the names of built-in types and fields.
9. **Delete, archive and undo (⌘Z)** for items. The core cannot delete or archive yet.
10. **Review UI**: request a review, resolve it, see the rounds (the core already supports it).
11. **Custom workflows**: stages with a category, one workflow per type, a board per workflow, then transition rules (required fields, who may move) and automations (on entering a stage, request a review).
12. **Phases** (named date ranges per track, e.g. the three periods of the dissertation): a track setting or a choice field. To decide.

### C. Views and outputs
13. **Table and timeline views** driven by fields ("who said what, and when" = Statements grouped by phase).
14. **Progress module** (like CogNote's Insights): delivered on time or late, returned from review, reopened, rounds per card, time per stage, agent approval rate. Needs workflows (categories), richer event history (from → to, initial due day) and persistence.
15. **Export**: triage table, "who said what" by period, reference list (Harvard by default); Markdown and PDF.
16. **Reading order**: sort by role then phase first; a dependency graph only if the student asks for "A before B".

### D. PDFs
17. **Upload and versions**: copy into app storage, content hash, revisions by the supervisor or the student.
18. **Reader (PDFKit)** with highlights, underlines and notes in marking sets (layers), stored apart from the file.
19. **Re-anchoring** markings on a new revision by text, with a "needs review" list.
20. **From a highlight to a Statement** with source, page and quote filled in.

### E. Integrations
21. **Calendar (EventKit)**: one-way mirror of deadlines and milestones into a "Xueji" calendar; other calendars read-only. Needs the Xcode project.

### F. Quality and release
22. Native review of the Chinese strings, plurals and date formats.
23. Accessibility (VoiceOver labels, focus order, contrast in every theme).
24. Onboarding and empty states.
25. Backup: export and import of all data as JSON.
26. Sandbox, hardened runtime, signing, notarization.
27. CI: `swift test` on macOS for every push.
28. Later: iOS app (the core is already UI-free), sync.

## Recommended order

1 → 2 → 3 → 4 → 5 → 6 (a usable product) → 7, 8, 9, 10 → 11 → 14 → 13, 15 → 17–20 → 21.

Reasoning: the progress module and the PDF reader are the most visible, but both are worth little until data
persists and an agent can send work in. Workflows come before progress because "returned from review" and
"done" must look at a stage's category, not its name.

## Decisions still open

- Phases: track setting or choice field (item 12).
- Citation style for export: Harvard assumed (item 15).
- How markings carry over to a revision: re-anchor by text assumed (item 19).
- Dependencies between cards: manual only at first, or also suggested by the agent (item 16).
- Bundle identifier prefix and signing team (item 2).


## PDF import (first version written, unverified build)

- Reads the two layouts the supervisor's PDFs use (source triage table; who-said-what-and-when table with references).
- The parsers live in `XuejiCore/Importing` and are tested with synthetic pages. `PDFPageReader` (PDFKit characters to positioned words) is the one part that has to be checked against the real PDFs.
- Still to do: a preview of the rows before they land in "Inbox"; match triage sources to the full links in a who-said-what reference list; import of the closing "reading order" and "perceptions by period" sections of the triage PDF; other layouts.

### PDF import: tolerance to other PDF makers

- Checked on the supervisor's two PDFs and on the same tables re-made with other engines (WebKit and LibreOffice, A4 and Letter, three fonts): the reading logic finds every row in all of them.
- Fixed from that check: rows near the bottom edge were cut by a fixed margin (now only a lone page number is dropped), and pages that do not repeat the table heading are read with the previous page's columns.
- Known limit: tables whose cells are centred vertically (not top-aligned) are not read, because a row is recognised by its date and reference sitting on the same line.
- Still unchecked: what PDFKit itself reports for these files (see "Save PDF Reading Report…").
