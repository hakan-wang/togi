# Goals, check-ins & the insight journal — Implementation Plan (Foundation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the on-device agent the data + tools to create goals, write a dated behavioural/goal **journal** (Notice), schedule check-ins as events, and fire them proactively through the existing 5-minute judge tick.

**Architecture:** Migration **v6 on top of v5** (`feat/tailored-data-model`). Adds two persistent shapes — extended `goals` and a new `journal` table (episodic memory: insights + goal progress + check-in outcomes, keyed by `kind`) — plus a `goal_id` on `user_events` so a `cat='checkin'` event is a scheduled check-in. Everything is agent-curated data in the established grain: agent reads via read-only SQL tools, writes via `callAction → SidecarActionHandlers → GRDB`. Proactivity rides `JudgeCoordinator.tick()`, which already feeds active events to the agent. The semantic `behaviour_profile` doc (Remember) from v5 is unchanged; the agent distills durable journal entries into it.

**Tech Stack:** Swift + GRDB (SQLite), Node/TypeScript sidecar (LangChain tools + better-sqlite3), Vitest, XCTest.

**Scope:** This plan delivers the data + agent + proactivity foundation only. The dashboard UI that surfaces journal insight cards and the per-goal journey is a **separate follow-up plan** (the stores and tools defined here are its inputs).

**Run locations:**
- Swift: from `apps/macos/Bogi` → `swift test --filter <Name>`
- Sidecar: from `apps/macos/Bogi/sidecar` → `npx vitest run <file>` (or `npm test` for all)

---

## File Structure

**Create:**
- `apps/macos/Bogi/Sources/BogiApp/Features/Journal/JournalEntry.swift` — GRDB record for `journal`.
- `apps/macos/Bogi/Sources/BogiApp/Features/Journal/JournalRepository.swift` — insert / query / setStatus.
- `apps/macos/Bogi/Tests/BogiAppTests/GoalsServiceTests.swift`
- `apps/macos/Bogi/Tests/BogiAppTests/JournalRepositoryTests.swift`
- `apps/macos/Bogi/Tests/BogiAppTests/SidecarGoalsHandlerTests.swift`
- `apps/macos/Bogi/Tests/BogiAppTests/JudgeProactivityTests.swift`

**Modify:**
- `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift` — `v6_goals_and_journal`.
- `apps/macos/Bogi/Tests/BogiAppTests/SchemaMigrationTests.swift` — v6 assertions.
- `apps/macos/Bogi/Sources/BogiApp/Features/DataBank/Goals.swift` — extend record + service.
- `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEvent.swift` — add `goalId`.
- `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEventRepository.swift` — `events(forGoal:)`, `delete(id:)`.
- `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift` — new cases + closures.
- `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift` — `activeGoals` + `dueCheckIns`.
- `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift` — fetch + fire-on-due + mark handled.
- `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift` — wire closures + coordinator + appState.
- `apps/macos/Bogi/sidecar/src/tools/actionTools.ts` — `manage_goal`, `log_journal`, `set_journal_status`, `add_event` goal_id.
- `apps/macos/Bogi/sidecar/test/actionTools.test.ts` — forwarding tests.
- `apps/macos/Bogi/sidecar/src/tools/readTools.ts` — `list_goals` (status/why/cat), `list_journal`, `summarize_range.recentInsights`.
- `apps/macos/Bogi/sidecar/test/readTools.test.ts` — journal/goals fixtures + tests.
- `apps/macos/Bogi/sidecar/src/persona.ts` — goals / journal / check-in guidance.

---

## Task 1: Migration v6 — extend goals, create journal, add user_events.goal_id

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift` (append a migration after `v5_tailored_data_model`, before `try migrator.migrate(dbQueue)` at line 215)
- Test: `apps/macos/Bogi/Tests/BogiAppTests/SchemaMigrationTests.swift`

- [ ] **Step 1: Write the failing tests** — append these methods inside `SchemaMigrationTests` (before the closing brace at line 76):

```swift
    func testV6ExtendsGoals() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "goals").map { $0.name }
            XCTAssertTrue(["why", "status", "cat", "updated_at"].allSatisfy(cols.contains), "goals missing v6 columns")
        }
    }

    func testV6CreatesJournal() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            XCTAssertTrue(try conn.tableExists("journal"))
            let cols = try conn.columns(in: "journal").map { $0.name }
            XCTAssertTrue(["id", "created_at", "kind", "goal_id", "cat", "title", "desc", "confidence", "evidence", "status"].allSatisfy(cols.contains))
        }
    }

    func testV6AddsGoalIdToUserEvents() throws {
        let db = try DatabaseService(inMemory: true)
        try db.dbQueue.read { conn in
            let cols = try conn.columns(in: "user_events").map { $0.name }
            XCTAssertTrue(cols.contains("goal_id"), "user_events needs goal_id for check-ins")
        }
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter SchemaMigrationTests`
Expected: FAIL — `journal` table missing, `goals` lacks `status`.

- [ ] **Step 3: Implement the migration** — insert after the `v5_tailored_data_model` migration block closes (after line 213, before line 215 `try migrator.migrate(dbQueue)`):

```swift
        migrator.registerMigration("v6_goals_and_journal") { db in
            // Granular goals gain motivation, lifecycle, optional category, and a touch timestamp.
            try db.alter(table: "goals") { t in
                t.add(column: "why", .text)
                t.add(column: "status", .text).notNull().defaults(to: "active")  // active|done|abandoned
                t.add(column: "cat", .text)
                t.add(column: "updated_at", .datetime)
            }
            try db.execute(sql: "UPDATE goals SET updated_at = created_at WHERE updated_at IS NULL")

            // Episodic memory: dated, evidenced agent notes. kind splits the three views
            // (insight cards / goal journey / check-in outcomes). Evidence is JSON time-ranges.
            try db.create(table: "journal") { t in
                t.column("id", .text).primaryKey()
                t.column("created_at", .datetime).notNull()
                t.column("kind", .text).notNull()                 // insight|progress|checkin|milestone
                t.column("goal_id", .text).references("goals", onDelete: .setNull)
                t.column("cat", .text)
                t.column("title", .text).notNull()
                t.column("desc", .text)
                t.column("confidence", .double)
                t.column("evidence", .text)                       // JSON: [{start_at,end_at}]
                t.column("status", .text).notNull().defaults(to: "active")  // active|dismissed|superseded
            }
            try db.create(indexOn: "journal", columns: ["created_at"])
            try db.create(indexOn: "journal", columns: ["goal_id"])
            try db.create(indexOn: "journal", columns: ["kind"])

            // A scheduled check-in is a user_events row (cat='checkin') attached to a goal.
            try db.alter(table: "user_events") { t in
                t.add(column: "goal_id", .text).references("goals", onDelete: .setNull)
            }
        }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter SchemaMigrationTests`
Expected: PASS (all migration tests).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift apps/macos/Bogi/Tests/BogiAppTests/SchemaMigrationTests.swift
git commit -m "feat(macos): migration v6 — goals lifecycle, journal table, user_events.goal_id"
```

---

## Task 2: Extend GoalRecord + GoalsService

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/DataBank/Goals.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/GoalsServiceTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `GoalsServiceTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class GoalsServiceTests: XCTestCase {
    private func service() throws -> GoalsService {
        GoalsService(database: try DatabaseService(inMemory: true))
    }

    func testAddDefaultsToActiveAndStampsUpdatedAt() throws {
        let s = try service()
        let g = s.add(title: "Run a half marathon", period: "quarter", why: "feel strong")
        XCTAssertEqual(g.status, "active")
        XCTAssertEqual(g.why, "feel strong")
        XCTAssertNotNil(g.updatedAt)
    }

    func testUpdateTransitionsStatusAndFields() throws {
        let s = try service()
        let g = s.add(title: "Ship v1", period: "month")
        XCTAssertTrue(s.update(id: g.id, status: "done", target: "by Friday"))
        let reloaded = s.all().first { $0.id == g.id }
        XCTAssertEqual(reloaded?.status, "done")
        XCTAssertEqual(reloaded?.target, "by Friday")
        XCTAssertFalse(s.update(id: "nope", status: "done"))
    }

    func testAllFilterByStatus() throws {
        let s = try service()
        let a = s.add(title: "A", period: "month")
        _ = s.add(title: "B", period: "month")
        XCTAssertTrue(s.update(id: a.id, status: "done"))
        XCTAssertEqual(s.all(status: "active").count, 1)
        XCTAssertEqual(s.all(status: "active").first?.title, "B")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter GoalsServiceTests`
Expected: FAIL — `GoalRecord` has no `status`/`why`/`updatedAt`; `add` has no `why:`; no `update`/`all(status:)`.

- [ ] **Step 3: Replace the file contents** of `Goals.swift`:

```swift
import Foundation
import GRDB

/// A goal the coach references when judging plan-vs-reality. Persisted to the `goals` table
/// (created by SchemaMigrator; extended in v6 with lifecycle + motivation).
struct GoalRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "goals"

    var id: String
    var title: String
    var period: String          // month | quarter | year | custom
    var target: String?
    var createdAt: Date
    var why: String?
    var status: String          // active | done | abandoned
    var cat: String?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, period, target, why, status, cat
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// CRUD over goals.
final class GoalsService {
    private let database: DatabaseService

    init(database: DatabaseService) {
        self.database = database
    }

    /// Create and persist a new goal (defaults to active).
    @discardableResult
    func add(title: String, period: String, target: String? = nil,
             why: String? = nil, cat: String? = nil) -> GoalRecord {
        let now = Date()
        let goal = GoalRecord(
            id: UUID().uuidString, title: title, period: period, target: target,
            createdAt: now, why: why, status: "active", cat: cat, updatedAt: now)
        try? database.dbQueue.write { db in try goal.insert(db) }
        return goal
    }

    /// Goals oldest first, optionally filtered by status.
    func all(status: String? = nil) -> [GoalRecord] {
        (try? database.dbQueue.read { db in
            var request = GoalRecord.order(Column("created_at"))
            if let status { request = request.filter(Column("status") == status) }
            return try request.fetchAll(db)
        }) ?? []
    }

    /// Mutate any subset of mutable fields; bumps updated_at. Returns false if the id is unknown.
    @discardableResult
    func update(id: String, status: String? = nil, why: String? = nil,
                target: String? = nil, cat: String? = nil) -> Bool {
        ((try? database.dbQueue.write { db -> Bool in
            guard var g = try GoalRecord.fetchOne(db, key: id) else { return false }
            if let status { g.status = status }
            if let why { g.why = why }
            if let target { g.target = target }
            if let cat { g.cat = cat }
            g.updatedAt = Date()
            try g.update(db)
            return true
        }) ?? false)
    }

    func delete(id: String) {
        try? database.dbQueue.write { db in _ = try GoalRecord.deleteOne(db, key: id) }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter GoalsServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/DataBank/Goals.swift apps/macos/Bogi/Tests/BogiAppTests/GoalsServiceTests.swift
git commit -m "feat(macos): goals gain why/status/cat/updated_at + update/all(status:)"
```

---

## Task 3: JournalEntry + JournalRepository

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Journal/JournalEntry.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Journal/JournalRepository.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JournalRepositoryTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `JournalRepositoryTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class JournalRepositoryTests: XCTestCase {
    private func repo() throws -> JournalRepository {
        JournalRepository(database: try DatabaseService(inMemory: true))
    }

    private func entry(_ id: String, kind: String, goalId: String? = nil) -> JournalEntry {
        JournalEntry(id: id, createdAt: Date(), kind: kind, goalId: goalId, cat: nil,
                     title: "t-\(id)", desc: nil, confidence: nil, evidence: nil, status: "active")
    }

    func testInsertAndFilterByKind() throws {
        let r = try repo()
        r.insert(entry("a", kind: "insight"))
        r.insert(entry("b", kind: "checkin", goalId: "g1"))
        XCTAssertEqual(r.entries(kind: "insight").map { $0.id }, ["a"])
        XCTAssertEqual(r.entries(goalId: "g1").map { $0.id }, ["b"])
        XCTAssertEqual(r.entries().count, 2)
    }

    func testSetStatusHides() throws {
        let r = try repo()
        r.insert(entry("a", kind: "insight"))
        r.setStatus(id: "a", status: "dismissed")
        XCTAssertEqual(r.entries(kind: "insight", status: "active").count, 0)
        XCTAssertEqual(r.entries(kind: "insight", status: "dismissed").count, 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter JournalRepositoryTests`
Expected: FAIL — no `JournalEntry` / `JournalRepository`.

- [ ] **Step 3a: Create `JournalEntry.swift`:**

```swift
import Foundation
import GRDB

/// One dated, agent-authored note: a behavioural insight (Notice), a goal-progress entry, a
/// logged check-in, or a milestone. Episodic memory, distinct from the synthesized
/// `behaviour_profile` doc (Remember). Lives in the `journal` table (SchemaMigrator v6).
struct JournalEntry: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "journal"

    var id: String
    var createdAt: Date
    var kind: String            // insight | progress | checkin | milestone
    var goalId: String?
    var cat: String?
    var title: String
    var desc: String?
    var confidence: Double?
    var evidence: String?       // JSON string: [{start_at,end_at}]
    var status: String          // active | dismissed | superseded

    enum CodingKeys: String, CodingKey {
        case id, kind, cat, title, desc, confidence, evidence, status
        case createdAt = "created_at"
        case goalId = "goal_id"
    }
}
```

- [ ] **Step 3b: Create `JournalRepository.swift`:**

```swift
import Foundation
import GRDB

/// Read/write over the episodic journal. Mirrors the DatabaseService-injection style of the
/// other repositories.
final class JournalRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func insert(_ entry: JournalEntry) {
        try? database.dbQueue.write { db in try entry.insert(db) }
    }

    /// Newest first. Filter by kind, goal, and/or status; cap with limit.
    func entries(kind: String? = nil, goalId: String? = nil,
                 status: String? = nil, limit: Int? = nil) -> [JournalEntry] {
        (try? database.dbQueue.read { db in
            var request = JournalEntry.all()
            if let kind { request = request.filter(Column("kind") == kind) }
            if let goalId { request = request.filter(Column("goal_id") == goalId) }
            if let status { request = request.filter(Column("status") == status) }
            request = request.order(Column("created_at").desc)
            if let limit { request = request.limit(limit) }
            return try request.fetchAll(db)
        }) ?? []
    }

    func setStatus(id: String, status: String) {
        try? database.dbQueue.write { db in
            guard var e = try JournalEntry.fetchOne(db, key: id) else { return }
            e.status = status
            try e.update(db)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter JournalRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Journal/
git add apps/macos/Bogi/Tests/BogiAppTests/JournalRepositoryTests.swift
git commit -m "feat(macos): JournalEntry + JournalRepository (episodic agent notes)"
```

---

## Task 4: UserEvent.goalId + UserEventRepository helpers

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEvent.swift`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEventRepository.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JournalRepositoryTests.swift` (add a case — same file, it already boots an in-memory DB)

- [ ] **Step 1: Add the failing test** — append inside `JournalRepositoryTests` (before its closing brace):

```swift
    func testUserEventForGoalAndDelete() throws {
        let db = try DatabaseService(inMemory: true)
        let events = UserEventRepository(database: db)
        let now = Date()
        let e = UserEvent(id: "ev1", title: "Check in: half marathon", desc: nil, cat: "checkin",
                          sub: nil, startAt: now, endAt: now.addingTimeInterval(300),
                          createdAt: now, goalId: "g1")
        events.insert(e)
        XCTAssertEqual(events.events(forGoal: "g1").map { $0.id }, ["ev1"])
        events.delete(id: "ev1")
        XCTAssertTrue(events.events(forGoal: "g1").isEmpty)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter JournalRepositoryTests`
Expected: FAIL — `UserEvent` has no `goalId`; no `events(forGoal:)` / `delete(id:)`.

- [ ] **Step 3a: Replace `UserEvent.swift`:**

```swift
import Foundation
import GRDB

/// A real-world commitment the user mentioned in chat (meeting, gym, appointment). Lives in the
/// unified cat/sub/title/desc shape, separate from planned_blocks. A `cat='checkin'` event with a
/// `goalId` is a scheduled goal check-in (v6).
struct UserEvent: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "user_events"
    var id: String
    var title: String
    var desc: String?
    var cat: String?
    var sub: String?
    var startAt: Date
    var endAt: Date
    var createdAt: Date
    var goalId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, desc, cat, sub
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
        case goalId = "goal_id"
    }
}
```

- [ ] **Step 3b: Add to `UserEventRepository.swift`** — insert these methods before the final closing brace (after `events(overlapping:)`):

```swift
    /// Events attached to a goal (its scheduled check-ins), soonest first.
    func events(forGoal goalId: String) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("goal_id") == goalId)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    func delete(id: String) {
        try? database.dbQueue.write { db in _ = try UserEvent.deleteOne(db, key: id) }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter JournalRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Events/
git add apps/macos/Bogi/Tests/BogiAppTests/JournalRepositoryTests.swift
git commit -m "feat(macos): UserEvent.goalId + events(forGoal:)/delete for check-ins"
```

---

## Task 5: Sidecar action tools — manage_goal, log_journal, set_journal_status, add_event goal_id

**Files:**
- Modify: `apps/macos/Bogi/sidecar/src/tools/actionTools.ts`
- Test: `apps/macos/Bogi/sidecar/test/actionTools.test.ts`

- [ ] **Step 1: Add the failing test** — append to `actionTools.test.ts`:

```typescript
test("manage_goal forwards op + fields", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true, id: "g1" }; });
  const out = JSON.parse(await tools.find((t) => t.name === "manage_goal")!.invoke({ op: "add", title: "Half marathon", why: "feel strong", period: "quarter" }));
  expect(out).toEqual({ ok: true, id: "g1" });
  expect(seen[0].name).toBe("manage_goal");
  expect(seen[0].input.title).toBe("Half marathon");
});

test("log_journal + set_journal_status forward", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true, id: "j1" }; });
  await tools.find((t) => t.name === "log_journal")!.invoke({ kind: "insight", title: "Loses focus ~35m into editing", confidence: 0.7 });
  await tools.find((t) => t.name === "set_journal_status")!.invoke({ id: "j1", status: "dismissed" });
  expect(seen.map((s) => s.name)).toEqual(["log_journal", "set_journal_status"]);
  expect(seen[0].input.kind).toBe("insight");
});

test("add_event forwards goal_id for check-ins", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true, id: "ev1" }; });
  await tools.find((t) => t.name === "add_event")!.invoke({ title: "Check in: half marathon", start: "2026-06-08T18:00:00Z", end: "2026-06-08T18:05:00Z", cat: "checkin", goal_id: "g1" });
  expect(seen[0].input.goal_id).toBe("g1");
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/actionTools.test.ts`
Expected: FAIL — `manage_goal`/`log_journal`/`set_journal_status` not found; `add_event` rejects `goal_id` (strict schema).

- [ ] **Step 3a: Add the three tools** — in `actionTools.ts`, insert after `add_event` (after line 85, before `return [...]`):

```typescript
  const manage_goal = tool(
    async (input) => JSON.stringify(await callAction("manage_goal", input)),
    {
      name: "manage_goal",
      description: "Curate the user's goals. op 'add' (title, why?, period?, target?, cat?) creates a goal; op 'update' (id, status?, why?, target?, cat?) changes one. status is active, done, or abandoned. cat, if given, must be an existing category.",
      schema: z.object({
        op: z.enum(["add", "update"]),
        id: z.string().nullish(),
        title: z.string().nullish(),
        why: z.string().nullish(),
        period: z.string().nullish(),
        target: z.string().nullish(),
        status: z.string().nullish(),
        cat: z.string().nullish(),
      }),
    }
  );

  const log_journal = tool(
    async (input) => JSON.stringify(await callAction("log_journal", input)),
    {
      name: "log_journal",
      description: "Record a dated note. kind 'insight' = a behavioural pattern you noticed (give a short title, a one-line desc, a confidence 0..1, and evidence time-ranges). kind 'progress'/'checkin'/'milestone' = a note about a goal (pass goal_id). cat, if given, must be an existing category. This is your episodic memory; periodically fold durable insights into write_behaviour.",
      schema: z.object({
        kind: z.enum(["insight", "progress", "checkin", "milestone"]),
        title: z.string(),
        desc: z.string().nullish(),
        goal_id: z.string().nullish(),
        cat: z.string().nullish(),
        confidence: z.number().nullish(),
        evidence: z.array(z.object({ start_at: z.string(), end_at: z.string() })).nullish(),
      }),
    }
  );

  const set_journal_status = tool(
    async (input) => JSON.stringify(await callAction("set_journal_status", input)),
    {
      name: "set_journal_status",
      description: "Update a journal entry's status: 'dismissed' to hide it, 'superseded' when a newer insight replaces it, or 'active'.",
      schema: z.object({
        id: z.string(),
        status: z.enum(["active", "dismissed", "superseded"]),
      }),
    }
  );
```

- [ ] **Step 3b: Extend `add_event` schema** — add `goal_id` to its `z.object` (after the `desc` line, line 82):

```typescript
        goal_id: z.string().nullish(),
```

- [ ] **Step 3c: Update the return array** (line 87):

```typescript
  return [create_block, move_block, post_nudge, manage_categories, write_behaviour, add_event, manage_goal, log_journal, set_journal_status];
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/actionTools.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/actionTools.ts apps/macos/Bogi/sidecar/test/actionTools.test.ts
git commit -m "feat(sidecar): manage_goal, log_journal, set_journal_status + add_event goal_id"
```

---

## Task 6: Swift action handlers for the new tools

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/SidecarGoalsHandlerTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `SidecarGoalsHandlerTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class SidecarGoalsHandlerTests: XCTestCase {
    private func iso(_ s: String) -> String { s }

    func testManageGoalAddRoutes() async {
        var seenOp: String?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            manageGoal: { op, _ in seenOp = op; return ["ok": true, "id": "g1"] })
        let out = await h.handle("manage_goal", ["op": "add", "title": "Half marathon"])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(seenOp, "add")
    }

    func testLogJournalRejectsBadKind() async {
        let h = SidecarActionHandlers(createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil })
        let out = await h.handle("log_journal", ["kind": "nonsense", "title": "x"])
        XCTAssertEqual(out["error"] as? String, "bad_input")
    }

    func testLogJournalInsertsValidEntry() async {
        var inserted: JournalEntry?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            logJournal: { entry in inserted = entry; return entry.id })
        let out = await h.handle("log_journal", ["kind": "insight", "title": "Loses focus ~35m into editing", "confidence": 0.7])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(inserted?.kind, "insight")
        XCTAssertEqual(inserted?.title, "Loses focus ~35m into editing")
    }

    func testLogJournalRejectsUnknownCat() async {
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            categoryExists: { _ in false },
            logJournal: { $0.id })
        let out = await h.handle("log_journal", ["kind": "insight", "title": "x", "cat": "ghost"])
        XCTAssertEqual(out["error"] as? String, "bad_input")
    }

    func testAddEventCarriesGoalId() async {
        var seen: UserEvent?
        let h = SidecarActionHandlers(
            createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
            addEvent: { ev in seen = ev; return ev.id })
        let out = await h.handle("add_event", [
            "title": "Check in", "start": "2026-06-08T18:00:00Z", "end": "2026-06-08T18:05:00Z",
            "cat": "checkin", "goal_id": "g1"])
        XCTAssertEqual(out["ok"] as? Bool, true)
        XCTAssertEqual(seen?.goalId, "g1")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter SidecarGoalsHandlerTests`
Expected: FAIL — no `manageGoal`/`logJournal` params; `add_event` ignores `goal_id`.

- [ ] **Step 3a: Add typealiases + stored props + init params** in `SidecarActionHandlers.swift`. After line 13 (`typealias CategoryExists`) add:

```swift
    typealias ManageGoal = (_ op: String, _ args: [String: Any]) async -> [String: Any]
    typealias LogJournal = (_ entry: JournalEntry) async -> String?
    typealias SetJournalStatus = (_ id: String, _ status: String) async -> Bool
    typealias GoalExists = (_ id: String) async -> Bool
```

After line 22 (`private let categoryExists: CategoryExists`) add:

```swift
    private let manageGoal: ManageGoal
    private let logJournal: LogJournal
    private let setJournalStatus: SetJournalStatus
    private let goalExists: GoalExists
```

Add these defaulted params to `init` (after `addEvent:` on line 34):

```swift
         manageGoal: @escaping ManageGoal = { _, _ in ["ok": false, "error": "unsupported"] },
         logJournal: @escaping LogJournal = { _ in nil },
         setJournalStatus: @escaping SetJournalStatus = { _, _ in false },
         goalExists: @escaping GoalExists = { _ in true },
```

And assign them in the init body (after `self.categoryExists = categoryExists` on line 42):

```swift
        self.manageGoal = manageGoal
        self.logJournal = logJournal
        self.setJournalStatus = setJournalStatus
        self.goalExists = goalExists
```

- [ ] **Step 3b: Extend `add_event` to carry goal_id** — in the `case "add_event":` block, replace the `UserEvent(...)` construction (lines 111-113) with:

```swift
            let goalId = input["goal_id"] as? String
            if let goalId, !(await goalExists(goalId)) { return ["ok": false, "error": "bad_input"] }
            let event = UserEvent(id: UUID().uuidString, title: title, desc: input["desc"] as? String,
                                  cat: cat, sub: input["sub"] as? String,
                                  startAt: start, endAt: end, createdAt: Date(), goalId: goalId)
```

- [ ] **Step 3c: Add the new cases** — insert before `default:` (line 116):

```swift
        case "manage_goal":
            guard let op = input["op"] as? String else { return ["ok": false, "error": "bad_input"] }
            if let cat = input["cat"] as? String, !(await categoryExists(cat)) {
                return ["ok": false, "error": "bad_input"]
            }
            return await manageGoal(op, input)
        case "log_journal":
            let allowedKinds: Set<String> = ["insight", "progress", "checkin", "milestone"]
            guard let kind = input["kind"] as? String, allowedKinds.contains(kind),
                  let title = input["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return ["ok": false, "error": "bad_input"] }
            if let cat = input["cat"] as? String, !(await categoryExists(cat)) {
                return ["ok": false, "error": "bad_input"]
            }
            if let goalId = input["goal_id"] as? String, !(await goalExists(goalId)) {
                return ["ok": false, "error": "bad_input"]
            }
            let evidenceJSON: String? = {
                guard let ev = input["evidence"] else { return nil }
                guard let data = try? JSONSerialization.data(withJSONObject: ev) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
            let entry = JournalEntry(
                id: UUID().uuidString, createdAt: Date(), kind: kind,
                goalId: input["goal_id"] as? String, cat: input["cat"] as? String,
                title: title, desc: input["desc"] as? String,
                confidence: input["confidence"] as? Double, evidence: evidenceJSON, status: "active")
            if let id = await logJournal(entry) { return ["ok": true, "id": id] }
            return ["ok": false, "error": "insert_failed"]
        case "set_journal_status":
            guard let id = input["id"] as? String, let status = input["status"] as? String else {
                return ["ok": false, "error": "bad_input"]
            }
            return ["ok": await setJournalStatus(id, status)]
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter SidecarGoalsHandlerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift apps/macos/Bogi/Tests/BogiAppTests/SidecarGoalsHandlerTests.swift
git commit -m "feat(macos): handlers for manage_goal/log_journal/set_journal_status + add_event goal_id"
```

---

## Task 7: Sidecar read tools — list_goals fields, list_journal, summarize_range insights

**Files:**
- Modify: `apps/macos/Bogi/sidecar/src/tools/readTools.ts`
- Test: `apps/macos/Bogi/sidecar/test/readTools.test.ts`

- [ ] **Step 1: Extend the test fixture + add tests** in `readTools.test.ts`. (The existing `test("list_goals returns active goals")` at line ~85 stays green unchanged — g1 is active and sorts first under the new active-only default; do not edit or remove it.)

First, in the `beforeAll` SQL, replace the `goals` CREATE/INSERT (lines 16 and 35) so the table has the v6 columns and a journal table exists. Replace line 16:

```typescript
    CREATE TABLE goals (id TEXT PRIMARY KEY, title TEXT, period TEXT, target TEXT, created_at TEXT,
      why TEXT, status TEXT, cat TEXT, updated_at TEXT);
    CREATE TABLE journal (id TEXT PRIMARY KEY, created_at TEXT, kind TEXT, goal_id TEXT, cat TEXT,
      title TEXT, desc TEXT, confidence REAL, evidence TEXT, status TEXT);
```

Replace the goals INSERT (line 35) and add journal seed rows:

```typescript
    INSERT INTO goals (id,title,period,target,created_at,why,status,cat) VALUES
      ('g1','Ship Bogi','quarter','beta by July','2026-05-01T00:00:00Z','love it','active','deepwork'),
      ('g2','Old goal','month',NULL,'2026-04-01T00:00:00Z',NULL,'done',NULL);
    INSERT INTO journal (id,created_at,kind,goal_id,cat,title,desc,confidence,evidence,status) VALUES
      ('j1','2026-06-05T20:00:00Z','insight',NULL,NULL,'Loses focus ~35m into editing','dips after 35m',0.7,NULL,'active'),
      ('j2','2026-06-06T20:00:00Z','progress','g1',NULL,'Shipped the migration',NULL,NULL,NULL,'active');
```

Then append these tests at the end of the file:

```typescript
test("list_goals returns active goals with fields by default", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_goals")!.invoke({}));
  expect(out.goals.length).toBe(1);
  expect(out.goals[0].title).toBe("Ship Bogi");
  expect(out.goals[0].status).toBe("active");
  expect(out.goals[0].why).toBe("love it");
});

test("list_goals includeAll returns done goals too", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_goals")!.invoke({ includeAll: true }));
  expect(out.goals.length).toBe(2);
});

test("list_journal filters by kind and goal_id", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const lj = tools.find((t) => t.name === "list_journal")!;
  const insights = JSON.parse(await lj.invoke({ kind: "insight" }));
  expect(insights.entries.map((e: any) => e.id)).toEqual(["j1"]);
  const forGoal = JSON.parse(await lj.invoke({ goal_id: "g1" }));
  expect(forGoal.entries.map((e: any) => e.id)).toEqual(["j2"]);
});

test("summarize_range includes recentInsights", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "summarize_range")!.invoke({ start: "2026-06-01T00:00:00Z", end: "2026-06-02T23:59:59Z" }));
  expect(Array.isArray(out.recentInsights)).toBe(true);
  expect(out.recentInsights.some((i: any) => i.title.includes("Loses focus"))).toBe(true);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/readTools.test.ts`
Expected: FAIL — `list_journal` not found; `list_goals` lacks `status`/`why` and `includeAll`; no `recentInsights`.

- [ ] **Step 3a: Replace the `list_goals` tool** (lines 174-187) with:

```typescript
  const list_goals = tool(
    async ({ includeAll }) => {
      const db = open();
      try {
        const where = includeAll ? "" : "WHERE status = 'active'";
        const rows = db.prepare(
          `SELECT id, title, period, target, why, status, cat FROM goals ${where} ORDER BY created_at`
        ).all();
        return JSON.stringify({ goals: rows });
      } finally { db.close(); }
    },
    {
      name: "list_goals",
      description: "List the user's goals (id, title, period, target, why, status, cat). Active only by default; pass includeAll to include done/abandoned goals.",
      schema: z.object({ includeAll: z.boolean().nullish() }),
    }
  );
```

- [ ] **Step 3b: Add the `list_journal` tool** — insert after `list_events` (after line 245, before `return [...]`):

```typescript
  const list_journal = tool(
    async ({ kind, goal_id, limit }) => {
      const db = open();
      try {
        const clauses: string[] = ["status = 'active'"];
        const args: any[] = [];
        if (kind) { clauses.push("kind = ?"); args.push(kind); }
        if (goal_id) { clauses.push("goal_id = ?"); args.push(goal_id); }
        const cap = limit ?? 20;
        const rows = db.prepare(
          `SELECT id, created_at, kind, goal_id, cat, title, desc, confidence FROM journal
            WHERE ${clauses.join(" AND ")} ORDER BY created_at DESC LIMIT ?`
        ).all(...args, cap);
        return JSON.stringify({ entries: rows });
      } finally { db.close(); }
    },
    {
      name: "list_journal",
      description: "List your past notes (insights you noticed, goal progress, check-ins). Filter by kind ('insight'|'progress'|'checkin'|'milestone') or goal_id. Call before logging an insight so you do not repeat one you already recorded.",
      schema: z.object({
        kind: z.string().nullish(),
        goal_id: z.string().nullish(),
        limit: z.number().int().positive().nullish(),
      }),
    }
  );
```

- [ ] **Step 3c: Add `recentInsights` to `summarize_range`** — inside the `summarize_range` async body, after the `events` query (after line 100), add:

```typescript
        const recentInsights = db.prepare(
          `SELECT id, title, desc, confidence FROM journal
            WHERE kind = 'insight' AND status = 'active' ORDER BY created_at DESC LIMIT 5`
        ).all();
```

Then add `recentInsights` to BOTH returned objects: in the fallback `return JSON.stringify({ ... events });` (line 123) and the main `return JSON.stringify({ ... events });` (line 134), append `, recentInsights` before the closing `})`.

- [ ] **Step 3d: Update the return array** (line 247):

```typescript
  return [search_activity, summarize_range, list_days, list_goals, list_categories, read_behaviour, list_events, list_journal];
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/readTools.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/readTools.ts apps/macos/Bogi/sidecar/test/readTools.test.ts
git commit -m "feat(sidecar): list_journal + list_goals fields/includeAll + summarize_range recentInsights"
```

---

## Task 8: Persona — goals, journal (Notice), check-ins

**Files:**
- Modify: `apps/macos/Bogi/sidecar/src/persona.ts`
- Test: `apps/macos/Bogi/sidecar/test/main.test.ts` (add a content assertion — it already imports the agent build; if it does not reference PERSONA, add a direct import test below)

- [ ] **Step 1: Write the failing test** — create `apps/macos/Bogi/sidecar/test/persona.test.ts`:

```typescript
import { test, expect } from "vitest";
import { PERSONA } from "../src/persona.js";

test("persona instructs goal, journal, and check-in behaviour", () => {
  expect(PERSONA).toContain("manage_goal");
  expect(PERSONA).toContain("log_journal");
  expect(PERSONA).toContain("due_check_ins");
  expect(PERSONA).not.toContain("—"); // never em-dashes
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/persona.test.ts`
Expected: FAIL — persona does not mention `manage_goal`/`log_journal`/`due_check_ins`.

- [ ] **Step 3: Append guidance** to `persona.ts` — change the final line so the backtick string ends after the new paragraphs (insert before the closing `` `; ``):

```typescript

Goals: when the user states a goal or intention, call manage_goal (op 'add') with the title and
their why. Offer to schedule check-ins; if they agree, call add_event with cat 'checkin', the
goal_id, and the time. Read active goals (list_goals) before answering progress questions, and
use manage_goal (op 'update') to mark a goal done or abandoned when they tell you.

Journal: when you notice a durable behavioural pattern while judging a batch or reading logs, call
log_journal with kind 'insight', a short title, a one-line desc, a confidence, and the time-ranges
as evidence. Check recent insights first (they appear in summarize_range.recentInsights, or call
list_journal) so you do not repeat one. Log goal progress with kind 'progress' and a goal_id.
Periodically fold durable insights into write_behaviour.

Check-ins: when a due_check_in appears in a judge batch, decide whether to post_nudge inviting a
short reflection, and skip it if the user is clearly mid-flow. When the user replies to a check-in,
record it with log_journal kind 'checkin' tied to the goal, and schedule the next one with add_event
if it should recur.
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/persona.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/persona.ts apps/macos/Bogi/sidecar/test/persona.test.ts
git commit -m "feat(sidecar): persona guidance for goals, journal (Notice), check-ins"
```

---

## Task 9: Judge payload + proactive check-in firing

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift`
- Modify: `apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/JudgeProactivityTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `JudgeProactivityTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class JudgeProactivityTests: XCTestCase {
    func testPayloadSerializesGoalsAndDueCheckIns() {
        let now = Date()
        var input = JudgeInput(
            activeBlock: nil,
            observations: [(t: now, app: "Final Cut", window: "edit", text: nil, focused: true)],
            recentOffTaskMinutes: 0)
        input.activeGoals = [(id: "g1", title: "Half marathon", status: "active", cat: "health")]
        input.dueCheckIns = [(eventId: "ev1", goalId: "g1", title: "Check in: half marathon")]

        let json = JudgePrompt.userJSON(input)
        XCTAssertTrue(json.contains("active_goals"))
        XCTAssertTrue(json.contains("due_check_ins"))
        XCTAssertTrue(json.contains("Half marathon"))
        XCTAssertTrue(json.contains("ev1"))
    }

    func testPayloadOmitsGoalsAndCheckInsWhenEmpty() {
        let input = JudgeInput(activeBlock: nil, observations: [], recentOffTaskMinutes: 0)
        let json = JudgePrompt.userJSON(input)
        XCTAssertFalse(json.contains("active_goals"))
        XCTAssertFalse(json.contains("due_check_ins"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/macos/Bogi && swift test --filter JudgeProactivityTests`
Expected: FAIL — `JudgeInput` has no `activeGoals`/`dueCheckIns`.

- [ ] **Step 3a: Extend `JudgeInput`** in `JudgePrompt.swift` — add two fields after line 9 (`var activeEvents...`):

```swift
    var activeGoals: [(id: String, title: String, status: String, cat: String?)] = []
    var dueCheckIns: [(eventId: String, goalId: String?, title: String)] = []
```

- [ ] **Step 3b: Serialize them** in `JudgePrompt.userJSON` — insert after the `active_events` block (after line 58, before `root["observations"]`):

```swift
        if !input.activeGoals.isEmpty {
            root["active_goals"] = input.activeGoals.map { g -> [String: Any] in
                var o: [String: Any] = ["id": g.id, "title": g.title, "status": g.status]
                if let cat = g.cat { o["cat"] = cat }
                return o
            }
        }

        if !input.dueCheckIns.isEmpty {
            root["due_check_ins"] = input.dueCheckIns.map { c -> [String: Any] in
                var o: [String: Any] = ["event_id": c.eventId, "title": c.title]
                if let goalId = c.goalId { o["goal_id"] = goalId }
                return o
            }
        }
```

- [ ] **Step 3c: Wire the coordinator** — replace `JudgeCoordinator.swift` body to inject goals, gather due check-ins, fire even with no observations when a check-in is due, and delete fired check-ins. Replace the stored props/init and `tick()`:

Add a `goals` dependency. Change the property block (lines 9-17) to add:

```swift
    private let goals: GoalsService?
```

Change `init` (lines 19-31) to accept and store it:

```swift
    init(observations: ObservationStore,
         blocks: PlannedBlockRepository,
         segments: SegmentStore,
         sidecar: SidecarClient,
         events: UserEventRepository? = nil,
         goals: GoalsService? = nil,
         interval: TimeInterval = 300) {
        self.observations = observations
        self.blocks = blocks
        self.segments = segments
        self.sidecar = sidecar
        self.events = events
        self.goals = goals
        self.interval = interval
    }
```

Replace `tick()` (lines 47-68) with:

```swift
    /// One judge cycle. Public so a "Check in now" action can trigger it on demand. Runs when
    /// there are recent observations OR a check-in is due (so proactive check-ins fire even on a
    /// quiet screen).
    func tick() async {
        let now = Date()
        let recent = observations.recent(within: interval, now: now)
        let overlapping = events?.events(overlapping: now) ?? []
        let dueCheckIns = overlapping.filter { $0.cat == "checkin" }
        guard !recent.isEmpty || !dueCheckIns.isEmpty else { return }

        let obs = recent.map {
            (t: $0.capturedAt, app: $0.activeApp, window: $0.activeWindowTitle,
             text: $0.text, focused: $0.focused)
        }
        let active = blocks.activeBlock(at: now)
        let activeEvents = overlapping.filter { $0.cat != "checkin" }.map {
            (title: $0.title, cat: $0.cat, startAt: $0.startAt, endAt: $0.endAt)
        }
        var input = JudgeInput(
            activeBlock: active.map { (title: $0.title, cat: $0.cat, startAt: $0.startAt, endAt: $0.endAt) },
            observations: obs,
            recentOffTaskMinutes: segments.offTaskMinutes(within: offTaskWindow, now: now),
            activeEvents: activeEvents
        )
        input.activeGoals = goals?.all(status: "active").map {
            (id: $0.id, title: $0.title, status: $0.status, cat: $0.cat)
        } ?? []
        input.dueCheckIns = dueCheckIns.map {
            (eventId: $0.id, goalId: $0.goalId, title: $0.title)
        }

        let payload = JudgePrompt.userJSON(input)
        _ = try? await sidecar.judge(payload, threadId: "judge")

        // Surface each due check-in exactly once: delete it so it does not re-fire. Recurrence is
        // the agent scheduling the next add_event when it logs the check-in outcome.
        dueCheckIns.forEach { events?.delete(id: $0.id) }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/macos/Bogi && swift test --filter JudgeProactivityTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgePrompt.swift apps/macos/Bogi/Sources/BogiApp/Features/Judge/JudgeCoordinator.swift apps/macos/Bogi/Tests/BogiAppTests/JudgeProactivityTests.swift
git commit -m "feat(macos): judge payload carries active_goals + due_check_ins, fires on due check-in"
```

---

## Task 10: Wire everything into AppDelegate

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`

This task has no new unit test (it is composition of already-tested units); it is verified by the full build + suite in Step 3.

- [ ] **Step 1: Add a `JournalRepository` to AppState.** Near the other repository declarations (line 18-19 area: `let categories`, `let userEvents`) add:

```swift
    let journal: JournalRepository
```

And where they are constructed (line 100-101 area) add:

```swift
        self.journal = JournalRepository(database: database)
```

- [ ] **Step 2: Capture the new dependencies** for the handler closures. In the block at lines 331-337 (where `planner`, `categories`, `userEvents`, `settings` are bound), add:

```swift
        let goals = appState.goals
        let journal = appState.journal
```

- [ ] **Step 3: Add the handler closures** to the `SidecarActionHandlers(...)` initializer call (after the `addEvent:` closure on line 393-395, before the closing `)` on line 395 — add a trailing comma to the `addEvent` closure and append):

```swift
            manageGoal: { op, args in
                await MainActor.run {
                    switch op {
                    case "add":
                        guard let title = args["title"] as? String else { return ["ok": false, "error": "bad_input"] }
                        let g = goals.add(title: title, period: (args["period"] as? String) ?? "custom",
                                          target: args["target"] as? String, why: args["why"] as? String,
                                          cat: args["cat"] as? String)
                        return ["ok": true, "id": g.id]
                    case "update":
                        guard let id = args["id"] as? String else { return ["ok": false, "error": "bad_input"] }
                        let ok = goals.update(id: id, status: args["status"] as? String, why: args["why"] as? String,
                                              target: args["target"] as? String, cat: args["cat"] as? String)
                        return ["ok": ok]
                    default:
                        return ["ok": false, "error": "unknown_op"]
                    }
                }
            },
            logJournal: { entry in
                await MainActor.run { journal.insert(entry); return entry.id }
            },
            setJournalStatus: { id, status in
                await MainActor.run { journal.setStatus(id: id, status: status); return true }
            },
            goalExists: { id in
                await MainActor.run { goals.all().contains { $0.id == id } }
            }
```

- [ ] **Step 4: Pass `goals` to the coordinator** — in the `JudgeCoordinator(...)` call (lines 406-412), add the `goals:` argument after `events: userEvents`:

```swift
        let coordinator = JudgeCoordinator(
            observations: appState.observations,
            blocks: appState.plannedBlocks,
            segments: appState.segments,
            sidecar: appState.sidecar,
            events: userEvents,
            goals: appState.goals
        )
```

- [ ] **Step 5: Build + run the full suite**

Run: `cd apps/macos/Bogi && swift build && swift test`
Expected: build succeeds; all tests pass (existing 104 + the new GoalsService/Journal/SidecarGoalsHandler/JudgeProactivity/Schema cases).

Run: `cd apps/macos/Bogi/sidecar && npm test`
Expected: all sidecar tests pass (existing 31 + actionTools/readTools/persona additions).

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift
git commit -m "feat(macos): wire goals/journal handlers + goals into the judge coordinator"
```

---

## Final verification

- [ ] `cd apps/macos/Bogi && swift build && swift test` — green.
- [ ] `cd apps/macos/Bogi/sidecar && npm test` — green.
- [ ] Manual trace (read-through, no run needed): user says "I want to run a half marathon, why: feel strong" → agent calls `manage_goal add` → goal persisted (active). Agent offers check-ins → `add_event cat='checkin' goal_id` → row in `user_events`. Next judge tick where that event overlaps now → `due_check_ins` in payload → agent `post_nudge` → event deleted; on reply → `log_journal kind='checkin'`. Agent notices a pattern → `log_journal kind='insight'` with evidence → appears in `summarize_range.recentInsights` and `list_journal`.

## Follow-up (separate plan)

**Dashboard UI** surfacing this data: an Insights section (`JournalRepository.entries(kind: "insight", status: "active")` as dismissible cards) and a Goals & journey section (`GoalsService.all(status: "active")` + `UserEventRepository.events(forGoal:)` next check-in + `JournalRepository.entries(goalId:)` timeline), with category colors from `CategoryRepository.color(for:)`. To be planned against `UI/DashboardView.swift` / `UI/InsightView.swift` once this foundation lands.
```
