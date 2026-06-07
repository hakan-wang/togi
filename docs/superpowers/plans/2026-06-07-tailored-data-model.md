# Tailored Data Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every activity record one fixed field shape (`cat/sub/title/desc`) and make the category set, user memory, and a custom-events calendar into agent-curated local data.

**Architecture:** SQLite migration `v5` restructures the three record tables, replaces the unused `categories` table with a seeded `category_registry`, and adds `user_events`. The sidecar (read-only SQLite) gains read tools (`list_categories`, `read_behaviour`, `list_events`) and write tools (`manage_categories`, `write_behaviour`, `add_event`) that flow through the existing `callAction → SidecarActionHandlers` bridge, mirroring `record_segments`. The persona teaches the agent to use them.

**Tech Stack:** Swift + GRDB (app, `apps/macos/Bogi`), TypeScript + LangChain.js + better-sqlite3 + vitest (sidecar), XCTest (app).

**Spec:** `docs/superpowers/specs/2026-06-07-tailored-data-model-design.md`

---

## File structure

**Create:**
- `apps/macos/Bogi/Sources/BogiApp/Features/Categories/CategoryEntry.swift` — registry record.
- `apps/macos/Bogi/Sources/BogiApp/Features/Categories/CategoryRepository.swift` — registry CRUD + merge.
- `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEvent.swift` — events record.
- `apps/macos/Bogi/Sources/BogiApp/Features/Events/UserEventRepository.swift` — events CRUD.
- `apps/macos/Bogi/Tests/BogiAppTests/CategoryRepositoryTests.swift`
- `apps/macos/Bogi/Tests/BogiAppTests/UserEventRepositoryTests.swift`

**Modify:**
- `.../Infrastructure/Database/SchemaMigrator.swift` — migration `v5`.
- `.../Features/Judge/ActivitySegment.swift` — fields → `cat/sub/title/desc`.
- `.../Features/Judge/JudgeResult.swift` — `JudgeSegment` fields.
- `.../Features/Planner/PlannedBlock.swift` — `category`→`cat`, add `sub`/`desc`.
- `.../Infrastructure/Sidecar/SidecarActionHandlers.swift` — new cases + cat validation.
- `.../Features/Judge/JudgePrompt.swift`, `JudgeCoordinator.swift` — events context.
- `.../AppDelegate.swift` — wire repos + handlers; rebuild FTS description.
- `sidecar/src/tools/readTools.ts`, `actionTools.ts`, `recordTools.ts`, `persona.ts`.
- `sidecar/test/readTools.test.ts`, `actionTools.test.ts`, `recordTools.test.ts`.
- `Tests/BogiAppTests/SchemaMigrationTests.swift`, `SidecarActionHandlerTests.swift`, `JudgeTests.swift`.

**Commands:** Swift tests `cd apps/macos/Bogi && swift test`; sidecar `cd apps/macos/Bogi/sidecar && npm test`.

---

## Phase 1 — Foundation: migration + field restructure

This phase lands atomically: the migration renames columns, and the Swift models + their direct consumers must move together or runtime reads/writes break. Do all steps before running the suite.

### Task 1: Migration v5 + model/consumer renames

**Files:**
- Modify: `.../Infrastructure/Database/SchemaMigrator.swift:147-154`
- Modify: `.../Features/Judge/ActivitySegment.swift`
- Modify: `.../Features/Planner/PlannedBlock.swift`
- Modify: `.../Features/Judge/JudgeResult.swift`
- Modify: `.../Infrastructure/Sidecar/SidecarActionHandlers.swift:53-69`
- Modify: `.../AppDelegate.swift:339-348`
- Test: `Tests/BogiAppTests/SchemaMigrationTests.swift`

- [ ] **Step 1: Write failing migration tests**

Add to `SchemaMigrationTests.swift`:

```swift
func testV5CreatesSeededCategoryRegistry() throws {
    let db = try DatabaseService(inMemory: true)
    try db.dbQueue.read { conn in
        XCTAssertTrue(try conn.tableExists("category_registry"))
        XCTAssertFalse(try conn.tableExists("categories"), "legacy categories table should be gone")
        let count = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM category_registry") ?? 0
        XCTAssertEqual(count, 9, "9 default categories seeded")
        let deepwork = try String.fetchOne(conn, sql: "SELECT color FROM category_registry WHERE id = 'deepwork'")
        XCTAssertEqual(deepwork, "#2E5BFF")
    }
}

func testV5RenamesSegmentAndBlockColumns() throws {
    let db = try DatabaseService(inMemory: true)
    try db.dbQueue.read { conn in
        let seg = try conn.columns(in: "activity_segments").map { $0.name }
        XCTAssertTrue(["cat", "sub", "title", "desc"].allSatisfy(seg.contains))
        XCTAssertFalse(seg.contains("category"))
        XCTAssertFalse(seg.contains("sub_category"))
        let blk = try conn.columns(in: "planned_blocks").map { $0.name }
        XCTAssertTrue(["cat", "sub", "desc"].allSatisfy(blk.contains))
        XCTAssertFalse(blk.contains("category"))
    }
}

func testV5CreatesUserEvents() throws {
    let db = try DatabaseService(inMemory: true)
    try db.dbQueue.read { conn in
        XCTAssertTrue(try conn.tableExists("user_events"))
        let cols = try conn.columns(in: "user_events").map { $0.name }
        XCTAssertTrue(["cat", "sub", "title", "desc", "start_at", "end_at"].allSatisfy(cols.contains))
    }
}
```

Also update the existing `testMigrationCreatesAllCoreTables` expected list: remove `"categories"`.

- [ ] **Step 2: Run, verify fail**

Run: `cd apps/macos/Bogi && swift test --filter SchemaMigrationTests`
Expected: FAIL — `category_registry`/`user_events` missing, columns not renamed.

- [ ] **Step 3: Add the migration**

In `SchemaMigrator.swift`, after the `v4_planned_block_calendar_id` migration block (before `try migrator.migrate(dbQueue)`):

```swift
migrator.registerMigration("v5_tailored_data_model") { db in
    // Replace the unused legacy taxonomy with a flat, colored, agent-curated registry.
    try db.drop(table: "categories")
    try db.create(table: "category_registry") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
        t.column("color", .text).notNull()
        t.column("description", .text)
        t.column("sort_order", .integer).notNull().defaults(to: 0)
        t.column("created_at", .datetime).notNull()
        t.column("updated_at", .datetime).notNull()
    }
    let seed: [(String, String, String, String)] = [
        ("deepwork", "Deep work", "#2E5BFF", "focused, cognitively heavy work"),
        ("creative", "Creative", "#8B5CF6", "making things (design, writing, video)"),
        ("admin", "Admin", "#64748B", "email, scheduling, paperwork"),
        ("health", "Health", "#22C55E", "exercise, meals, rest"),
        ("social", "Social", "#EC4899", "time with people, calls"),
        ("errands", "Errands", "#F59E0B", "out and about, shopping"),
        ("leisure", "Leisure", "#14B8A6", "intentional downtime (games, shows)"),
        ("scroll", "Scroll", "#EF4444", "passive feed consumption"),
        ("personal", "Personal", "#9CA3AF", "catch-all, misc personal"),
    ]
    for (i, c) in seed.enumerated() {
        try db.execute(sql: """
            INSERT INTO category_registry (id, name, color, description, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'), datetime('now'))
            """, arguments: [c.0, c.1, c.2, c.3, i])
    }

    // Reality, judged: rename to the unified field shape.
    try db.alter(table: "activity_segments") { t in
        t.rename(column: "category", to: "cat")
        t.rename(column: "sub_category", to: "sub")
        t.rename(column: "sub_sub", to: "title")
        t.add(column: "desc", .text)
    }
    // Old free-text values are not registry ids; null them (no invented mappings).
    try db.execute(sql: "UPDATE activity_segments SET cat = NULL")

    // Plan: rename + extend (title already exists).
    try db.alter(table: "planned_blocks") { t in
        t.rename(column: "category", to: "cat")
        t.add(column: "sub", .text)
        t.add(column: "desc", .text)
    }
    try db.execute(sql: "UPDATE planned_blocks SET cat = NULL")

    // Conversation: custom events in the unified shape.
    try db.create(table: "user_events") { t in
        t.column("id", .text).primaryKey()
        t.column("title", .text).notNull()
        t.column("desc", .text)
        t.column("cat", .text)
        t.column("sub", .text)
        t.column("start_at", .datetime).notNull()
        t.column("end_at", .datetime).notNull()
        t.column("created_at", .datetime).notNull()
    }
    try db.create(indexOn: "user_events", columns: ["start_at"])
}
```

- [ ] **Step 4: Rename `ActivitySegment` fields**

Replace the properties + CodingKeys in `ActivitySegment.swift`:

```swift
var id: String
var startAt: Date
var endAt: Date
var minutes: Double
var plannedBlockId: String?
var cat: String?
var sub: String?
var title: String?
var desc: String?
var onTask: Bool?
var confidence: Double?
var judgedAt: Date

enum CodingKeys: String, CodingKey {
    case id
    case startAt = "start_at"
    case endAt = "end_at"
    case minutes
    case plannedBlockId = "planned_block_id"
    case cat
    case sub
    case title
    case desc
    case onTask = "on_task"
    case confidence
    case judgedAt = "judged_at"
}
```

- [ ] **Step 5: Rename `JudgeSegment` fields**

In `JudgeResult.swift`, change `JudgeSegment`’s `category/subCategory/subSub` to `cat/sub/title/desc` (add `desc`) with CodingKeys `cat`, `sub`, `title`, `desc`. Update the doc comment’s JSON shape to use `cat/sub/title/desc`. `NudgeGate.shouldConsiderNudge` is unaffected (uses `onTask`/`minutes`).

- [ ] **Step 6: Rename `PlannedBlock` fields**

In `PlannedBlock.swift`: rename `category` → `cat` (CodingKey `cat`), and add after it:

```swift
var sub: String? = nil
var desc: String? = nil
```
with CodingKeys `case sub` and `case desc`. Update `PlannerService.createLocalBlock` (`.../Features/Planner/PlannerService.swift:77-93`) to pass `cat: category` and `sub: nil, desc: nil` in the `PlannedBlock(...)` initializer (keep the external `category` param name for now; only the stored property changed).

- [ ] **Step 7: Update `record_segments` handler to new keys**

In `SidecarActionHandlers.swift` `case "record_segments"` (lines 53-69), change the `ActivitySegment(...)` build:

```swift
return ActivitySegment(
    id: UUID().uuidString, startAt: start, endAt: end, minutes: minutes,
    plannedBlockId: nil,
    cat: r["cat"] as? String,
    sub: r["sub"] as? String,
    title: r["title"] as? String,
    desc: r["desc"] as? String,
    onTask: r["on_task"] as? Bool, confidence: r["confidence"] as? Double, judgedAt: now)
```

- [ ] **Step 8: Update the FTS description in AppDelegate**

In `AppDelegate.swift` `recordSegments` closure (lines 339-348), rebuild the indexed description from the new fields:

```swift
let desc = [$0.cat, $0.sub, $0.title].compactMap { $0 }.joined(separator: " — ")
```

- [ ] **Step 9: Update the existing record_segments handler test**

In `SidecarActionHandlerTests.swift` `testRecordSegmentsPersists`, change the input keys to `cat/sub/title` and the assertions:

```swift
let input: [String: Any] = ["segments": [[
    "start_at": "2026-06-06T10:00:00Z", "end_at": "2026-06-06T10:05:00Z",
    "minutes": 5, "cat": "deepwork", "sub": "Litro", "title": "Editing",
    "on_task": true, "confidence": 0.9,
]]]
// ...
XCTAssertEqual(inserted.first?.cat, "deepwork")
XCTAssertEqual(inserted.first?.onTask, true)
```

(Note: this test does not yet enforce cat validation — that arrives in Task 6 with a separate test. Until then `record_segments` accepts any cat.)

- [ ] **Step 10: Run the whole Swift suite**

Run: `cd apps/macos/Bogi && swift test`
Expected: PASS (migration + handler + judge tests green; everything compiles).

- [ ] **Step 11: Commit**

```bash
git add apps/macos/Bogi/Sources apps/macos/Bogi/Tests
git commit -m "feat(macos): migration v5 — unified cat/sub/title/desc + category_registry + user_events"
```

---

## Phase 2 — Category registry (Swift)

### Task 2: CategoryEntry + read-side repository

**Files:**
- Create: `.../Features/Categories/CategoryEntry.swift`
- Create: `.../Features/Categories/CategoryRepository.swift`
- Test: `Tests/BogiAppTests/CategoryRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import BogiApp

final class CategoryRepositoryTests: XCTestCase {
    private func repo() throws -> CategoryRepository {
        CategoryRepository(database: try DatabaseService(inMemory: true))
    }

    func testAllReturnsSeededNine() throws {
        let all = try repo().all()
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.first?.id, "deepwork")           // sort_order 0
        XCTAssertEqual(all.first?.color, "#2E5BFF")
    }

    func testExistsAndColor() throws {
        let r = try repo()
        XCTAssertTrue(r.exists("scroll"))
        XCTAssertFalse(r.exists("nope"))
        XCTAssertEqual(r.color(for: "health"), "#22C55E")
        XCTAssertNil(r.color(for: "nope"))
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter CategoryRepositoryTests`
Expected: FAIL — `CategoryEntry`/`CategoryRepository` undefined.

- [ ] **Step 3: Implement model + read repo**

`CategoryEntry.swift`:

```swift
import Foundation
import GRDB

/// One row of the agent-curated category registry (the only level with a color).
struct CategoryEntry: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "category_registry"
    var id: String
    var name: String
    var color: String
    var description: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, color, description
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

`CategoryRepository.swift` (read side only for this task):

```swift
import Foundation
import GRDB

/// CRUD over the category registry. Mirrors SegmentStore's DatabaseService-injection style.
final class CategoryRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func all() -> [CategoryEntry] {
        (try? database.dbQueue.read { db in
            try CategoryEntry.order(Column("sort_order")).fetchAll(db)
        }) ?? []
    }

    func exists(_ id: String) -> Bool {
        (try? database.dbQueue.read { db in
            try CategoryEntry.filter(key: id).fetchCount(db) > 0
        }) ?? false
    }

    func color(for id: String) -> String? {
        try? database.dbQueue.read { db in
            try CategoryEntry.fetchOne(db, key: id)?.color
        }
    }
}
```

(The test helper uses `try repo().all()` — change `all()` etc. to be called without `try` since they don't throw; adjust the test to `repo().all()`. Keep signatures non-throwing.)

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter CategoryRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Categories apps/macos/Bogi/Tests/BogiAppTests/CategoryRepositoryTests.swift
git commit -m "feat(macos): CategoryEntry + read-side CategoryRepository"
```

### Task 3: Registry mutations (add / rename / recolor / merge)

**Files:**
- Modify: `.../Features/Categories/CategoryRepository.swift`
- Test: `Tests/BogiAppTests/CategoryRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testAddCreatesSluggedEntry() throws {
    let r = repo()
    let added = r.add(name: "Side Project", color: "#123456", description: nil)
    XCTAssertEqual(added?.id, "sideproject")
    XCTAssertTrue(r.exists("sideproject"))
    XCTAssertEqual(r.add(name: "Side Project").flatMap { _ in r.all().filter { $0.id == "sideproject" }.count }, 1) // no dupes
}

func testRenameAndRecolor() throws {
    let r = repo()
    XCTAssertTrue(r.rename(id: "scroll", name: "Doomscroll"))
    XCTAssertEqual(r.all().first { $0.id == "scroll" }?.name, "Doomscroll")
    XCTAssertTrue(r.recolor(id: "scroll", color: "#000000"))
    XCTAssertEqual(r.color(for: "scroll"), "#000000")
    XCTAssertFalse(r.rename(id: "nope", name: "X"))
}

func testMergeReassignsAcrossAllTablesAndDeletes() throws {
    let db = try DatabaseService(inMemory: true)
    let r = CategoryRepository(database: db)
    try db.dbQueue.write { conn in
        try conn.execute(sql: "INSERT INTO activity_segments (id,start_at,end_at,minutes,cat,judged_at) VALUES ('s1','2026-06-06 10:00:00','2026-06-06 10:05:00',5,'scroll','2026-06-06 10:05:00')")
        try conn.execute(sql: "INSERT INTO planned_blocks (id,source,title,start_at,end_at,cat,status,created_by_bogi,updated_at) VALUES ('p1','local','x','2026-06-06 09:00:00','2026-06-06 10:00:00','scroll','planned',1,'2026-06-06 09:00:00')")
        try conn.execute(sql: "INSERT INTO user_events (id,title,cat,start_at,end_at,created_at) VALUES ('e1','y','scroll','2026-06-06 11:00:00','2026-06-06 12:00:00','2026-06-06 08:00:00')")
    }
    XCTAssertTrue(r.merge(from: "scroll", into: "social"))
    XCTAssertFalse(r.exists("scroll"))
    try db.dbQueue.read { conn in
        for table in ["activity_segments", "planned_blocks", "user_events"] {
            let leftover = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(table) WHERE cat = 'scroll'") ?? -1
            XCTAssertEqual(leftover, 0, "\(table) still has scroll")
            let moved = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM \(table) WHERE cat = 'social'") ?? -1
            XCTAssertEqual(moved, 1, "\(table) not reassigned to social")
        }
    }
    XCTAssertFalse(r.merge(from: "nope", into: "social"))
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter CategoryRepositoryTests`
Expected: FAIL — `add/rename/recolor/merge` undefined.

- [ ] **Step 3: Implement mutations**

Append to `CategoryRepository`:

```swift
@discardableResult
func add(name: String, color: String? = nil, description: String? = nil) -> CategoryEntry? {
    let id = Self.slug(name)
    guard !id.isEmpty, !exists(id) else { return nil }
    let now = Date()
    let entry = CategoryEntry(
        id: id, name: name,
        color: color ?? Self.fallbackColor(avoiding: Set(all().map { $0.color })),
        description: description, sortOrder: nextSortOrder(), createdAt: now, updatedAt: now)
    try? database.dbQueue.write { db in try entry.insert(db) }
    return exists(id) ? entry : nil
}

func rename(id: String, name: String) -> Bool { update(id) { $0.name = name } }
func recolor(id: String, color: String) -> Bool { update(id) { $0.color = color } }

func merge(from: String, into: String) -> Bool {
    guard from != into, exists(from), exists(into) else { return false }
    return (try? database.dbQueue.write { db in
        for table in ["activity_segments", "planned_blocks", "user_events"] {
            try db.execute(sql: "UPDATE \(table) SET cat = ? WHERE cat = ?", arguments: [into, from])
        }
        _ = try CategoryEntry.deleteOne(db, key: from)
    }) != nil

}

private func update(_ id: String, _ mutate: (inout CategoryEntry) -> Void) -> Bool {
    ((try? database.dbQueue.write { db -> Bool in
        guard var row = try CategoryEntry.fetchOne(db, key: id) else { return false }
        mutate(&row); row.updatedAt = Date(); try row.update(db); return true
    }) ?? false)
}

private func nextSortOrder() -> Int { (all().map { $0.sortOrder }.max() ?? -1) + 1 }

static func slug(_ name: String) -> String {
    String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}

static func fallbackColor(avoiding used: Set<String>) -> String {
    let palette = ["#0EA5E9", "#A855F7", "#F97316", "#10B981", "#E11D48", "#6366F1", "#84CC16", "#06B6D4"]
    return palette.first { !used.contains($0) } ?? "#9CA3AF"
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter CategoryRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Categories apps/macos/Bogi/Tests/BogiAppTests/CategoryRepositoryTests.swift
git commit -m "feat(macos): category registry mutations + cross-table merge"
```

---

## Phase 3 — Custom events (Swift)

### Task 4: UserEvent + UserEventRepository

**Files:**
- Create: `.../Features/Events/UserEvent.swift`
- Create: `.../Features/Events/UserEventRepository.swift`
- Test: `Tests/BogiAppTests/UserEventRepositoryTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
import GRDB
@testable import BogiApp

final class UserEventRepositoryTests: XCTestCase {
    private func make() throws -> (UserEventRepository, DatabaseService) {
        let db = try DatabaseService(inMemory: true)
        return (UserEventRepository(database: db), db)
    }
    private func ev(_ id: String, _ start: String, _ end: String) -> UserEvent {
        let iso = ISO8601DateFormatter()
        return UserEvent(id: id, title: "Gym", desc: nil, cat: "health", sub: nil,
                         startAt: iso.date(from: start)!, endAt: iso.date(from: end)!, createdAt: Date())
    }

    func testInsertAndRangeQuery() throws {
        let (r, _) = try make()
        r.insert(ev("e1", "2026-06-06T18:00:00Z", "2026-06-06T19:00:00Z"))
        r.insert(ev("e2", "2026-06-08T18:00:00Z", "2026-06-08T19:00:00Z"))
        let iso = ISO8601DateFormatter()
        let inRange = r.events(inRange: iso.date(from: "2026-06-06T00:00:00Z")!, iso.date(from: "2026-06-06T23:59:59Z")!)
        XCTAssertEqual(inRange.map { $0.id }, ["e1"])
    }

    func testOverlappingForJudge() throws {
        let (r, _) = try make()
        r.insert(ev("e1", "2026-06-06T18:00:00Z", "2026-06-06T19:00:00Z"))
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(r.events(overlapping: iso.date(from: "2026-06-06T18:30:00Z")!).map { $0.id }, ["e1"])
        XCTAssertTrue(r.events(overlapping: iso.date(from: "2026-06-06T20:00:00Z")!).isEmpty)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter UserEventRepositoryTests`
Expected: FAIL — undefined.

- [ ] **Step 3: Implement**

`UserEvent.swift`:

```swift
import Foundation
import GRDB

/// A real-world commitment the user mentioned in chat (meeting, gym, appointment). Lives in the
/// unified cat/sub/title/desc shape, separate from planned_blocks.
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

    enum CodingKeys: String, CodingKey {
        case id, title, desc, cat, sub
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
    }
}
```

`UserEventRepository.swift`:

```swift
import Foundation
import GRDB

final class UserEventRepository {
    private let database: DatabaseService
    init(database: DatabaseService) { self.database = database }

    func insert(_ event: UserEvent) {
        try? database.dbQueue.write { db in try event.insert(db) }
    }

    /// Events whose start falls in [start, end] — for summaries/list_events.
    func events(inRange start: Date, _ end: Date) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("start_at") >= start && Column("start_at") <= end)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }

    /// Events active at `date` (start <= date < end) — context for the judge tick.
    func events(overlapping date: Date) -> [UserEvent] {
        (try? database.dbQueue.read { db in
            try UserEvent
                .filter(Column("start_at") <= date && Column("end_at") > date)
                .order(Column("start_at"))
                .fetchAll(db)
        }) ?? []
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter UserEventRepositoryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Events apps/macos/Bogi/Tests/BogiAppTests/UserEventRepositoryTests.swift
git commit -m "feat(macos): UserEvent model + repository"
```

---

## Phase 4 — Swift action handlers (the write bridge)

### Task 5: manage_categories / write_behaviour / add_event handlers + cat validation

**Files:**
- Modify: `.../Infrastructure/Sidecar/SidecarActionHandlers.swift`
- Test: `Tests/BogiAppTests/SidecarActionHandlerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testManageCategoriesAdd() async {
    var op: (String, [String: Any])?
    let handlers = SidecarActionHandlers(
        createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
        manageCategories: { o, args in op = (o, args); return ["ok": true] })
    let result = await handlers.handle("manage_categories", ["op": "add", "name": "Side Project", "color": "#123456"])
    XCTAssertEqual(result["ok"] as? Bool, true)
    XCTAssertEqual(op?.0, "add")
    XCTAssertEqual(op?.1["name"] as? String, "Side Project")
}

func testWriteBehaviourRejectsEmpty() async {
    var saved: String?
    let handlers = SidecarActionHandlers(
        createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
        writeBehaviour: { saved = $0 })
    XCTAssertEqual((await handlers.handle("write_behaviour", ["text": ""]))["error"] as? String, "bad_input")
    XCTAssertNil(saved)
    XCTAssertEqual((await handlers.handle("write_behaviour", ["text": "loses focus after 35m"]))["ok"] as? Bool, true)
    XCTAssertEqual(saved, "loses focus after 35m")
}

func testAddEventValidatesCategory() async {
    let iso = ISO8601DateFormatter()
    var inserted: UserEvent?
    let handlers = SidecarActionHandlers(
        createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
        categoryExists: { $0 == "health" },
        addEvent: { inserted = $0; return $0.id })
    // unknown cat rejected
    let bad = await handlers.handle("add_event", ["title": "Gym", "cat": "nope",
        "start": "2026-06-06T18:00:00Z", "end": "2026-06-06T19:00:00Z"])
    XCTAssertEqual(bad["error"] as? String, "bad_input")
    XCTAssertNil(inserted)
    // valid cat accepted
    let ok = await handlers.handle("add_event", ["title": "Gym", "cat": "health",
        "start": "2026-06-06T18:00:00Z", "end": "2026-06-06T19:00:00Z"])
    XCTAssertEqual(ok["ok"] as? Bool, true)
    XCTAssertEqual(inserted?.cat, "health")
}

func testRecordSegmentsRejectsUnknownCat() async {
    let handlers = SidecarActionHandlers(
        createBlock: { _, _, _ in nil }, moveBlock: { _, _, _ in nil },
        categoryExists: { $0 == "deepwork" },
        recordSegments: { _ in 0 })
    let input: [String: Any] = ["segments": [[
        "start_at": "2026-06-06T10:00:00Z", "end_at": "2026-06-06T10:05:00Z",
        "minutes": 5, "cat": "bogus", "on_task": true]]]
    XCTAssertEqual((await handlers.handle("record_segments", input))["error"] as? String, "bad_input")
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter SidecarActionHandlerTests`
Expected: FAIL — new init params / cases undefined.

- [ ] **Step 3: Extend the handler**

In `SidecarActionHandlers.swift` add typealiases, stored closures, init params (all defaulted so existing call sites compile):

```swift
typealias ManageCategories = (_ op: String, _ args: [String: Any]) async -> [String: Any]
typealias WriteBehaviour = (_ text: String) async -> Void
typealias AddEvent = (_ event: UserEvent) async -> String?
typealias CategoryExists = (_ id: String) async -> Bool
```

Add stored properties + init params (defaults: `manageCategories: @escaping ManageCategories = { _, _ in ["ok": false, "error": "unsupported"] }`, `writeBehaviour: @escaping WriteBehaviour = { _ in }`, `addEvent: @escaping AddEvent = { _ in nil }`, `categoryExists: @escaping CategoryExists = { _ in true }`). `categoryExists` defaults to `true` so existing tests that don't pass it keep accepting any cat.

Add cases to `handle`:

```swift
case "manage_categories":
    guard let op = input["op"] as? String else { return ["ok": false, "error": "bad_input"] }
    return await manageCategories(op, input)

case "write_behaviour":
    guard let text = input["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return ["ok": false, "error": "bad_input"] }
    await writeBehaviour(text)
    return ["ok": true]

case "add_event":
    guard let title = input["title"] as? String,
          let start = date(input["start"]), let end = date(input["end"]) else {
        return ["ok": false, "error": "bad_input"]
    }
    let cat = input["cat"] as? String
    if let cat, !(await categoryExists(cat)) { return ["ok": false, "error": "bad_input"] }
    let event = UserEvent(id: UUID().uuidString, title: title, desc: input["desc"] as? String,
                          cat: cat, sub: input["sub"] as? String,
                          startAt: start, endAt: end, createdAt: Date())
    if let id = await addEvent(event) { return ["ok": true, "id": id] }
    return ["ok": false, "error": "insert_failed"]
```

In `case "record_segments"`, before building, validate cats: after parsing `rows`, reject if any non-null `cat` is unknown:

```swift
for r in rows {
    if let cat = r["cat"] as? String, !(await categoryExists(cat)) {
        return ["ok": false, "error": "bad_input"]
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter SidecarActionHandlerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Sidecar/SidecarActionHandlers.swift apps/macos/Bogi/Tests/BogiAppTests/SidecarActionHandlerTests.swift
git commit -m "feat(macos): handlers for manage_categories/write_behaviour/add_event + cat validation"
```

---

## Phase 5 — Judge events context

### Task 6: Pass active events into the judge payload

**Files:**
- Modify: `.../Features/Judge/JudgePrompt.swift`
- Modify: `.../Features/Judge/JudgeCoordinator.swift`
- Test: `Tests/BogiAppTests/JudgeTests.swift`

- [ ] **Step 1: Write failing test**

Add to `JudgeTests.swift` (match existing `JudgePrompt.userJSON` test style):

```swift
func testUserJSONIncludesActiveEvents() throws {
    let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime]
    let input = JudgeInput(
        activeBlock: nil,
        observations: [(t: iso.date(from: "2026-06-06T10:00:00Z")!, app: "cmux", window: nil, text: nil, focused: true)],
        recentOffTaskMinutes: 0,
        activeEvents: [(title: "Gym", cat: "health",
                        startAt: iso.date(from: "2026-06-06T09:30:00Z")!,
                        endAt: iso.date(from: "2026-06-06T11:00:00Z")!)])
    let json = JudgePrompt.userJSON(input)
    XCTAssertTrue(json.contains("active_events"))
    XCTAssertTrue(json.contains("Gym"))
}

func testUserJSONOmitsEmptyEvents() throws {
    let input = JudgeInput(activeBlock: nil, observations: [], recentOffTaskMinutes: 0, activeEvents: [])
    XCTAssertFalse(JudgePrompt.userJSON(input).contains("active_events"))
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter JudgeTests`
Expected: FAIL — `JudgeInput` has no `activeEvents`.

- [ ] **Step 3: Extend JudgeInput + serialization**

In `JudgePrompt.swift`, add to `JudgeInput`:

```swift
var activeEvents: [(title: String, cat: String?, startAt: Date, endAt: Date)] = []
```

In `userJSON`, after `recent_off_task_minutes`:

```swift
if !input.activeEvents.isEmpty {
    root["active_events"] = input.activeEvents.map { e -> [String: Any] in
        var o: [String: Any] = ["title": e.title,
                                "start_at": iso.string(from: e.startAt),
                                "end_at": iso.string(from: e.endAt)]
        if let cat = e.cat { o["cat"] = cat }
        return o
    }
}
```

- [ ] **Step 4: Wire the coordinator**

In `JudgeCoordinator.swift`: add `private let events: UserEventRepository` (init param), and in `tick()` build the input with:

```swift
activeEvents: events.events(overlapping: now).map {
    (title: $0.title, cat: $0.cat, startAt: $0.startAt, endAt: $0.endAt)
}
```

(Update the `JudgeCoordinator(...)` call in `AppDelegate.swift:359` to pass `events: appState.userEvents` — `appState.userEvents` is created in Task 8.)

- [ ] **Step 5: Run, verify pass**

Run: `swift test --filter JudgeTests`
Expected: PASS. (App-wide wiring compiles after Task 8; if building the whole app now, temporarily pass a `UserEventRepository(database:)` — finalized in Task 8.)

- [ ] **Step 6: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Features/Judge apps/macos/Bogi/Tests/BogiAppTests/JudgeTests.swift
git commit -m "feat(macos): feed active user events into the judge payload"
```

---

## Phase 6 — Sidecar tools

### Task 7: list_categories + read_behaviour + list_events read tools

**Files:**
- Modify: `sidecar/src/tools/readTools.ts`
- Test: `sidecar/test/readTools.test.ts`

- [ ] **Step 1: Extend the fixture + write failing tests**

In `readTools.test.ts` `beforeAll`, add tables + rows:

```sql
CREATE TABLE category_registry (id TEXT PRIMARY KEY, name TEXT, color TEXT, description TEXT, sort_order INTEGER, created_at TEXT, updated_at TEXT);
INSERT INTO category_registry VALUES ('deepwork','Deep work','#2E5BFF','focus',0,'','' ),('scroll','Scroll','#EF4444','feeds',1,'','');
CREATE TABLE user_events (id TEXT PRIMARY KEY, title TEXT, desc TEXT, cat TEXT, sub TEXT, start_at TEXT, end_at TEXT, created_at TEXT);
INSERT INTO user_events (id,title,cat,start_at,end_at,created_at) VALUES ('ev1','Gym','health','2026-06-06 18:00:00.000','2026-06-06 19:00:00.000','2026-06-06 08:00:00.000');
INSERT INTO settings (key, value) VALUES ('user_display_name','Erik'),('north_star','Ship Togi'),('behaviour_profile','- loses focus after 35m');
```

(The `settings` table is created in the existing fixture? It is not — add `CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);` to the fixture as well.)

Tests:

```js
test("list_categories returns the registry ordered", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_categories")!.invoke({}));
  expect(out.categories.map((c: any) => c.id)).toEqual(["deepwork", "scroll"]);
  expect(out.categories[0].color).toBe("#2E5BFF");
});

test("read_behaviour returns identity + learned behaviour", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "read_behaviour")!.invoke({}));
  expect(out.name).toBe("Erik");
  expect(out.northStar).toBe("Ship Togi");
  expect(out.behaviour).toContain("35m");
});

test("list_events filters by range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "list_events")!.invoke({ start: "2026-06-06", end: "2026-06-06" }));
  expect(out.events.length).toBe(1);
  expect(out.events[0].title).toBe("Gym");
});
```

- [ ] **Step 2: Run, verify fail**

Run: `cd apps/macos/Bogi/sidecar && npx vitest run test/readTools.test.ts`
Expected: FAIL — tools not found.

- [ ] **Step 3: Implement the three tools**

In `readTools.ts` `makeReadTools`, add before `return [...]`:

```javascript
const list_categories = tool(
  async () => {
    const db = open();
    try {
      const rows = db.prepare(
        `SELECT id, name, color, description FROM category_registry ORDER BY sort_order`
      ).all();
      return JSON.stringify({ categories: rows });
    } finally { db.close(); }
  },
  { name: "list_categories", description: "List the user's current categories (id, name, color). Call this before labeling activity so you reuse an existing category when one fits.", schema: z.object({}) }
);

const read_behaviour = tool(
  async () => {
    const db = open();
    try {
      const get = (k) => (db.prepare(`SELECT value FROM settings WHERE key = ?`).get(k)?.value) ?? null;
      return JSON.stringify({
        name: get("user_display_name"),
        northStar: get("north_star"),
        northStarWhy: get("north_star_why"),
        behaviour: get("behaviour_profile"),
      });
    } finally { db.close(); }
  },
  { name: "read_behaviour", description: "Recall what you know about the user: their name, their north-star goal (and why), and the behaviour patterns you have learned. Call before judging activity or answering questions about their habits.", schema: z.object({}) }
);

const list_events = tool(
  async ({ start, end }) => {
    const db = open();
    try {
      const lo = normalizeBound(start, "start");
      const hi = normalizeBound(end, "end");
      const rows = db.prepare(
        `SELECT id, title, desc, cat, sub, start_at, end_at FROM user_events
          WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?)
          ORDER BY start_at`
      ).all(lo, hi);
      return JSON.stringify({ events: rows });
    } finally { db.close(); }
  },
  { name: "list_events", description: "List the user's real-world commitments (gym, meetings, appointments) in a date range.", schema: z.object({ start: z.string(), end: z.string() }) }
);
```

Add them to the returned array: `return [search_activity, summarize_range, list_days, list_goals, list_categories, read_behaviour, list_events];`

- [ ] **Step 4: Run, verify pass**

Run: `npx vitest run test/readTools.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/readTools.ts apps/macos/Bogi/sidecar/test/readTools.test.ts
git commit -m "feat(sidecar): list_categories, read_behaviour, list_events read tools"
```

### Task 8: cat grouping + events in summarize_range

**Files:**
- Modify: `sidecar/src/tools/readTools.ts`
- Test: `sidecar/test/readTools.test.ts`

- [ ] **Step 1: Update fixture rows + write failing assertions**

Update the existing `activity_segments` seed rows in the fixture to use `cat` instead of `category` (rename the column in the CREATE TABLE and the INSERTs to `cat`, and `sub`/`title`/`desc`). Update existing tests that read `out.topCategories[0].category` — they already key on `category` in the returned JSON; keep the returned key name `category` for stability but source it from the `cat` column. Add:

```js
test("summarize_range includes user events in range", async () => {
  const tools = makeReadTools(() => openReadOnly(path));
  const out = JSON.parse(await tools.find((t) => t.name === "summarize_range")!.invoke({ start: "2026-06-06", end: "2026-06-06" }));
  expect(out.events.map((e: any) => e.title)).toContain("Gym");
});
```

- [ ] **Step 2: Run, verify fail**

Run: `npx vitest run test/readTools.test.ts`
Expected: FAIL — `out.events` undefined; column `category` errors after rename.

- [ ] **Step 3: Implement**

In `summarize_range`: change segment SQL `s.category` → `s.cat AS category` (keep output key) wherever it groups; in `search_activity` and `list_days` change `s.category`/`category` → `s.cat AS category` / `cat`. Add an events fetch in `summarize_range` and include it:

```javascript
const events = db.prepare(
  `SELECT title, cat, start_at, end_at FROM user_events
    WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?) ORDER BY start_at`
).all(lo, hi);
```
Add `events` to both the segments and the observations-fallback return objects.

- [ ] **Step 4: Run, verify pass**

Run: `npx vitest run test/readTools.test.ts`
Expected: PASS (all readTools tests, including the timestamp + fallback ones).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools/readTools.ts apps/macos/Bogi/sidecar/test/readTools.test.ts
git commit -m "feat(sidecar): group by cat and surface user events in summaries"
```

### Task 9: write tools — manage_categories / write_behaviour / add_event + record_segments rename

**Files:**
- Modify: `sidecar/src/tools/actionTools.ts`, `sidecar/src/tools/recordTools.ts`
- Test: `sidecar/test/actionTools.test.ts`, `sidecar/test/recordTools.test.ts`

- [ ] **Step 1: Write failing tests**

In `actionTools.test.ts`:

```js
test("manage_categories forwards op + args", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  const out = JSON.parse(await tools.find((t) => t.name === "manage_categories")!.invoke({ op: "merge", from: "scroll", into: "social" }));
  expect(out).toEqual({ ok: true });
  expect(seen[0].name).toBe("manage_categories");
  expect(seen[0].input.op).toBe("merge");
});

test("write_behaviour + add_event forward", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  await tools.find((t) => t.name === "write_behaviour")!.invoke({ text: "learns fast" });
  await tools.find((t) => t.name === "add_event")!.invoke({ title: "Gym", start: "2026-06-06T18:00:00Z", end: "2026-06-06T19:00:00Z", cat: "health" });
  expect(seen.map((s) => s.name)).toEqual(["write_behaviour", "add_event"]);
});
```

In `recordTools.test.ts`, change the existing test’s segment to the new keys (`cat/sub/title`) and assert it forwards.

- [ ] **Step 2: Run, verify fail**

Run: `npx vitest run test/actionTools.test.ts test/recordTools.test.ts`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `actionTools.ts` add three tools to `makeActionTools` (same pattern as `create_block`):

```javascript
const manage_categories = tool(
  async (input) => JSON.stringify(await callAction("manage_categories", input)),
  { name: "manage_categories", description: "Curate the user's category list. op 'add' (name, color?, description?), 'rename' (id, name), 'recolor' (id, color), or 'merge' (from, into). merge reassigns that category across ALL the user's past activity, plans, and events, then deletes it, so use it deliberately.",
    schema: z.object({
      op: z.enum(["add", "rename", "recolor", "merge"]),
      id: z.string().nullish(), name: z.string().nullish(), color: z.string().nullish(),
      description: z.string().nullish(), from: z.string().nullish(), into: z.string().nullish(),
    }) }
);

const write_behaviour = tool(
  async (input) => JSON.stringify(await callAction("write_behaviour", input)),
  { name: "write_behaviour", description: "Save what you have learned about how the user works. REPLACES the whole learned-behaviour note (keep prior insights you still believe). Does not touch their name or north star. Keep it a short bulleted profile.",
    schema: z.object({ text: z.string() }) }
);

const add_event = tool(
  async (input) => JSON.stringify(await callAction("add_event", input)),
  { name: "add_event", description: "Record a real-world commitment the user mentions (meeting, gym, appointment). Resolve relative times against the current time. cat, if given, must be an existing category.",
    schema: z.object({
      title: z.string(), start: z.string(), end: z.string(),
      cat: z.string().nullish(), sub: z.string().nullish(), desc: z.string().nullish(),
    }) }
);
```
Return `[create_block, move_block, post_nudge, manage_categories, write_behaviour, add_event]`.

In `recordTools.ts`, change the `segment` zod object: `category/sub_category/sub_sub` → `cat/sub/title/desc` (all nullish except keep `start_at/end_at/minutes`). Update the description to mention cat/sub/title/desc.

- [ ] **Step 4: Run, verify pass**

Run: `npx vitest run` (whole sidecar suite)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/tools apps/macos/Bogi/sidecar/test
git commit -m "feat(sidecar): manage_categories/write_behaviour/add_event tools + record_segments cat keys"
```

---

## Phase 7 — Persona + app wiring

### Task 10: Persona guidance

**Files:** Modify `sidecar/src/persona.ts`

- [ ] **Step 1: Update the segmentation + add behaviour/events/category guidance**

Change step (1) of the judge instructions to: `Segment the activity into time blocks (cat, sub, title, desc, minutes, on_task) and call record_segments once with them.` Append after the judge block:

```
Categories: before labeling, call list_categories and reuse an existing category when one fits.
Only when nothing fits, call manage_categories to add/rename/recolor. Use merge to combine two
categories that are really the same; merge reassigns that category across all the user's past
activity, plans, and events and then removes it, so do it deliberately.

Memory: before judging a batch or answering questions about the user's habits, call read_behaviour.
Use their name when you have it, and weigh drift and advice against their north star. When you
notice a durable pattern, call read_behaviour then write_behaviour with the full updated
learned-behaviour text (it REPLACES the note; keep insights you still believe; keep it short).

Events: when the user mentions a real commitment (meeting, gym, appointment, call), call add_event,
resolving relative times against the current time.
```

- [ ] **Step 2: Build the sidecar bundle**

Run: `cd apps/macos/Bogi/sidecar && npm run build && npm test`
Expected: builds; tests PASS.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/sidecar/src/persona.ts
git commit -m "feat(sidecar): persona guidance for categories, memory, events"
```

### Task 11: Wire repositories + handlers in the app

**Files:** Modify `.../AppDelegate.swift`, and `AppState` (same file ~line 7-140)

- [ ] **Step 1: Add repositories to AppState**

In `AppState`, add stored lets initialized from `database`:

```swift
let categories: CategoryRepository
let userEvents: UserEventRepository
```
Initialize in `AppState.init` (alongside `observations`/`segments`): `self.categories = CategoryRepository(database: database)`, `self.userEvents = UserEventRepository(database: database)`.

- [ ] **Step 2: Wire the new handler closures**

In `AppDelegate.startMainExperience` where `SidecarActionHandlers(...)` is built (lines 321-348), add:

```swift
categoryExists: { id in await MainActor.run { appState.categories.exists(id) } },
manageCategories: { op, args in
    await MainActor.run {
        let r = appState.categories
        switch op {
        case "add":
            guard let name = args["name"] as? String else { return ["ok": false, "error": "bad_input"] }
            return r.add(name: name, color: args["color"] as? String, description: args["description"] as? String) != nil ? ["ok": true] : ["ok": false, "error": "exists_or_bad"]
        case "rename":
            guard let id = args["id"] as? String, let name = args["name"] as? String else { return ["ok": false, "error": "bad_input"] }
            return ["ok": r.rename(id: id, name: name)]
        case "recolor":
            guard let id = args["id"] as? String, let color = args["color"] as? String else { return ["ok": false, "error": "bad_input"] }
            return ["ok": r.recolor(id: id, color: color)]
        case "merge":
            guard let from = args["from"] as? String, let into = args["into"] as? String else { return ["ok": false, "error": "bad_input"] }
            return ["ok": r.merge(from: from, into: into)]
        default: return ["ok": false, "error": "unknown_op"]
        }
    }
},
writeBehaviour: { text in await MainActor.run { appState.settings.set("behaviour_profile", text) } },
addEvent: { event in await MainActor.run { appState.userEvents.insert(event); return event.id } }
```

- [ ] **Step 3: Pass events repo to the JudgeCoordinator**

Update the `JudgeCoordinator(...)` init (line 359) to add `events: appState.userEvents`.

- [ ] **Step 4: Build + full Swift suite**

Run: `cd apps/macos/Bogi && swift build && swift test`
Expected: builds; all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift
git commit -m "feat(macos): wire category/event repos + memory handlers into the app"
```

---

## Phase 8 — Onboarding coordination (non-code; for the michelle-merge merge)

### Task 12: Record the merge checklist

**Files:** Append a short note to the spec or a `MERGE-NOTES` section; no code.

- [ ] **Step 1: Document the integration steps** (do NOT modify the `.worktrees/michelle-merge` tree)

When `integration/michelle-merge` merges, apply:
1. In `OnboardingCoordinator.saveNorthStar()`, write `settings.set("north_star", text)` and `settings.set("north_star_why", why)` instead of `northStar.save(...)`.
2. Delete `NorthStarRecord`, `NorthStarService`, `NorthStarSync`, and the worktree's `v5_north_star` migration (its `north_star` table). Name (`user_display_name`) already matches `read_behaviour`.
3. Resolve the migration-name overlap: keep `v5_tailored_data_model`; drop `v5_north_star`.
4. Verify `read_behaviour` returns the onboarded name + north star end to end.

- [ ] **Step 2: Commit the note**

```bash
git add docs/superpowers
git commit -m "docs: michelle-merge onboarding-to-memory merge checklist"
```

---

## Self-review

- **Spec coverage:** registry (Tasks 2-3, 7, 9, 11) · enforcement/reject (Task 5) · merge-everywhere (Task 3, persona Task 10) · memory identity+behaviour (Tasks 5, 7, 11) · events (Tasks 4, 5, 6, 7-9) · judge events (Task 6) · cat grouping (Task 8) · migration (Task 1) · onboarding coordination (Task 12). All covered.
- **Type consistency:** `cat/sub/title/desc` used identically across ActivitySegment, JudgeSegment, UserEvent, PlannedBlock, tool schemas, and SQL. `categoryExists`/`manageCategories`/`writeBehaviour`/`addEvent` closure names match between handler and AppDelegate wiring. `read_behaviour` keys (`name/northStar/northStarWhy/behaviour`) match the settings keys and the spec.
- **Placeholders:** none — every step has concrete code/commands.
- **Green-build ordering:** Task 1 lands the rename atomically; later tasks are additive. Task 6 notes the AppState dependency finalized in Task 11.
