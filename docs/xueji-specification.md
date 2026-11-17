# Xueji 学记 — A native Mac app where students and AI agents work together

> **Xueji** (学记, "record of learning") is a native Mac app (Swift/SwiftUI) for PhD and master's students. It organizes daily academic work in *tracks*: lists of items (readings, sources, chapters, notes) that move through the stages of a kanban. People and AI agents are the same kind of entity (`Member`) and ask each other for work and review. Notes are written in place, directly on the items. Everything is stored in a local SQLite database, and a local REST API lets agents take part from outside. The first use case is research and study: an agent finds papers, checks the links and classifies what to read, and the student approves or discards everything inside the app.

> **Name:** Xueji (学记), chosen with the user. **Languages:** English (base) and Simplified Chinese.

---

## Goals & Non-Goals

### Goals

- Help PhD and master's students organize their **daily work**: what to read, what was found, what to write, what needs a decision.
- Let students **write notes in place**, directly on cards and sources, without opening a separate dialog.
- Validate the model **people and agents as the same kind of member**, with assignment and cross-review.
- Deliver the full **research and triage** flow: ask for a search, receive classified items, approve or discard, follow the reading.
- Make everything doable **inside the app, without a terminal**.
- Keep the core (model, rules, persistence) separate from the interface, so it can be reused on iOS later.
- Work in **English and Simplified Chinese** from the start.

### Non-Goals (first version)

- Multiple users, accounts, or sharing between people.
- Sync and an iOS version.
- An embedded runner (the app starting agents by itself). Agents run outside the app and use the API.
- Kanban stages that can be edited per track.
- Approval rules configurable per track.
- App Store distribution.
- Automatic review between agents (an agent reviewing an agent). See the roadmap.
- Replacing a reference manager: citations and bibliography export are out of scope (assumption).

---

## Scope

| In | Out (for now) |
|---|---|
| Tracks, items, members (people and agents), comments, review requests | Attachments other than PDFs |
| Notes written in place on items | Rich text editing, citations, bibliography export |
| PDFs with markings and a suggested reading order *(proposed)* | Editing the PDF itself, OCR |
| Kanban with 4 fixed stages | Calendar, advanced metrics |
| "Inbox" queue (approvals and reviews) | Push notifications |
| Local REST API with a token | Remote access to the API |
| External research agent (script) | Agent marketplace or library |
| Basic history (who did what, when) | Advanced auditing and report export |

---

## Stakeholders & Users

- **Student (primary user):** a PhD or master's student using a Mac for daily work. One user per installation in version 1 (assumption).
- **Supervisor (later):** the natural human reviewer for a student's work. Not a separate user in version 1; the student is the only human member (assumption).
- **Agents:** external programs (for example Claude Code or a script) that authenticate with a token and act as `agent` members.
- **Responsible human:** every agent has a human owner, who answers for what it produces.

---

## Functional Requirements

### Tracks and items

- **FR-01** Create, rename, archive and list tracks.
- **FR-02** Create items in a track. Each item has a title, description, kind, stage, assignee, creator and, where applicable, a URL and a classification.
- **FR-03** Item kinds (version 1): `research request`, `source` and `note`.
- **FR-04** Fixed stages: **To read → Reading → In review → Done**.
- **FR-05** Move items between stages (drag on the board or through the API), checking the mover's permission.

### Notes in place

- **FR-22** Every item has a notes area that is edited **in place** on the card and in the detail view, with no separate dialog. Changes are saved as the student types.
- **FR-23** A note is written by a human or by an agent. Agent-written text is kept apart from the student's own notes, so an agent can never overwrite them (assumption: a separate `notes` field on the item).
- **FR-24** A new note can be created straight from a board column, in one step (quick add).
- **FR-25** Notes are plain text in version 1 (assumption); rich text and Markdown are open questions.

### Card panel

- **FR-48** Selecting a card and pressing ↩ (or double-clicking it, or ⌘I) opens a side panel with the card's properties (stage, due day, classification, link, assignee, creator), the student's own **notes**, any text the agent wrote (read-only), every field of the card's type, the cards linked to it, comments and history.
- **FR-49** Text is saved when the student leaves a field or presses return, not on every key; unsaved text is saved when the panel moves to another card.
- **FR-50** Every classification explains itself: a tooltip on its label, a line under it in the panel and in the approval inbox ("Essential: fills a critical gap that nothing you already have covers. Read it first.").
- **FR-51** Notes are the student's alone; agents never write to them. Editing a card's title, classification and link, like its fields, is for humans only, and a human can correct an agent's proposal before approving it.

### One person for now

- **FR-59** The app has one person: the user of the Mac, taken from the macOS account. There is no team screen and no member management for now. The core still models members and agents as equals, so agents can be added later through the local API without changing the rules.

### Where work is created

- **FR-57** Cards are not created on the board. New work (a source, a statement, a research request, a note, or a card of a type the student made) is started in the **Inbox** (button, or ⌘N, which opens the Inbox and its form), and PDFs are imported there too. The board is for tracking what already exists.
- **FR-58** A card created by the student is approved from the start and lands on the board; the Inbox confirms it. What agents and imports create waits in the Inbox for approval.

### PDF import

- **FR-52** The student can import a PDF into "Inbox" (button, ⇧⌘I, or dropping the file). Two layouts are read: a **source triage table** (#, period, source, link, classification, triage note) and a **who-said-what-and-when table** (date, who and where, position taken, where to find it, reference number, grouped by period, with a numbered reference list). Anything else is refused with a clear message.
- **FR-53** Every imported card waits for approval, exactly like an agent's proposal, and records the file it came from. Nothing an import creates is approved automatically.
- **FR-54** Triage rows become Source cards (classification, period, venue, year, triage note). The table only shows a shortened link, so the card gets the site and a caveat saying the full address still has to be found.
- **FR-55** Statement rows become Statement cards (actor and kind, date, position, locator, period, verification set to "to verify"). Dates that are not complete (year only, month only, "c.") are marked approximate. Each reference number becomes a Source card with the link from the reference list and is linked to the statement; further references are listed in the statement's details.
- **FR-56** Importing the same PDF again adds nothing: rows already in the track are skipped and counted in the result message.

### Item types and fields

- **FR-40** Every card has a **type**. Four types are built in (Note, Research request, Source, Statement) and people create more (for example Lecture, Experiment, Chapter). A type is a name, an icon and an ordered list of fields.
- **FR-41** Field kinds: text, long text, number, date, link, checkbox, single choice, multiple choice, and a relation to another card. Choices can be extended by the user (for example a new kind of actor). A field can be required.
- **FR-42** Title, stage, assignee, due day and approval are common to every card, so the board, the calendar and the approval inbox work for any type. Built-in rules stay with the built-in types (a Source needs a valid link, a Research request has a lease); custom types are plain.
- **FR-43** A **Source** has authors, venue, year, DOI, kind of source, how much was read (abstract only, full text available, read), a triage note, caveats and an optional "replaced by" source.
- **FR-44** A **Statement** records who said what: a source (relation), a date that may be approximate, who, kind of actor, the position taken, a short direct quote, where to find it, and a verification state. A missing verification state means "to verify". Agents propose statements; a human checks the quote against the original and approves.
- **FR-45** Each type has a switch "agents may propose this type" (off for types people create, until they turn it on). Agent-created cards are always pending.
- **FR-46** Agents read the schema through the API and the server validates every value against it.
- **FR-47** *(planned)* **Export** of documents like the triage table, the "who said what, and when" table by period, and the reference list, in a configurable citation style (assumption: Harvard by default; Markdown and PDF).

### Deadlines and calendar

- **FR-35** A card can have an optional **due day** (a date with no time of day). The board shows it as a badge (today, tomorrow, in N days, N days overdue, or the date). A card in Done is never shown as late.
- **FR-36** **Milestones** are dates that are not tied to a card (chapter due, meeting with the supervisor, thesis defense). Only humans create, move and remove them.
- **FR-37** A **Calendar** section shows a month grid and, for the selected day, its entries, plus lists of overdue items and of what is coming in the next two weeks. The board can be filtered by overdue and sorted by due date.
- **FR-38** An agent can propose a due day only when it creates a card; the card stays off the board and the calendar until a human approves it. Only humans change a due day afterwards.
- **FR-39** *(planned, needs the Xcode app project)* Mirror deadlines and milestones into a dedicated "Xueji" calendar in the Mac's Calendar (EventKit), one way, and show events from the Mac's other calendars read-only. Two-way sync is out of scope for the first version.

### Themes and keyboard-first organization

- **FR-32** Six themes shared with CogNote (Automatic, Warm, B&W, Night, Blue, Navy). The choice is made in Settings (⌘,), in the sidebar, or in the View menu, and cycled with ⌥⌘T. Automatic follows the Mac's light or dark mode.
- **FR-33** The board can be searched (⌘F), filtered (by classification or notes only) and sorted (oldest, newest, most relevant, title).
- **FR-34** The board, the calendar and "Inbox" are fully usable from the keyboard: arrows select, 1–4 move a card to a stage, ⌘[ and ⌘] step through stages, ↩ opens a link, A and D approve and discard. ⌘1–4 switch section, ⌘N adds a note, ⌘/ lists every shortcut.

### PDFs, markings and reading order *(proposed, pending answers to the open questions)*

- **FR-26** Upload a PDF onto a `source` item. The file is copied into the app's storage and never modified. Each upload is a **version**; a content hash is recorded so the same file is not stored twice.
- **FR-27** Mark up a PDF (highlights, underlines, text notes) in a reader built into the app (PDFKit). Markings belong to a marking set tied to one version of the file, are stored by the app, and are never written into the PDF; exporting an annotated copy is optional.
- **FR-28** Create a **new marking set** over the same PDF to mark a different topic, without duplicating the file. Sets can be shown, hidden and exported on their own (assumption: layers instead of file copies).
- **FR-29** Items can **depend on** other items ("read A before B"). Dependencies are created by the student or **proposed by an agent**, and agent proposals follow the same approval rule as FR-09.
- **FR-30** The app computes a **suggested reading order** for a track: every item comes after the items it depends on (topological order). It shows the suggested next item and explains why. A dependency cycle is reported, with the items involved, instead of producing an order (assumption).
- **FR-31** Items with no dependency between them are ordered by classification (Essential first), then by creation date (assumption).

### Members and roles

- **FR-06** Register members with a `kind` (`human` or `agent`) and a role (for example researcher, reviewer, owner).
- **FR-07** Every `agent` member has a human owner and its own token, which can be revoked.
- **FR-08** Agents have minimal permissions by default: create proposed items, comment, claim requests assigned to them. They do not approve their own work.

### Approval (the main rule)

- **FR-09** Every item created or changed by an agent is born with `approval = pending` and **does not appear on the board** until a human approves it.
- **FR-10** The **"Inbox"** queue lists pending approvals and requested reviews, with context (who proposed, link, classification, reasoning).
- **FR-11** Approve, discard (with an optional reason) or ask for changes. The reason is recorded.

### Research requests and agent execution

- **FR-12** A human creates a `research request` (topic, scope, what they already have) and assigns it to a research agent.
- **FR-13** The agent **claims** the request (`claim`) with a time-limited *lease*, so two agents do not take the same one. If the lease expires, the request becomes available again.
- **FR-14** The agent creates `source` items as proposals, each with a URL, a classification (`Essential`, `Complementary`, `Secondary`), a triage note and the date the link was checked.
- **FR-15** The agent closes the request with a summary and, optionally, reported cost and duration.

### Review

- **FR-16** Any member can ask another member to review an item (`ReviewRequest`), saying what to look at, and the result is recorded (approved, changes requested).
- **FR-17** A limit of **3 review rounds** per item. After that, the item is escalated to a human.

### Comments and history

- **FR-18** Comments on items, by any member.
- **FR-19** Event history per item (creation, move, approval, discard, review), with author and time.

### Interface

- **FR-20** Screens: **Board**, item detail, **Inbox**, and **Agents & team**.
- **FR-21** Every version 1 flow must be doable through the interface, without a terminal. That includes creating the research request, following progress and approving the results. Generating an agent's token is also done in the app.

---

## Non-Functional Requirements

| Area | Requirement |
|---|---|
| **Platform** | macOS 14 or later (assumption, the Mac is new). Swift, SwiftUI. |
| **Language** | English is the base language and the language of all code, identifiers and documentation. Simplified Chinese is supported through localization files with the same keys. The app follows the Mac's language. |
| **Design** | Native Mac look (sidebar, toolbar, SF Symbols, materials), using the same system as the web app and the sibling native apps: warm off-white background, terracotta accent, serif headings, shadows only on interaction, motion around 200 ms. Light and dark appearance. |
| **Latency** | Screens respond in under 200 ms with up to 5,000 items. The API responds in under 100 ms for simple operations (target assumption). |
| **Privacy** | Data stays on the local disk. The app sends no data out. Sending data to models is the external agent's responsibility. |
| **Security** | The API listens only on `127.0.0.1`, with a token per member. Tokens are kept in the Keychain. See the security section. |
| **Reliability** | Atomic writes in SQLite (WAL). Backup by JSON export. Leases expire. |
| **Observability** | Event log per item and per agent run. App logs contain no tokens and no sensitive content. |
| **Testability** | The core runs in tests (`swift test`) without UI. The API is testable with `curl` and automated tests. |
| **Future compatibility** | The core depends on no UI and no macOS-only APIs, to make iOS easier. |

---

## Architecture Overview

Three modules in one Swift package:

| Module | Responsibility | Depends on |
|---|---|---|
| `XuejiCore` | Models, transition and approval rules, SQLite persistence | Foundation and the SQLite library only |
| `XuejiAPI` *(planned)* | Local REST server, token authentication, input validation | `XuejiCore` |
| `XuejiApp` | SwiftUI interface and server startup | `XuejiCore`, `XuejiAPI` |

**Screen architecture:** each screen first declares a view protocol (what it reads) and a controller protocol (what it triggers), then a view model implements both and the model is injected. Views contain no logic. Code is organized by feature (`Features/<Name>/` with contracts, view model and view), plus `App/` (composition root), `Models/`, `Design/` and `Resources/` for localization.

### Data Sources & Connectors

- **Local SQLite** (file in `Application Support`), accessed through GRDB (assumption; SwiftData is the alternative, but gives less control when the local server and the UI share one database).
- **External agents** connect through the REST API. The app has no connectors to third-party services.
- **Research sources** (web, journals) are reached by the agent, not by the app.

### Components & Sequence

**Main flow: research and triage**

1. The student creates a `research request` and assigns it to the research agent (in the interface).
2. The agent queries `GET /requests?status=open` and calls `POST /requests/{id}/claim` (receiving the lease).
3. The agent searches, checks the links and classifies the sources, and sends each one with `POST /items` (born `approval = pending`).
4. The agent calls `POST /requests/{id}/complete` with the summary.
5. The app shows the proposals in the "Inbox" queue. The student approves (the item enters **To read**), discards, or asks for changes.
6. The student moves approved items through **Reading → In review → Done** and writes notes in place while reading.

---

## API / Interface Design

REST with JSON, versioned under `/v1`, with a generated OpenAPI specification so any agent can learn the API by itself. Authentication: `Authorization: Bearer <token>`.

| Method and path | Purpose |
|---|---|
| `GET /v1/tracks` | List tracks |
| `GET /v1/tracks/{id}/items` | List a track's items (filters by stage, approval, assignee) |
| `POST /v1/items` | Create an item (agent: always `pending`) |
| `PATCH /v1/items/{id}` | Update fields allowed for the caller's role |
| `POST /v1/items/{id}/transition` | Move to another stage, checking permission |
| `POST /v1/items/{id}/comments` | Comment |
| `POST /v1/items/{id}/reviews` | Ask for a review |
| `GET /v1/requests?status=open` | Requests available to the agent |
| `POST /v1/requests/{id}/claim` | Claim with a lease |
| `POST /v1/requests/{id}/complete` | Close with a summary, optional cost and duration |
| `POST /v1/members/{id}/tokens` | Generate a token (only from the app, by the human owner) |

**API rules**

- Every input is validated (types, sizes, formats) and rejected by default if invalid.
- A `source` item **without a valid URL is rejected**.
- Errors return correct status codes and generic messages, with no internal details.
- Agents cannot approve items or change `approval`, and cannot overwrite the student's notes.

**Data model (summary)**

| Entity | Main fields |
|---|---|
| `Member` | id, name, `kind` (human/agent), role, owner (for agents), active |
| `Track` | id, name, description, archived |
| `Item` | id, track, kind, title, description, notes, stage, `approval` (pending/approved/rejected), assignee, creator, URL, classification, link_verified_at, needs_human |
| `ReviewRequest` | id, item, requester, reviewer, instructions, result, round |
| `Comment` | id, item, author, text, date |
| `Event` | id, item, actor, kind, date, details |
| `AgentRun` | id, agent, request, start, end, summary, reported cost and duration |
| `Lease` | id, request, agent, expires_at |

---

## Research Agent Workflow

*(replaces the "Retrieval & Generation Workflow" section, which is specific to RAG systems. Here the workflow is the one followed by the agent that uses the API.)*

The research agent is an external program (assumption: a script that uses Claude, with the logic of the `source-triage` skill):

1. **Understand the request:** topic, scope and what the student already has (to avoid duplicates).
2. **Search** quality sources by category (theory, academic papers, official sources, journalism, technical reports).
3. **Verify** that each link is live and relevant before sending it.
4. **Classify** as `Essential`, `Complementary` or `Secondary`, relative to what the student already has, and write a triage note saying which gap the source fills.
5. **Send** each source as a proposal and close the request with a summary.

**Rules:** never invent sources or links, drop duplicates of what the student already has, and respect the per-request item limit (assumption: 20).

---

## Evaluation & Metrics

Derived from the success criteria the user chose.

| Criterion | Metric | Initial target (assumption, adjust after 2 weeks) |
|---|---|---|
| **Useful triage** | % of proposed items the student approves | ≥ 50% |
| **Useful triage** | % of links that were live at approval time | ≥ 95% |
| **Less search time** | Weekly hours spent looking for material, noted by the student, before and after | A noticeable reduction, defined by the student |
| **No terminal needed** | Checklist of the FR-21 flows done only through the interface | 100% of flows |

**How it is measured:** the app records approvals and discards (already part of the history). Search time is self-reported, because it cannot be measured automatically.

**Cost:** since agents run outside the app, it only records cost and duration when the agent reports them.

---

## Deployment & Operations

- **Distribution:** local build through Xcode, personal use, no App Store (assumption). This avoids sandbox requirements for the local server.
- **App bundle:** the package currently runs as a SwiftPM executable, which has no `.app` bundle and so no Dock icon. An Xcode app project is needed for the icon, bundle identifier and entitlements. Icon assets are in `Icon/`.
- **Data:** SQLite file in `Application Support`. Backup by JSON export, manual at first.
- **API server:** starts with the app and stops when the app closes.
- **Agents:** run by the student outside the app (terminal, Claude Code, scheduled script). They need the app to be open.
- **Schema updates:** versioned migrations in `XuejiCore`.

---

## Security & Access Control

- **Network:** the server only accepts connections on `127.0.0.1`. No access from the local network or the internet.
- **Authentication:** one token per agent member, generated and revoked by the app. Tokens are kept in the Keychain and shown only once.
- **Authorization (least privilege):**
  - an agent can create proposed items, comment and claim requests assigned to it;
  - an agent does **not** approve items, does not change `approval`, does not move items outside its scope, and does not see tracks not assigned to it;
  - only humans approve and discard.
- **Input:** all external input is validated and size-limited.
- **Errors:** generic responses, with no stack traces or SQL details.
- **Secrets:** model keys stay with the agent, not in the app. No secrets in code or logs.
- **Logs:** never record tokens or the full text of items or notes.
- **Dependencies:** check Swift dependencies for known vulnerabilities before each milestone.

---

## Risks & Limitations

| Risk | Impact | Mitigation |
|---|---|---|
| **Choosing the full app as the first milestone.** It went against the recommendation to start with the core, the API and a command line. SwiftUI changes can only be verified by building on the user's Mac. | More error-and-fix cycles, and a risk of investing in the interface before the model is proven. | Separate milestones (M0 to M2): the core and the API are tested without the interface. If progress stalls, stop at M1 and use only the API. |
| **A reliable runner is the hard part.** An agent that does not repeat work, does not overspend and asks for help at the right moment. | The system looks good and goes unused. | In version 1 the runner is external and simple. The lease prevents duplicate work. An embedded runner comes later. |
| **Invented sources or broken links.** | Loss of trust in the triage. | The API rejects a source without a URL, the agent verifies links, and the live-link metric is tracked. |
| **Mandatory approval can become a bottleneck.** | The queue grows and the student stops looking. | Per-request item limit, sorting by classification, and a review of the rule after 2 weeks of use. |
| **Too generic a system.** | It becomes vague and unused. | One concrete flow (research and triage) for students. Generalization comes from the second use case on. |
| **Agent writes over the student's notes.** | Loss of the student's own thinking. | Agent text is kept in separate fields and the API forbids writing to the student's notes (FR-23). |
| **An agent reviewing an agent becomes a rubber stamp.** | Review with no value. | Out of version 1. When it arrives, require the review to state what was checked and use a different model or prompt. |
| **The local API does not reach the iPhone.** | The future iOS version needs another solution. | The core is independent of the UI. Sync through CloudKit stays as an evolution. |
| **The app must be open for agents to work.** | Agents fail outside usage hours. | Document it. Handle connection errors in the agent with retries. |
| **Chinese translations not reviewed by a native speaker.** | Awkward or wrong wording. | Review the Chinese strings with a native speaker before any release. |

**Known limitations:** a single user, no sync, no automatic agent execution, and time-saved metrics depend on the student's own report.

---

## Open Questions

1. **Per-request item limit** (assumed 20) and review round limit (assumed 3): confirm after the first tests.
2. **Persistence library:** GRDB (assumed) or SwiftData?
3. **How the research agent will run day to day:** manually from the terminal, or scheduled? This defines what the app should expose to make it easy.
4. **Import:** do you want to import the source list the `source-triage` skill already produces (`.docx`) or start from scratch?
5. **Minimum macOS version:** confirm the exact version of the Mac.
6. **When agent-to-agent review enters** and with which safeguards against rubber-stamping.
7. **Notes format:** plain text (assumed) or Markdown, and whether notes need to link to sources.
8. **Supervisor role:** does the supervisor ever get access (review or comment), and how, given that version 1 has a single user?
9. **Versions** *(answered)*: a new version is a **revision** of the same document, made by a supervisor or by the student. Open: how markings carry over to a revision (proposed: re-anchor by text, flag the ones that no longer match for review).
10. **Copies for other topics:** is a separate marking set over one PDF (proposed) enough, or do you need independent copies of the file?
11. **Dependencies:** at first, only manual links, or also agent suggestions (for example from a paper's references or a syllabus)?

---

## Project Plan & Milestones

Independent milestones, so work can stop at any of them without losing what already works.

| Milestone | Deliverable | Acceptance criteria | Status |
|---|---|---|---|
| **M0 — Core** | `XuejiCore` with models, transition rules, approval, leases and SQLite persistence | Automated tests cover: an agent cannot approve, a pending item does not appear on the board, a lease expires, the review round limit | Rules engine and tests written; persistence not started |
| **M1 — API and agent** | `XuejiAPI` with the endpoints, generated OpenAPI, token per member, and a sample research agent | From the terminal, a request is claimed, sources arrive as `pending` and the API rejects a source without a URL | Not started |
| **M2 — Mac app** | Board, item detail with notes in place, "Inbox" and "Agents & team" screens | Every FR-21 flow works through the interface, without a terminal | App shell on sample data; notes in place and persistence pending |
| **M3 — Real use** | Two weeks of use, with the metrics collected | Review of the approval, live-link and "no terminal" targets, with a decision on what changes | Not started |
| **M4 — Evolution (conditional)** | Embedded runner, agent-to-agent review, iOS with CloudKit | Only if M3 shows real use and need | Not started |

**No dates set:** order matters more than dates, and estimates depend on how much time the student has and the pace of interface adjustments in Xcode.

---

## References

- Skill `source-triage`: search, link verification and classification logic (Essential, Complementary, Secondary) used by the research agent.
- Skill `contracted-mvvm` (Socket Pattern): inspiration for the view and controller protocols per screen, adapted to Swift.
- Skills `coding-guidelines` and `security-guidelines`: simplicity first, surgical changes, input validation, least privilege.
- Sibling apps CogNote and Mesa: folder layout, localization helpers (`L()` and `Lf()`) and design tokens.
- The "Forja" workspace (screenshots provided): visual reference for the "Overview" and "Needs you" screens.

---

## Notes

- **Omitted section:** "Retrieval & Generation Workflow" is replaced by "Research Agent Workflow", because the system is not a RAG.
- **Assumptions** are marked in the text as "(assumption)". These decisions came directly from the interview and later messages:
  - first flow: research and triage;
  - agents run outside, through the API;
  - first milestone: the full SwiftUI app (against the recommendation to start with the core, the API and a command line);
  - success: useful triage, less search time and everything without a terminal;
  - human approval always required;
  - fixed kanban stages;
  - audience: PhD and master's students, for daily work, with notes written in place;
  - everything in English, with Simplified Chinese support;
  - name: Xueji (学记).

### Decisions: deadlines and calendar

- A deadline is a day, not a date and time (answered). Recurring events are out of the first version (assumption).
- EventKit needs `NSCalendarsFullAccessUsageDescription` in an `Info.plist` and the calendar entitlement when sandboxed, so it depends on the Xcode app project (the SwiftPM executable has neither).

### Decisions: item types, statements and export

- Card types are predefined and people can create their own (answered). Built-in typed properties that carry rules (link, classification, link-verified time) stay on the card; everything else is a field of the type.
- Statements are proposed by agents and also written by the student (answered); the per-type switch in FR-45 covers both.
- Export of the triage and "who said what" documents is wanted (answered); format and citation style are assumptions in FR-47.
- Not in the first version: deleting or renaming fields and types, changing a field's kind, per-type workflows, formulas.

- **FR-60** Any PDF can be added to the library as a source card (the file is copied into the app's folder). Only a person may attach a local file; agents still send web links.
- **FR-61** A card on the board can be discarded (context menu or ⌫); the card is kept as rejected and the last discard can be undone.
- **FR-62** The Inbox can be searched, filtered (type, priority, imported file) and sorted (document order, suggested reading order, priority); all cards shown can be approved or discarded at once after a confirmation.
- **FR-63** The "Suggested Reading Order" of a source triage PDF is imported as the source's "Reading order" field, with the PDF's reason added to the card's details.
- **FR-64** The sidebar has a Writing screen: free-text drafts with a title, word count and a button that copies the text to the clipboard (to paste into Word). Drafts are not cards.
- **FR-65** The four stages are also sidebar items (with counts) and Go-menu items; each opens the board narrowed to that stage.
- **FR-66** A Library screen lists every approved source (web links and PDFs kept on this Mac), searchable and filterable; a PDF opens in the default app. Adding a PDF takes the user to the Library.
- **FR-67** A draft can be exported as Word (.docx), rich text (.rtf) or plain text (.txt).
- **FR-68** A draft records what it is based on: a free note and links to cards (sources, statements, tasks). A linked card opens on the board; "Copy text and sources" and every export add a "Based on" block at the end.
- **FR-69** Changes to cards (approve, discard, move, due date, rename, import, new card) can be undone and redone, in order, with ⌘Z / ⇧⌘Z on the board and the Inbox, with buttons in their toolbars and items in the Board menu (up to 100 steps, this session only). Drafts are not part of it.
- **FR-70** A PDF in the Library opens in a reader inside the app: highlight (four colours) and underline selected text, add a note to a mark, search, and see all marks in a side list that jumps to the page. Marks are written into the PDF file itself.
- **FR-71** Each PDF can have several versions, one per topic or use: its own copy of the file with its own marks, created from the current version with or without its highlights. The original is a version too. Version names and the list are kept in memory only for now; the files stay on disk.
- **FR-72** A mark's quote can be copied with its page, or added to a draft, which also links the source as the draft's basis.
- **FR-73** In a draft, the "Based on" field searches the cards while you type (sources, PDFs, statements, tasks, notes): one click links the card; ↩ adds what you typed as a note. Notes and links show as removable chips. A linked PDF opens in the reader, any other card on the board.
- **FR-74** Import is explicit: "Source triage table…" and "Who-said-what-and-when table…" (each with a short description of the format), and "Add PDF to library…" for any other PDF. A PDF that is the other kind of table is refused with a message that names the right entry; a PDF dropped on the Inbox is detected automatically.
- **FR-75** "Detect automatically…" imports a PDF without choosing the kind of table: Xueji recognises it and says which one it was. It is the first import option, and ⇧⌘I.
- **FR-76** When "Detect automatically…" meets a PDF that is neither table, it goes to the Library as a source (with a notice there) instead of failing. A table chosen explicitly that does not fit still shows an error, without the raw diagnosis (that is in Help → Save PDF Reading Report…).
- **FR-77** The student has a palette of highlight colours: four to start with, plus any colour they choose with the colour picker, each with a name (for example "Definition"). The palette is kept between sessions; marks store their colour in the PDF.
- **FR-78** Everything the student makes (cards, types, milestones, drafts, reading versions) is saved to one file in Application Support and loaded at start, so builds and restarts keep it. A copy of the previous run's file is kept; a file that cannot be read is moved aside, never overwritten. Highlight colours are kept in the user defaults.
- **FR-79** A draft can be based on any number of cards, PDFs and free notes. They are listed in a Sources panel on the right of the writing area (which can be hidden, and remembers that), each source as a small card with its title, authors and year, a Read / Show button and a remove button; free notes are listed below them. The text area keeps its size however many sources there are.
- **FR-80** One search field at the top of the Sources panel looks for a phrase, ignoring case and accents, in the text of the linked PDFs (with page), the cards' title, description, notes and text fields, the student's highlight notes in the reader, and the free notes. Results appear inside the source they came from, the sources with results first and the others dimmed. Opening a result shows the PDF at that page with the phrase marked; "Quote" appends the passage to the draft with its source and page.
- **FR-81** Compile (sidebar, ⌘6) puts the drafts in order (drag to reorder), chooses which are included and at what level (chapter, section, subsection), and builds one document with a preview, a word count, copy and export to Word (real heading styles, optional table of contents), RTF and plain text.
- **FR-82** Sources are cited in a draft with a mark like `[@Silva2020, 12]` (the Cite button in the sources panel copies it; Quote inserts it with the page). On compile each mark becomes an in-text citation and the bibliography is built from what was cited (optionally also what was only linked), without duplicates (same DOI, address, or title, year and first author), with a, b letters when authors and year coincide. Unknown marks and sources with missing authors, year or title are listed as warnings.
- **FR-83** The student chooses the citation style per document. The two basic ones are Harvard (author–date) and GB/T 7714 (the Chinese national standard, numbered by first citation, with document-type letters such as [J], [M], [R]); APA 7, ABNT and numbered IEEE are also offered. The app starts with GB/T 7714 when it runs in Chinese and Harvard otherwise.
- **FR-84** The New card form, when the type is Source, also asks how important the source is (essential, complementary, secondary, or none), its authors, year and kind (journal article, book…), with journal/publisher and DOI under "More details". They are saved with the card in one undoable step.
- **FR-85** The workspace holds several projects (a dissertation, an article…). A switcher at the top of the sidebar changes the open project, creates a new one, renames or archives the current one (the last project in use cannot be archived), and restores archived ones. Each project has its own board, Inbox, calendar, library, drafts and compilation (with its own citation style). Archiving hides a project without deleting anything. Switching starts a fresh undo history.
- **FR-86** A card can be copied to another project from its context menu (board and Library): the copy has the same content, classification, notes and PDF file (not duplicated), and no links to cards of the original project. Everything saved before projects existed belongs to the first project.
- **FR-87** The app language can be chosen inside the app (System default, English, 简体中文) from Settings or the globe menu in the sidebar. The choice applies immediately to all text, menus, window titles and date formats, and is remembered.
- **FR-88** Triage (sidebar, ⌘7) builds a quote-triage report per project: the student gives a search term and the app counts it, whole word and ignoring case, in the PDF of every approved source (words, hits, hits per 1,000 words, and optionally a phrase such as “national security”); the student adds quotes classified as Essential, Supporting or Counter-evidence with speaker, locator, source and why it matters; a timeline whose rows can be marked as missing documents; and numbered findings. The report is shown on screen and exported as a landscape Word document with tables, or as plain text. Counts are never typed by hand; classification and comments are always written by the student.
- **FR-89** When a PDF is added to the Library, the highlights and underlines it already has are brought in as Xueji marks, one per line, with their notes and their exact colours (new colours join the palette with a name such as Red or Green). This covers highlights made by other apps and highlights flattened into the page (saved or printed with the highlights drawn in). Only the library copy is changed. Because PDFKit paints a flattened highlight opaque over the text, the painted copy is removed from the library copy (an appended update replaces the page's flattened-annotation form with an empty one, only when all its parts were imported as marks and the result opens with the same pages); if that is not possible the file keeps the painted highlights.
- **FR-90** A quote triage report in PDF (the layout Triage exports, or any report with the same three tables: counts per document, classified quotes, timeline, plus a recap) can be imported from the Inbox (Add menu, Import menu, or detected automatically). It fills the Triage of the current project: search term, counted phrase, notes, documents (matched to Library sources by title, or kept with the numbers of the report), quotes with class, speaker, locator and why it matters, timeline rows (a dash in the count column marks a missing document) and findings. Nothing already written is overwritten and repeated imports add nothing new. English and Chinese headings are read.
- **FR-91** A project can hold several quote triages (for different terms). A menu at the top of Triage switches between them, creates a new one and deletes the one shown. Importing a report fills the shown triage when it is empty, joins the triage with the same search term, or starts a new triage when the term is different.
- **FR-92** **Progress** (sidebar, ⌘8) shows productivity numbers for the open project, read from the history the app already keeps, with no new data to enter: cards finished and sources read per week, cards started, where the cards are by stage, deadlines (overdue, due in 7 days, finished on time or late) and the words in the drafts. Decisions on Inbox proposals are counted by who proposed them (the student or an agent), with the date: a column per week and a list of the latest decisions. Dropping a card from the board or bringing it back is not a decision. Numbers that need history the app does not keep (words per day, time in each stage) are not shown.
- **FR-93** In Progress the student chooses the period the numbers are about (this or last week, this or last month, last 30 or 90 days, all time, or two dates), and can turn on **Compare** to pick a second period (by default the stretch right before, as long as the first, or any other). Each number then shows the change against the other period (green when it is better, red when it is worse; rejections have no good or bad direction). The decisions list follows the chosen period. The stage counts and current deadlines always describe the present.
- **FR-94** Reference lists are read in more than one style. Besides the Harvard entries with the year in brackets, an entry can be a Chinese footnote or national-standard style ("作者：《标题》，载《期刊》，2020 年第 7 期" for an article, "作者：《书名》，出版社，2015 年版" for a book), an English footnote with a quoted title ("Author. “Title.” Journal, 2019, pp. 1-45", also for a chapter), an English book without quotes ("Author. Title. Publisher, 1996."), a Chicago note with single quotes ("Author, ‘Title’, in Book, ed. …"), APA ("Buzan, B., Wæver, O., & De Wilde, J. (1998). Title. Publisher.") or Springer ("Buzan B, Wæver O (2003) Title (No. 91). Publisher, City.") or a web page ("Organisation, Title, 2024-12-23, link, 访问时间：…"). Entries may be numbered "[1]", "1." or "1.Text", and a line without a number continues the entry above. Authors, year, title, venue (journal, book or publisher) and link are filled in; the access date is left out.
- **FR-95** The official reference model (Chinese footnote style for journal articles, books and web reports, English quoted style for the rest) is a citation style for compiling, and a Reference converter screen (⌘9) turns a pasted list in any supported style into another one, flagging the fields it could not read.
- **FR-96** A Reference finder (⌘0) looks a work up in Crossref and Open Library and prints it in a chosen style; it can add the result to the library as a source card.
- **FR-97** A Link checker (⌥⌘1) takes a pasted reference list; the references that have a link or DOI become tasks, each marked done automatically when its link opens. Sites that refuse automatic visits are flagged for a manual check, and the student can confirm any task by hand.
- **FR-98** The sidebar is grouped (Plan: board, calendar, inbox; Read & write: library, writing, compile, references; Analyse: triage, progress). The three reference tools (finder, converter, link checker) share one References screen with tabs, opened by ⌘0, ⌘9 and ⌥⌘1. The stages section starts folded.
- **FR-99** A "Prompts for AI" screen (sidebar group Help) offers copyable prompts that make an assistant such as Claude or ChatGPT write a document in the exact layout the importers read: source triage, who said what and when (with references and caveats), quote triage (English or Chinese), and a reference list in the official model. Each prompt says which Inbox or References action reads the result.
- **FR-100** Cleanup. ⌘1–⌘9 follow the sidebar order (board, calendar, inbox, library, writing, compile, references, triage, progress); ⌥⌘1–3 open the reference tabs and ⌥⌘P the prompts. The board toolbar keeps the panel button, search and one View menu (filter and sort); undo and redo stay on ⌘Z, ⇧⌘Z and the Board menu. The reader's highlights panel starts closed (⌥⌘L toggles it, the choice is remembered). The Progress blocks fold, with deadlines, decisions and writing folded at first. Spacing and title sizes come from shared tokens (`Space`, `Font.sectionTitle`, `Font.screenTitle`).
- **FR-101** Drafts accept light Markdown: `**bold**`, `*italic*`, list lines ("- " or "1. ") and formulas in LaTeX (`$x^2$` in a line, `$$ … $$` alone in a paragraph). The Word export turns them into bold and italic runs, indented lists and native, editable Word equations (fractions, powers, indices, roots, sums, integrals, Greek letters, operators, `\text`); the Compile preview and the RTF export show bold and italic and keep a formula as its LaTeX. The Stages group in the sidebar is always open.
- **FR-102** In the triage counts, each included PDF can list every place where the term appears: page number and the words around it, with the term in bold, using the same matching rule as the count. A click opens the PDF on that page with the term marked. The Report tab shows a start screen, and copy and export are off, until there is a term, a quote or an event.
- **FR-103** The first triage tab is called Documents and works in order: type the term, choose a PDF in the list, read where the term appears in it. Each place has a page and its context; a click opens the PDF there and a quote button starts a quote (text, source and page filled in) in the usual form. The notes for the report sit in a folded block. The first PDF is chosen when the tab opens.
- **FR-104** The screen called Triage in FR-88 to FR-90 and FR-102/103 is named **Evidence** in the app (English) and 文本证据 (Chinese); each one a project may have is an "evidence set", and the PDF it imports is an "evidence report". The source triage (the table that ranks sources, imported into the Library) keeps its name. In the code the feature is `Evidence…` (`EvidenceSet`, `EvidenceView`, `EvidenceReportParser`, …); the only names left from before are `triages` and `triageSets` in the saved file, so projects saved earlier still open.
- **FR-105** The places where the term appears are found while the PDF is read, a few pages at a time: each place shows up as soon as it is found, with "Reading page X of Y…" until the last page, and the reading starts at once, in step with the count. At most 400 places are listed per document.
- **FR-106** The modifier is called "Word before the term" and has an info popover that says what it does; below the fields the phrase being counted is shown ("Also counting the phrase …"). In the list of places, the ones where the word stands right before the term carry a "with …" mark, and the header counts them. The list reloads whenever the term changes, even when the count finishes before the screen redraws.
- **FR-107** Closing the reader goes back to the screen it was opened from (Evidence, Board, Writing, Library…), not always to the Library. The PDF chosen on the Evidence Documents tab is remembered between visits.
- **FR-108** Choosing another PDF on the Documents tab always starts its own reading, also when it has no place for the term (it then says so). The places are kept while the term and the project do not change, so leaving and coming back costs nothing. A quote started from a place carries the passage without the pieces of words the cut left at the ends, with about 120 characters of context on each side. The source of a quote or an event is chosen in a small list that shows the title of the chosen source.
- **FR-109** A quote started from a place of a PDF shows its source as read-only text, since the source was already chosen. Each place has a button to mark it as checked: checked places are hidden from the list (dimmed when shown again with "Show checked (n)") so what is left is what still has to be read. The checked places are saved with the report, by source, and survive a new reading of the PDF.
- **FR-110** Quotes only come from the documents under analysis: the Quotes tab has no "Add quote" button and says to save them from the Documents tab. The source and the page of such a quote are filled in by the app and shown as text, not as fields to choose; only the speaker, the class and the reason are written by the student. A quote imported from a report without a known document keeps the source chooser.
- **FR-111** In the timeline form, choosing the source fills the date of the line with the date of that document when the date is still empty.
- **FR-112** The timeline is a chart: time runs left to right and each document has its own row with a point for every event linked to it (events with no document share the last row; a missing document is a diamond). Pointing at the chart picks the nearest event and shows it under the chart. Below the chart the events are listed in date order, which replaces moving them by hand. The date of an event is a year with an optional month and day, chosen in fields that only accept dates that exist (the year from 1900 to 2100); the report writes it as "2019", "Feb 2019" or "4 Nov 2019". Dates of events imported as text are read when possible; those that cannot be read are listed, not drawn, and are fixed by editing the event.
- **FR-113** An event of the timeline can be linked to one of the quotes of the report, chosen in a list. The document of the quote becomes the source of the event (and its row on the chart), and the quote is shown in the event list and under the chart when the event is picked. Deleting a quote only unlinks its events. A missing document cannot have a quote.
- **FR-114** The axis of the timeline chart always runs in whole years. An event can last for a period (a start and an end, each a year, a month or a day; the end cannot be before the start) and is then drawn as a bar in the row of its document. The student can also add a named period ("the 2019–2023 expansion") with its start, its end and any number of the quotes of the report; periods are drawn as bars on top of the chart, listed in their own section, and written before the events in the timeline table of the report. Pointing at the chart picks the nearest item of the row under the pointer. Deleting a quote only takes it off the periods and events that used it.
- **FR-115** The same passage of a document is never saved as two quotes. On the Documents tab a place that is already a quote shows a filled quote button that opens the saved quote; the quote form refuses a passage another quote of the same document already holds (equal words, or one inside the other when they are long enough) and says so.
- **FR-116** The timeline always has one period, the master, which covers the whole timeline, can be renamed and cannot be deleted. Every event belongs to a period (the master unless the student chooses another) and every period sits inside another one, so the student can break the master into groups and the groups into smaller groups. A period or an event must fit inside the dates of the period it belongs to. Deleting a period moves the periods and events inside it up to the period that held it. The timeline is listed as an outline (each period followed by its events), drawn on the chart with the master as a faint bar over everything, and written in that order in the timeline table of the report.
- **FR-117** The timeline can be generated from the documents: the "Generate from documents" button adds one event for every included document that has a readable date and is not on the timeline yet. The event has the date and the title of the document, is linked to it, takes the quote of the document when it has exactly one, and goes into the innermost period that holds its date (the master when none does). Running it again adds only what is new, and it says how many events it created.
- **FR-118** An evidence report written as a PDF (the layout the "Evidence report" prompt asks an assistant for) is imported from the Evidence screen, not from the Inbox, because it creates no cards to approve or discard. It is read only when asked for there (the Inbox no longer takes it for a table). Its timeline dates become real dates: a year, a month, a day or a period such as "2019–2023", "Feb–Jun 2019" or "4–5 Nov 2019", so its events appear on the chart (as a bar when they last for a period). The prompt now asks for dates written only in those forms.
- **FR-119** An evidence report can bring in the periods too. Section 3 of the report may hold a periods table (name, from, until, inside, quotes) before the events table, and the events table has two more columns: the period of the event and the number of the quote that shows it. Importing creates the periods with their nesting (a period without "inside" sits in the whole timeline), links the quotes of each period, puts each event in its period and links it to its quote (the document of the quote becomes the source of the event), and says how many periods it added. Reports without these columns import as before. The "Evidence report" prompt asks an assistant for exactly this layout.
- **FR-120** Once a term is typed, the Documents tab lists only the documents that have something to look for: the term is in them (or their PDF is still being read). Documents without the term, and those left out of the counts, are behind "Show n documents without the term", so they can still be included again. The document shown on the right is always one of those listed, and when none has the term the screen says so.
- **FR-121** Importing a source triage skips only the sources that are already there and not discarded: a source the student discarded comes back as a new card to approve. When some of the ones that were already there are still waiting for approval, the message says how many, and that only approved sources appear on the Evidence screen.
- **FR-122** The Inbox has one import button, "Import a PDF…", instead of one per kind. Xueji recognises the PDF itself: a source triage or a table of statements puts cards in the Inbox, an evidence report goes into the Evidence screen (which is then opened), and any other PDF is added to the Library to read. Dropping a PDF on the Inbox does the same. The Evidence screen keeps its own "Import a report…" button for when the student already knows what the file is.

### FR-124 Search the documents

The Evidence screen has a **Search** tab, between Documents and Quotes.

- A list of the project's approved sources that have a PDF, each with a checkbox ("Search in"), plus All and None. A new document is on until switched off. Changing the selection after a search runs it again.
- A search field. Words are searched as whole words ignoring case, the same rule as the term count; text between quotes is an exact phrase. With several terms, only pages that contain every one of them are listed.
- The results are grouped by document and show the page, the words around the match with the match in bold, and a count per document. At most 300 places are listed, and a note says when the list was cut.
- A result opens the PDF in the reader on that page with the matched words marked. A button saves the passage as a quote with the page already filled in; a passage that is already a quote opens that quote instead (no duplicate quotes). Every result also has a check button, like the occurrences list of the Documents tab, and the marks are shared with it: a checked place is dimmed, and a link at the top hides the checked places or shows them again.
- The pages are read on demand and kept in memory while the app runs; nothing is written to disk and nothing leaves the Mac. There is no meaning-based search and no generated answer: the tab only finds and shows text.
- The search is not saved in the project; the text field and the selection start again when the project changes.

### FR-125 Documents tab lists only real documents

The Documents tab lists only the sources that have a PDF on this Mac, plus the documents of an imported report (FR-118). A source without a PDF (a card with only a link, a translation note) is not listed, because there is nothing to read, count, search or quote in it. Such sources still exist in the Library and can still be the source of an event on the timeline.

### FR-126 Choose the quote in the document

A quote is chosen where it is written, in the PDF:

- In the reader, **Save as quote** (⇧⌘E, enabled when text is selected) sends the selected words to the evidence report as a quote of that document, with its page. Words split by a hyphen at the end of a line are joined and line breaks become spaces.
- When a quote of the same document already holds these words (or part of them), that quote takes the selected words and the new page instead of a second quote being made, so a quote that was cut in the middle of a word is fixed by selecting the passage again. The same selection twice says it is already a quote. A message in the reader says which happened.
- On the Quotes tab each quote has a **Show in the document** button (also in its menu) that opens the PDF on the page of the quote, ready for the student to select the passage.
- The badge of the class is no longer cut at the right edge of the list.

### FR-127 Warn before a repeated card

Adding a card that is already in the project asks first instead of silently making a second one.

- A card counts as already there when a card of the same type in the project, not discarded, has the same title (ignoring case, accents and extra spaces) or, for a web link, the same address.
- **New card:** the form stays open with what was typed and asks "“Title” is already in this project. Add another one anyway?", with "Add anyway" and "Don't add".
- **Add a PDF** (Library, Inbox, drag and drop): a PDF counts as already there when its title or its file name matches a card. Nothing is copied until the student says yes.
- **References ▸ Find ▸ Add to Library** asks the same way.
- Imports of tables still skip repeated rows by themselves and report how many were skipped; they do not ask.

### FR-128 Name

The app is called **Xueji** (学记 in Chinese: "record of learning", also the title of a classical Chinese text on education). "Research notebook" is only a description, for example the subtitle in a store listing, because an app with that name already exists. The name is the same in the window title, the Dock, the menu bar, the bundle, the code and the data folder.
