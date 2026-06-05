# Bogi Full Product Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full Bogi native macOS product described in `docs/superpowers/specs/2026-06-05-bogi-full-product-design.md`.

**Architecture:** Bogi is a native Swift macOS app with a canonical local SQLite database. The backend supports sync, auth, Google Calendar OAuth, payments, and AI orchestration, while raw user context stays local-first. Implementation is split into independently verifiable tracks because the full product spans macOS UI, local data, permissions, audio, context capture, backend APIs, Postgres, AI tools, payments, and distribution.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Package Manager, GRDB.swift, SQLite FTS5, Keychain, EventKit, AVAudioEngine, AXUIElement, ScreenCaptureKit, Vision, TypeScript, Fastify, Zod, Drizzle, Postgres, pgvector, OpenAI APIs, Stripe.

---

## Scope Structure

The approved design covers multiple independent subsystems. Treat this as a plan set:

- Track 1: native macOS shell and local SQLite.
- Track 2: Apple Calendar planning loop.
- Track 3: command parsing and voice.
- Track 4: local context and accessibility.
- Track 5: lock-in mode with screenshot/OCR fallback.
- Track 6: TypeScript backend and Postgres sync.
- Track 7: OpenAI agent layer and Bogi tools.
- Track 8: payments, observability, distribution, export, and delete flows.

Each track must end with a focused commit and verification evidence. Do not start a dependent track until the previous track's core acceptance checks pass.

## Repository Layout

Create this structure as the product baseline:

```text
apps/
  macos/
    Bogi/
      Package.swift
      Sources/
        BogiApp/
          BogiApp.swift
          AppDelegate.swift
          UI/
            MenuBarController.swift
            CommandBarWindowController.swift
            SettingsView.swift
          Features/
            Planning/
            RealityLogging/
            Voice/
            Context/
            LockIn/
            Review/
          Infrastructure/
            Database/
            Calendar/
            Keychain/
            Sync/
            Agent/
            Privacy/
      Tests/
        BogiAppTests/
  backend/
    package.json
    tsconfig.json
    src/
      server.ts
      config.ts
      db/
      routes/
      schemas/
      services/
      agents/
      payments/
      sync/
    test/
docs/
  superpowers/
    specs/
    plans/
```

## Shared Execution Rules

- Use TDD for model, parser, database, sync, backend route, and agent-tool behavior.
- Use focused manual verification for native macOS permission and window behavior when automated tests are not practical.
- Keep raw accessibility text, OCR text, screenshots, and audio-derived transcripts local unless the feature explicitly sends a summary or user-approved log.
- Commit after each task or small task group.
- Do not add Electron, unrestricted AI computer control, wake word, social features, team dashboards, or automatic blocking.

## Track 1: Native macOS Shell and Local SQLite

### Task 1: Create Swift Package App Skeleton

**Files:**
- Create: `apps/macos/Bogi/Package.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/BogiApp.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/AppSmokeTests.swift`

- [ ] **Step 1: Write the smoke test**

Create `apps/macos/Bogi/Tests/BogiAppTests/AppSmokeTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class AppSmokeTests: XCTestCase {
    func testAppMetadataIsStable() {
        XCTAssertEqual(AppMetadata.name, "Bogi")
        XCTAssertEqual(AppMetadata.minimumMacOSMajorVersion, 14)
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter AppSmokeTests
```

Expected: FAIL because `Package.swift` and `AppMetadata` do not exist.

- [ ] **Step 3: Create the package and app entry files**

Create `apps/macos/Bogi/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bogi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Bogi", targets: ["BogiApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.2.0")
    ],
    targets: [
        .executableTarget(
            name: "BogiApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        ),
        .testTarget(
            name: "BogiAppTests",
            dependencies: ["BogiApp"]
        )
    ]
)
```

Create `apps/macos/Bogi/Sources/BogiApp/BogiApp.swift`:

```swift
import SwiftUI

enum AppMetadata {
    static let name = "Bogi"
    static let minimumMacOSMajorVersion = 14
}

@main
struct BogiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
    }
}
```

- [ ] **Step 4: Run the test and verify pass**

Run:

```bash
cd apps/macos/Bogi
swift test --filter AppSmokeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add native macOS app skeleton"
```

### Task 2: Add Menu Bar, Settings, and Command Bar Shell

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/UI/MenuBarController.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/UI/CommandBarWindowController.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/UI/SettingsView.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/CommandBarTests.swift`

- [ ] **Step 1: Write the command bar state test**

Create `apps/macos/Bogi/Tests/BogiAppTests/CommandBarTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class CommandBarTests: XCTestCase {
    func testCommandBarInitialStateIsHiddenAndEmpty() {
        let model = CommandBarModel()
        XCTAssertFalse(model.isPresented)
        XCTAssertEqual(model.query, "")
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter CommandBarTests
```

Expected: FAIL because `CommandBarModel` does not exist.

- [ ] **Step 3: Add UI shell files**

Create `apps/macos/Bogi/Sources/BogiApp/UI/CommandBarWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class CommandBarModel: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""
}

struct CommandBarView: View {
    @ObservedObject var model: CommandBarModel

    var body: some View {
        TextField("Command", text: $model.query)
            .textFieldStyle(.plain)
            .padding(16)
            .frame(width: 520)
    }
}

@MainActor
final class CommandBarWindowController {
    private let model: CommandBarModel
    private var panel: NSPanel?

    init(model: CommandBarModel = CommandBarModel()) {
        self.model = model
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 72),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: CommandBarView(model: model))
            self.panel = panel
        }
        model.isPresented = true
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        model.isPresented = false
        panel?.orderOut(nil)
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/UI/MenuBarController.swift`:

```swift
import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let commandBar = CommandBarWindowController()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Bogi"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Command Bar", action: #selector(showCommandBar), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Bogi", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showCommandBar() {
        commandBar.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/UI/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Privacy") {
                Text("Raw screen and accessibility context stay local by default.")
            }
            Section("Calendar") {
                Text("Calendar permissions are required for planned blocks.")
            }
        }
        .padding()
        .frame(width: 480)
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add menu bar and command bar shell"
```

### Task 3: Add Local Database Schema

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/DatabaseService.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Planning/PlannedBlock.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/RealityLogging/RealityLog.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/DatabaseMigrationTests.swift`

- [ ] **Step 1: Write migration test**

Create `apps/macos/Bogi/Tests/BogiAppTests/DatabaseMigrationTests.swift`:

```swift
import XCTest
import GRDB
@testable import BogiApp

final class DatabaseMigrationTests: XCTestCase {
    func testMigratorCreatesCoreTables() throws {
        let dbQueue = try DatabaseQueue()
        try SchemaMigrator.migrate(dbQueue)

        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertTrue(tables.contains("planned_blocks"))
            XCTAssertTrue(tables.contains("reality_logs"))
            XCTAssertTrue(tables.contains("activity_observations"))
            XCTAssertTrue(tables.contains("sync_queue"))
        }
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter DatabaseMigrationTests
```

Expected: FAIL because `SchemaMigrator` does not exist.

- [ ] **Step 3: Implement schema**

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/SchemaMigrator.swift`:

```swift
import Foundation
import GRDB

enum SchemaMigrator {
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("create_core_tables") { db in
            try db.create(table: "planned_blocks") { table in
                table.column("id", .text).primaryKey()
                table.column("source", .text).notNull()
                table.column("external_event_id", .text)
                table.column("title", .text).notNull()
                table.column("start_at", .datetime).notNull()
                table.column("end_at", .datetime).notNull()
                table.column("category", .text)
                table.column("goal_id", .text)
                table.column("status", .text).notNull()
                table.column("created_by_bogi", .boolean).notNull().defaults(to: false)
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "reality_logs") { table in
                table.column("id", .text).primaryKey()
                table.column("block_id", .text).references("planned_blocks", onDelete: .setNull)
                table.column("start_at", .datetime).notNull()
                table.column("end_at", .datetime).notNull()
                table.column("category", .text)
                table.column("user_text", .text).notNull()
                table.column("generated_summary", .text)
                table.column("confidence", .double)
                table.column("source", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "activity_observations") { table in
                table.column("id", .text).primaryKey()
                table.column("block_id", .text).references("planned_blocks", onDelete: .setNull)
                table.column("captured_at", .datetime).notNull()
                table.column("active_app", .text)
                table.column("active_window_title", .text)
                table.column("local_text_summary", .text)
                table.column("category_guess", .text)
                table.column("confidence", .double)
                table.column("capture_method", .text).notNull()
            }

            try db.create(table: "sync_queue") { table in
                table.column("id", .text).primaryKey()
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("operation", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("attempt_count", .integer).notNull().defaults(to: 0)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Database/DatabaseService.swift`:

```swift
import Foundation
import GRDB

final class DatabaseService {
    let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try SchemaMigrator.migrate(dbQueue)
    }

    init(inMemory: Bool) throws {
        dbQueue = try DatabaseQueue()
        try SchemaMigrator.migrate(dbQueue)
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Planning/PlannedBlock.swift`:

```swift
import Foundation

struct PlannedBlock: Codable, Equatable, Identifiable {
    let id: String
    var source: String
    var externalEventID: String?
    var title: String
    var startAt: Date
    var endAt: Date
    var category: String?
    var goalID: String?
    var status: String
    var createdByBogi: Bool
    var updatedAt: Date
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/RealityLogging/RealityLog.swift`:

```swift
import Foundation

struct RealityLog: Codable, Equatable, Identifiable {
    let id: String
    var blockID: String?
    var startAt: Date
    var endAt: Date
    var category: String?
    var userText: String
    var generatedSummary: String?
    var confidence: Double?
    var source: String
    var updatedAt: Date
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add local database schema"
```

## Track 2: Apple Calendar Planning Loop

### Task 4: Add EventKit Calendar Service

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Calendar/CalendarService.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Calendar/CalendarAuthorizationState.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/CalendarAuthorizationStateTests.swift`

- [ ] **Step 1: Write authorization-state test**

Create `apps/macos/Bogi/Tests/BogiAppTests/CalendarAuthorizationStateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class CalendarAuthorizationStateTests: XCTestCase {
    func testDeniedStateRequiresUserAction() {
        XCTAssertTrue(CalendarAuthorizationState.denied.requiresUserAction)
        XCTAssertFalse(CalendarAuthorizationState.authorized.requiresUserAction)
    }
}
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter CalendarAuthorizationStateTests
```

Expected: FAIL because `CalendarAuthorizationState` does not exist.

- [ ] **Step 3: Implement calendar state and service wrapper**

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Calendar/CalendarAuthorizationState.swift`:

```swift
enum CalendarAuthorizationState: Equatable {
    case unknown
    case authorized
    case denied

    var requiresUserAction: Bool {
        switch self {
        case .denied:
            return true
        case .unknown, .authorized:
            return false
        }
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Calendar/CalendarService.swift`:

```swift
import EventKit
import Foundation

final class CalendarService {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationState() -> CalendarAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add calendar authorization service"
```

### Task 5: Add Planned Block Repository and Day Planning View

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Planning/PlannedBlockRepository.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Planning/DayPlanView.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/PlannedBlockRepositoryTests.swift`

- [ ] **Step 1: Write repository round-trip test**

Create `apps/macos/Bogi/Tests/BogiAppTests/PlannedBlockRepositoryTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class PlannedBlockRepositoryTests: XCTestCase {
    func testInsertAndFetchPlannedBlock() throws {
        let database = try DatabaseService(inMemory: true)
        let repository = PlannedBlockRepository(dbQueue: database.dbQueue)
        let block = PlannedBlock(
            id: "block_1",
            source: "local",
            externalEventID: nil,
            title: "Editing",
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            category: "video_editing",
            goalID: nil,
            status: "planned",
            createdByBogi: true,
            updatedAt: Date(timeIntervalSince1970: 50)
        )

        try repository.save(block)
        XCTAssertEqual(try repository.fetch(id: "block_1"), block)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter PlannedBlockRepositoryTests
```

Expected: FAIL because `PlannedBlockRepository` does not exist.

- [ ] **Step 3: Implement repository and day view**

Create `apps/macos/Bogi/Sources/BogiApp/Features/Planning/PlannedBlockRepository.swift`:

```swift
import Foundation
import GRDB

final class PlannedBlockRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func save(_ block: PlannedBlock) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO planned_blocks
                (id, source, external_event_id, title, start_at, end_at, category, goal_id, status, created_by_bogi, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    block.id, block.source, block.externalEventID, block.title,
                    block.startAt, block.endAt, block.category, block.goalID,
                    block.status, block.createdByBogi, block.updatedAt
                ]
            )
        }
    }

    func fetch(id: String) throws -> PlannedBlock? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM planned_blocks WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return PlannedBlock(
                id: row["id"],
                source: row["source"],
                externalEventID: row["external_event_id"],
                title: row["title"],
                startAt: row["start_at"],
                endAt: row["end_at"],
                category: row["category"],
                goalID: row["goal_id"],
                status: row["status"],
                createdByBogi: row["created_by_bogi"],
                updatedAt: row["updated_at"]
            )
        }
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Planning/DayPlanView.swift`:

```swift
import SwiftUI

struct DayPlanView: View {
    let blocks: [PlannedBlock]

    var body: some View {
        List(blocks) { block in
            VStack(alignment: .leading) {
                Text(block.title)
                Text(block.category ?? "Uncategorized")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add planned block repository"
```

## Track 3: Command Parsing and Voice

### Task 6: Add Command Parser

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Planning/BogiCommand.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Planning/CommandParser.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/CommandParserTests.swift`

- [ ] **Step 1: Write parser tests**

Create `apps/macos/Bogi/Tests/BogiAppTests/CommandParserTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class CommandParserTests: XCTestCase {
    func testParsesRealityLogCommand() {
        let parser = CommandParser()
        XCTAssertEqual(
            parser.parse("Reality log: I edited for 45 minutes"),
            .saveRealityLog(text: "I edited for 45 minutes")
        )
    }

    func testParsesStartLockInCommand() {
        let parser = CommandParser()
        XCTAssertEqual(parser.parse("start lock in"), .startLockIn)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter CommandParserTests
```

Expected: FAIL because parser types do not exist.

- [ ] **Step 3: Implement parser**

Create `apps/macos/Bogi/Sources/BogiApp/Features/Planning/BogiCommand.swift`:

```swift
enum BogiCommand: Equatable {
    case saveRealityLog(text: String)
    case startLockIn
    case unknown(raw: String)
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Planning/CommandParser.swift`:

```swift
struct CommandParser {
    func parse(_ input: String) -> BogiCommand {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if lowercased.hasPrefix("reality log:") {
            let text = String(trimmed.dropFirst("Reality log:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .saveRealityLog(text: text)
        }

        if lowercased == "start lock in" || lowercased == "start lock-in" {
            return .startLockIn
        }

        return .unknown(raw: input)
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add command parser"
```

### Task 7: Add Push-to-Talk Voice Service Boundary

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Voice/VoiceRecordingState.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Voice/VoiceService.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/VoiceRecordingStateTests.swift`

- [ ] **Step 1: Write state test**

Create `apps/macos/Bogi/Tests/BogiAppTests/VoiceRecordingStateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class VoiceRecordingStateTests: XCTestCase {
    func testInitialVoiceStateIsIdle() {
        let state = VoiceRecordingState.idle
        XCTAssertFalse(state.isRecording)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter VoiceRecordingStateTests
```

Expected: FAIL because `VoiceRecordingState` does not exist.

- [ ] **Step 3: Implement voice state and AVAudioEngine boundary**

Create `apps/macos/Bogi/Sources/BogiApp/Features/Voice/VoiceRecordingState.swift`:

```swift
enum VoiceRecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case failed(String)

    var isRecording: Bool {
        self == .recording
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Voice/VoiceService.swift`:

```swift
import AVFoundation

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var state: VoiceRecordingState = .idle
    private let engine = AVAudioEngine()

    func startPushToTalk() {
        state = .recording
    }

    func stopPushToTalk() {
        if engine.isRunning {
            engine.stop()
        }
        state = .transcribing
    }

    func markTranscriptionComplete() {
        state = .idle
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add push-to-talk voice boundary"
```

## Track 4: Local Context and Accessibility

### Task 8: Add Local Context Observation Model

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Context/ActivityObservation.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Context/ContextClassifier.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/ContextClassifierTests.swift`

- [ ] **Step 1: Write classifier test**

Create `apps/macos/Bogi/Tests/BogiAppTests/ContextClassifierTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class ContextClassifierTests: XCTestCase {
    func testClassifiesEditingFromKnownApps() {
        let classifier = ContextClassifier()
        let result = classifier.classify(activeApp: "Final Cut Pro", text: "timeline export")
        XCTAssertEqual(result.category, "video_editing")
        XCTAssertGreaterThan(result.confidence, 0.7)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter ContextClassifierTests
```

Expected: FAIL because classifier types do not exist.

- [ ] **Step 3: Implement local classifier**

Create `apps/macos/Bogi/Sources/BogiApp/Features/Context/ActivityObservation.swift`:

```swift
import Foundation

struct ActivityObservation: Codable, Equatable, Identifiable {
    let id: String
    var blockID: String?
    var capturedAt: Date
    var activeApp: String?
    var activeWindowTitle: String?
    var localTextSummary: String?
    var categoryGuess: String?
    var confidence: Double?
    var captureMethod: String
}

struct ContextClassification: Equatable {
    let category: String
    let confidence: Double
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Context/ContextClassifier.swift`:

```swift
struct ContextClassifier {
    func classify(activeApp: String, text: String) -> ContextClassification {
        let app = activeApp.lowercased()
        let content = text.lowercased()

        if app.contains("final cut") || content.contains("timeline") || content.contains("export") {
            return ContextClassification(category: "video_editing", confidence: 0.82)
        }

        if app.contains("calendar") {
            return ContextClassification(category: "planning", confidence: 0.72)
        }

        return ContextClassification(category: "unknown", confidence: 0.25)
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add local context classification"
```

### Task 9: Add Accessibility Context Boundary

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/Context/AccessibilityContextService.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Privacy/PermissionState.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/PermissionStateTests.swift`

- [ ] **Step 1: Write permission test**

Create `apps/macos/Bogi/Tests/BogiAppTests/PermissionStateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class PermissionStateTests: XCTestCase {
    func testAccessibilityDeniedIsNotUsable() {
        XCTAssertFalse(PermissionState.denied.isUsable)
        XCTAssertTrue(PermissionState.granted.isUsable)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter PermissionStateTests
```

Expected: FAIL because `PermissionState` does not exist.

- [ ] **Step 3: Implement permission and AX boundary**

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Privacy/PermissionState.swift`:

```swift
enum PermissionState: Equatable {
    case unknown
    case granted
    case denied

    var isUsable: Bool {
        self == .granted
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/Context/AccessibilityContextService.swift`:

```swift
import ApplicationServices

struct AccessibilitySnapshot: Equatable {
    let activeApp: String?
    let focusedWindowTitle: String?
    let textSummary: String
}

final class AccessibilityContextService {
    func permissionState() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .denied
    }

    func snapshot() -> AccessibilitySnapshot {
        AccessibilitySnapshot(
            activeApp: nil,
            focusedWindowTitle: nil,
            textSummary: ""
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add accessibility context boundary"
```

## Track 5: Lock-In Mode and OCR Fallback

### Task 10: Add Lock-In Session Model and Controller

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInSession.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInController.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInView.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/LockInControllerTests.swift`

- [ ] **Step 1: Write lock-in state test**

Create `apps/macos/Bogi/Tests/BogiAppTests/LockInControllerTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class LockInControllerTests: XCTestCase {
    func testStartCreatesActiveSession() {
        let controller = LockInController()
        controller.start(blockID: "block_1")
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.currentSession?.blockID, "block_1")
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter LockInControllerTests
```

Expected: FAIL because lock-in types do not exist.

- [ ] **Step 3: Implement lock-in state**

Create `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInSession.swift`:

```swift
import Foundation

struct LockInSession: Codable, Equatable, Identifiable {
    let id: String
    let blockID: String?
    let startedAt: Date
    var endedAt: Date?
    var summary: String?
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInController.swift`:

```swift
import Foundation

@MainActor
final class LockInController: ObservableObject {
    @Published private(set) var currentSession: LockInSession?

    var isActive: Bool {
        currentSession?.endedAt == nil && currentSession != nil
    }

    func start(blockID: String?) {
        currentSession = LockInSession(
            id: UUID().uuidString,
            blockID: blockID,
            startedAt: Date(),
            endedAt: nil,
            summary: nil
        )
    }

    func end(summary: String?) {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        session.summary = summary
        currentSession = session
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/LockInView.swift`:

```swift
import SwiftUI

struct LockInView: View {
    @ObservedObject var controller: LockInController

    var body: some View {
        VStack(alignment: .leading) {
            Text(controller.isActive ? "Lock-in active" : "Lock-in idle")
            Button("End") {
                controller.end(summary: nil)
            }
            .disabled(!controller.isActive)
        }
        .padding()
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add lock-in session state"
```

### Task 11: Add Screen/OCR Fallback Boundary

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/ScreenContextService.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/OCRTextRecognizer.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/ScreenContextPolicyTests.swift`

- [ ] **Step 1: Write policy test**

Create `apps/macos/Bogi/Tests/BogiAppTests/ScreenContextPolicyTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class ScreenContextPolicyTests: XCTestCase {
    func testOCRRequiresPermissionAndActiveMode() {
        let policy = ScreenContextPolicy(
            screenRecordingPermission: .granted,
            isLockInActive: true,
            isExplicitContextCommand: false
        )
        XCTAssertTrue(policy.canUseOCRFallback)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter ScreenContextPolicyTests
```

Expected: FAIL because `ScreenContextPolicy` does not exist.

- [ ] **Step 3: Implement fallback boundaries**

Create `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/ScreenContextService.swift`:

```swift
import Foundation
import ScreenCaptureKit

struct ScreenContextPolicy: Equatable {
    let screenRecordingPermission: PermissionState
    let isLockInActive: Bool
    let isExplicitContextCommand: Bool

    var canUseOCRFallback: Bool {
        screenRecordingPermission.isUsable && (isLockInActive || isExplicitContextCommand)
    }
}

final class ScreenContextService {
    func captureCurrentDisplayForOCR(policy: ScreenContextPolicy) async throws -> Data? {
        guard policy.canUseOCRFallback else { return nil }
        return nil
    }
}
```

Create `apps/macos/Bogi/Sources/BogiApp/Features/LockIn/OCRTextRecognizer.swift`:

```swift
import Foundation
import Vision

final class OCRTextRecognizer {
    func recognizeText(fromImageData data: Data) async throws -> [String] {
        []
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add screen context fallback policy"
```

## Track 6: Backend and Sync

### Task 12: Add Fastify Backend Skeleton

**Files:**
- Create: `apps/backend/package.json`
- Create: `apps/backend/tsconfig.json`
- Create: `apps/backend/src/server.ts`
- Create: `apps/backend/src/config.ts`
- Create: `apps/backend/test/health.test.ts`

- [ ] **Step 1: Write health route test**

Create `apps/backend/test/health.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server";

describe("health", () => {
  it("returns ok", async () => {
    const server = buildServer();
    const response = await server.inject({ method: "GET", url: "/health" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- health.test.ts
```

Expected: FAIL because backend package does not exist.

- [ ] **Step 3: Implement backend skeleton**

Create `apps/backend/package.json`:

```json
{
  "name": "@bogi/backend",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "tsx src/server.ts",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@fastify/cors": "^9.0.1",
    "drizzle-orm": "^0.36.4",
    "fastify": "^5.1.0",
    "pg": "^8.13.1",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/node": "^22.10.2",
    "tsx": "^4.19.2",
    "typescript": "^5.7.2",
    "vitest": "^2.1.8"
  }
}
```

Create `apps/backend/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist"
  },
  "include": ["src", "test"]
}
```

Create `apps/backend/src/config.ts`:

```ts
import { z } from "zod";

const EnvSchema = z.object({
  DATABASE_URL: z.string().url().optional(),
  OPENAI_API_KEY: z.string().optional(),
  STRIPE_SECRET_KEY: z.string().optional()
});

export function loadConfig(env: NodeJS.ProcessEnv = process.env) {
  return EnvSchema.parse(env);
}
```

Create `apps/backend/src/server.ts`:

```ts
import Fastify from "fastify";

export function buildServer() {
  const server = Fastify({ logger: true });

  server.get("/health", async () => {
    return { ok: true };
  });

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = buildServer();
  await server.listen({ port: 3000, host: "0.0.0.0" });
}
```

- [ ] **Step 4: Install dependencies and run tests**

Run:

```bash
cd apps/backend
npm install
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add backend skeleton"
```

### Task 13: Add Backend Sync Schemas and Routes

**Files:**
- Create: `apps/backend/src/schemas/sync.ts`
- Create: `apps/backend/src/routes/sync.ts`
- Modify: `apps/backend/src/server.ts`
- Create: `apps/backend/test/sync.test.ts`

- [ ] **Step 1: Write sync validation test**

Create `apps/backend/test/sync.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server";

describe("sync", () => {
  it("accepts a reality log sync payload", async () => {
    const server = buildServer();
    const response = await server.inject({
      method: "POST",
      url: "/sync/reality-logs",
      payload: {
        id: "log_1",
        startAt: "2026-06-05T10:00:00.000Z",
        endAt: "2026-06-05T10:45:00.000Z",
        userText: "Edited for 45 minutes",
        source: "manual"
      }
    });

    expect(response.statusCode).toBe(202);
    expect(response.json()).toEqual({ accepted: true });
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- sync.test.ts
```

Expected: FAIL because route does not exist.

- [ ] **Step 3: Implement sync schema and route**

Create `apps/backend/src/schemas/sync.ts`:

```ts
import { z } from "zod";

export const RealityLogSyncSchema = z.object({
  id: z.string().min(1),
  blockId: z.string().optional(),
  startAt: z.string().datetime(),
  endAt: z.string().datetime(),
  category: z.string().optional(),
  userText: z.string().min(1),
  generatedSummary: z.string().optional(),
  confidence: z.number().min(0).max(1).optional(),
  source: z.string().min(1)
});
```

Create `apps/backend/src/routes/sync.ts`:

```ts
import type { FastifyInstance } from "fastify";
import { RealityLogSyncSchema } from "../schemas/sync";

export async function registerSyncRoutes(server: FastifyInstance) {
  server.post("/sync/reality-logs", async (request, reply) => {
    RealityLogSyncSchema.parse(request.body);
    return reply.code(202).send({ accepted: true });
  });
}
```

Modify `apps/backend/src/server.ts`:

```ts
import Fastify from "fastify";
import { registerSyncRoutes } from "./routes/sync";

export function buildServer() {
  const server = Fastify({ logger: true });

  server.get("/health", async () => {
    return { ok: true };
  });

  void server.register(registerSyncRoutes);

  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const server = buildServer();
  await server.listen({ port: 3000, host: "0.0.0.0" });
}
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add backend sync route"
```

## Track 7: OpenAI Agent Layer and Bogi Tools

### Task 14: Add Agent Tool Contract

**Files:**
- Create: `apps/backend/src/agents/tools.ts`
- Create: `apps/backend/src/agents/plannerAgent.ts`
- Create: `apps/backend/test/agent-tools.test.ts`

- [ ] **Step 1: Write tool contract test**

Create `apps/backend/test/agent-tools.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { BogiToolNameSchema } from "../src/agents/tools";

describe("Bogi tools", () => {
  it("allows owned planning tools", () => {
    expect(BogiToolNameSchema.parse("read_calendar")).toBe("read_calendar");
    expect(BogiToolNameSchema.parse("save_reality_log")).toBe("save_reality_log");
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- agent-tools.test.ts
```

Expected: FAIL because agent tool contract does not exist.

- [ ] **Step 3: Implement tool contract**

Create `apps/backend/src/agents/tools.ts`:

```ts
import { z } from "zod";

export const BogiToolNameSchema = z.enum([
  "read_calendar",
  "create_calendar_block",
  "update_calendar_block",
  "get_planned_blocks",
  "save_reality_log",
  "get_reality_logs",
  "get_user_patterns",
  "summarize_day",
  "summarize_week",
  "suggest_next_plan",
  "start_lock_in_session",
  "end_lock_in_session",
  "search_local_history",
  "export_user_data"
]);

export type BogiToolName = z.infer<typeof BogiToolNameSchema>;
```

Create `apps/backend/src/agents/plannerAgent.ts`:

```ts
export const plannerAgentInstructions = `
You are Bogi, a planning and reality-log coach.
Use only Bogi-owned tools.
Do not request raw continuous screen data.
Ground planning advice in calendar blocks, reality logs, summaries, and user patterns.
`;
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add agent tool contract"
```

### Task 15: Add OpenAI Planner Request Boundary

**Files:**
- Modify: `apps/backend/package.json`
- Create: `apps/backend/src/agents/openaiPlannerRequest.ts`
- Create: `apps/backend/test/openai-planner-request.test.ts`

- [ ] **Step 1: Write planner request test**

Create `apps/backend/test/openai-planner-request.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildOpenAIPlannerRequest } from "../src/agents/openaiPlannerRequest";

describe("OpenAI planner request", () => {
  it("uses structured output and avoids raw screen data", () => {
    const request = buildOpenAIPlannerRequest({
      userQuestion: "What should I plan tomorrow?",
      retrievedContext: "Completed 60 minute editing blocks more reliably than 180 minute blocks."
    });

    expect(request.model).toBe("gpt-4.1");
    expect(request.input).toContain("Do not request raw continuous screen data.");
    expect(request.text.format.type).toBe("json_schema");
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- openai-planner-request.test.ts
```

Expected: FAIL because `openaiPlannerRequest.ts` does not exist.

- [ ] **Step 3: Add OpenAI dependency and request builder**

Modify `apps/backend/package.json` dependencies to include OpenAI:

```json
{
  "dependencies": {
    "@fastify/cors": "^9.0.1",
    "drizzle-orm": "^0.36.4",
    "fastify": "^5.1.0",
    "openai": "^4.77.0",
    "pg": "^8.13.1",
    "zod": "^3.23.8"
  }
}
```

Create `apps/backend/src/agents/openaiPlannerRequest.ts`:

```ts
type PlannerRequestInput = {
  userQuestion: string;
  retrievedContext: string;
};

export function buildOpenAIPlannerRequest(input: PlannerRequestInput) {
  return {
    model: "gpt-4.1",
    input: [
      "You are Bogi, a planning and reality-log coach.",
      "Use only Bogi-owned tools.",
      "Do not request raw continuous screen data.",
      "Ground advice in retrieved summaries, reality logs, planned blocks, and patterns.",
      `Retrieved context: ${input.retrievedContext}`,
      `User question: ${input.userQuestion}`
    ].join("\n"),
    text: {
      format: {
        type: "json_schema",
        name: "bogi_planning_response",
        schema: {
          type: "object",
          additionalProperties: false,
          required: ["summary", "suggestedPlan", "evidence"],
          properties: {
            summary: { type: "string" },
            suggestedPlan: { type: "string" },
            evidence: {
              type: "array",
              items: { type: "string" }
            }
          }
        }
      }
    }
  } as const;
}
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm install
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add openai planner request boundary"
```

## Track 8: Payments, Observability, Distribution, Export, Delete

### Task 16: Add Entitlement and Stripe Webhook Boundary

**Files:**
- Create: `apps/backend/src/payments/entitlements.ts`
- Create: `apps/backend/src/routes/stripe.ts`
- Create: `apps/backend/test/entitlements.test.ts`

- [ ] **Step 1: Write entitlement test**

Create `apps/backend/test/entitlements.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { deriveEntitlement } from "../src/payments/entitlements";

describe("entitlements", () => {
  it("marks paid lifetime customers active", () => {
    expect(deriveEntitlement({ paymentStatus: "paid", product: "lifetime" })).toEqual({
      plan: "lifetime",
      active: true
    });
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- entitlements.test.ts
```

Expected: FAIL because entitlement code does not exist.

- [ ] **Step 3: Implement entitlement boundary**

Create `apps/backend/src/payments/entitlements.ts`:

```ts
type PaymentInput = {
  paymentStatus: "paid" | "unpaid";
  product: "lifetime" | "subscription";
};

type Entitlement = {
  plan: "none" | "lifetime" | "subscription";
  active: boolean;
};

export function deriveEntitlement(input: PaymentInput): Entitlement {
  if (input.paymentStatus === "paid") {
    return { plan: input.product, active: true };
  }
  return { plan: "none", active: false };
}
```

Create `apps/backend/src/routes/stripe.ts`:

```ts
import type { FastifyInstance } from "fastify";

export async function registerStripeRoutes(server: FastifyInstance) {
  server.post("/stripe/webhook", async (_request, reply) => {
    return reply.code(202).send({ accepted: true });
  });
}
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add payment entitlement boundary"
```

### Task 17: Add Privacy Export and Delete Boundaries

**Files:**
- Create: `apps/backend/src/routes/privacy.ts`
- Create: `apps/backend/src/services/privacyExport.ts`
- Create: `apps/backend/test/privacy-export.test.ts`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Privacy/PrivacyAction.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/PrivacyActionTests.swift`

- [ ] **Step 1: Write backend export test**

Create `apps/backend/test/privacy-export.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildPrivacyExport } from "../src/services/privacyExport";

describe("privacy export", () => {
  it("includes version and user id", () => {
    expect(buildPrivacyExport("user_1")).toEqual({
      version: 1,
      userId: "user_1",
      plannedBlocks: [],
      realityLogs: [],
      summaries: []
    });
  });
});
```

- [ ] **Step 2: Write macOS privacy action test**

Create `apps/macos/Bogi/Tests/BogiAppTests/PrivacyActionTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class PrivacyActionTests: XCTestCase {
    func testDeleteCloudDataRequiresConfirmation() {
        XCTAssertTrue(PrivacyAction.deleteCloudData.requiresConfirmation)
        XCTAssertFalse(PrivacyAction.exportData.requiresConfirmation)
    }
}
```

- [ ] **Step 3: Run and verify failures**

Run:

```bash
cd apps/backend
npm test -- privacy-export.test.ts
cd ../macos/Bogi
swift test --filter PrivacyActionTests
```

Expected: both fail because privacy export/action code does not exist.

- [ ] **Step 4: Implement backend privacy export**

Create `apps/backend/src/services/privacyExport.ts`:

```ts
export function buildPrivacyExport(userId: string) {
  return {
    version: 1,
    userId,
    plannedBlocks: [],
    realityLogs: [],
    summaries: []
  };
}
```

Create `apps/backend/src/routes/privacy.ts`:

```ts
import type { FastifyInstance } from "fastify";
import { buildPrivacyExport } from "../services/privacyExport";

export async function registerPrivacyRoutes(server: FastifyInstance) {
  server.get("/privacy/export/:userId", async (request) => {
    const params = request.params as { userId: string };
    return buildPrivacyExport(params.userId);
  });

  server.delete("/privacy/account/:userId", async (_request, reply) => {
    return reply.code(202).send({ accepted: true });
  });
}
```

- [ ] **Step 5: Implement macOS privacy action**

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Privacy/PrivacyAction.swift`:

```swift
enum PrivacyAction: Equatable {
    case exportData
    case deleteLocalData
    case deleteCloudData

    var requiresConfirmation: Bool {
        switch self {
        case .exportData:
            return false
        case .deleteLocalData, .deleteCloudData:
            return true
        }
    }
}
```

- [ ] **Step 6: Run backend and macOS tests**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
cd ../macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/backend apps/macos/Bogi
git commit -m "feat: add privacy export and delete boundaries"
```

### Task 18: Add Privacy-Safe Product Events

**Files:**
- Create: `apps/backend/src/services/productEvents.ts`
- Create: `apps/backend/test/product-events.test.ts`

- [ ] **Step 1: Write event privacy test**

Create `apps/backend/test/product-events.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { ProductEventSchema } from "../src/services/productEvents";

describe("product events", () => {
  it("allows product event names without sensitive content", () => {
    expect(ProductEventSchema.parse({ name: "created_block", properties: { source: "command_bar" } })).toEqual({
      name: "created_block",
      properties: { source: "command_bar" }
    });
  });

  it("rejects sensitive content properties", () => {
    expect(() =>
      ProductEventSchema.parse({ name: "completed_reality_log", properties: { userText: "private log" } })
    ).toThrow();
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- product-events.test.ts
```

Expected: FAIL because product event schema does not exist.

- [ ] **Step 3: Implement event schema**

Create `apps/backend/src/services/productEvents.ts`:

```ts
import { z } from "zod";

const EventNameSchema = z.enum([
  "created_block",
  "completed_reality_log",
  "missed_reality_log",
  "started_lock_in",
  "ended_lock_in",
  "viewed_week_summary",
  "paid_lifetime"
]);

const SensitiveKeys = new Set(["userText", "transcript", "ocrText", "accessibilityText", "screenshot"]);

export const ProductEventSchema = z.object({
  name: EventNameSchema,
  properties: z.record(z.string(), z.string()).superRefine((properties, context) => {
    for (const key of Object.keys(properties)) {
      if (SensitiveKeys.has(key)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Sensitive analytics property is not allowed: ${key}`
        });
      }
    }
  })
});
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add privacy-safe product events"
```

### Task 19: Add Postgres, Drizzle, and pgvector Schema

**Files:**
- Modify: `apps/backend/package.json`
- Create: `apps/backend/src/db/schema.ts`
- Create: `apps/backend/src/db/migrations/0001_init.sql`
- Create: `apps/backend/test/db-schema.test.ts`

- [ ] **Step 1: Write schema test**

Create `apps/backend/test/db-schema.test.ts`:

```ts
import { getTableName } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { dailySummaries, embeddings, plannedBlocks, realityLogs, users } from "../src/db/schema";

describe("database schema", () => {
  it("defines core cloud data-bank tables", () => {
    expect(getTableName(users)).toBe("users");
    expect(getTableName(plannedBlocks)).toBe("planned_blocks");
    expect(getTableName(realityLogs)).toBe("reality_logs");
    expect(getTableName(dailySummaries)).toBe("daily_summaries");
    expect(getTableName(embeddings)).toBe("embeddings");
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- db-schema.test.ts
```

Expected: FAIL because `src/db/schema.ts` does not exist.

- [ ] **Step 3: Add Drizzle schema**

Modify `apps/backend/package.json` dev dependencies to include Drizzle Kit:

```json
{
  "devDependencies": {
    "@types/node": "^22.10.2",
    "drizzle-kit": "^0.27.1",
    "tsx": "^4.19.2",
    "typescript": "^5.7.2",
    "vitest": "^2.1.8"
  }
}
```

Create `apps/backend/src/db/schema.ts`:

```ts
import { index, pgTable, text, timestamp, uuid, vector } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: uuid("id").primaryKey(),
  email: text("email").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull()
});

export const plannedBlocks = pgTable("planned_blocks", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  title: text("title").notNull(),
  startAt: timestamp("start_at", { withTimezone: true }).notNull(),
  endAt: timestamp("end_at", { withTimezone: true }).notNull(),
  source: text("source").notNull(),
  externalEventId: text("external_event_id"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const realityLogs = pgTable("reality_logs", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  plannedBlockId: uuid("planned_block_id").references(() => plannedBlocks.id),
  userText: text("user_text").notNull(),
  generatedSummary: text("generated_summary"),
  startAt: timestamp("start_at", { withTimezone: true }).notNull(),
  endAt: timestamp("end_at", { withTimezone: true }).notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const dailySummaries = pgTable("daily_summaries", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id),
  day: text("day").notNull(),
  summary: text("summary").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull()
});

export const embeddings = pgTable(
  "embeddings",
  {
    id: uuid("id").primaryKey(),
    userId: uuid("user_id").notNull().references(() => users.id),
    sourceType: text("source_type").notNull(),
    sourceId: uuid("source_id").notNull(),
    embedding: vector("embedding", { dimensions: 1536 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull()
  },
  (table) => ({
    embeddingIndex: index("embeddings_vector_idx").using("hnsw", table.embedding.op("vector_cosine_ops"))
  })
);
```

Create `apps/backend/src/db/migrations/0001_init.sql`:

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE users (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  created_at timestamptz NOT NULL
);

CREATE TABLE planned_blocks (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  title text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  source text NOT NULL,
  external_event_id text,
  updated_at timestamptz NOT NULL
);

CREATE TABLE reality_logs (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  planned_block_id uuid REFERENCES planned_blocks(id),
  user_text text NOT NULL,
  generated_summary text,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE daily_summaries (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  day text NOT NULL,
  summary text NOT NULL,
  updated_at timestamptz NOT NULL
);

CREATE TABLE embeddings (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  source_type text NOT NULL,
  source_id uuid NOT NULL,
  embedding vector(1536) NOT NULL,
  created_at timestamptz NOT NULL
);

CREATE INDEX embeddings_vector_idx ON embeddings USING hnsw (embedding vector_cosine_ops);
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm install
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add cloud data-bank schema"
```

### Task 20: Add Google Calendar OAuth Boundary

**Files:**
- Create: `apps/backend/src/services/googleCalendarOAuth.ts`
- Create: `apps/backend/src/routes/googleCalendar.ts`
- Create: `apps/backend/test/google-calendar-oauth.test.ts`

- [ ] **Step 1: Write OAuth URL test**

Create `apps/backend/test/google-calendar-oauth.test.ts`:

```ts
import { describe, expect, it } from "vitest";
import { buildGoogleCalendarAuthUrl } from "../src/services/googleCalendarOAuth";

describe("Google Calendar OAuth", () => {
  it("builds an authorization URL with minimal calendar scope", () => {
    const url = buildGoogleCalendarAuthUrl({
      clientId: "client_1",
      redirectUri: "https://api.bogi.app/google/callback",
      state: "state_1"
    });

    expect(url.hostname).toBe("accounts.google.com");
    expect(url.searchParams.get("scope")).toBe("https://www.googleapis.com/auth/calendar.events");
    expect(url.searchParams.get("access_type")).toBe("offline");
  });
});
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/backend
npm test -- google-calendar-oauth.test.ts
```

Expected: FAIL because Google Calendar OAuth code does not exist.

- [ ] **Step 3: Implement OAuth boundary**

Create `apps/backend/src/services/googleCalendarOAuth.ts`:

```ts
type GoogleCalendarAuthInput = {
  clientId: string;
  redirectUri: string;
  state: string;
};

export function buildGoogleCalendarAuthUrl(input: GoogleCalendarAuthInput) {
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", input.clientId);
  url.searchParams.set("redirect_uri", input.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", "https://www.googleapis.com/auth/calendar.events");
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("state", input.state);
  return url;
}
```

Create `apps/backend/src/routes/googleCalendar.ts`:

```ts
import type { FastifyInstance } from "fastify";
import { buildGoogleCalendarAuthUrl } from "../services/googleCalendarOAuth";

export async function registerGoogleCalendarRoutes(server: FastifyInstance) {
  server.get("/google-calendar/auth-url", async (request) => {
    const query = request.query as { clientId: string; redirectUri: string; state: string };
    return {
      url: buildGoogleCalendarAuthUrl(query).toString()
    };
  });
}
```

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
cd apps/backend
npm test
npm run typecheck
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/backend
git commit -m "feat: add google calendar oauth boundary"
```

### Task 21: Add Sparkle Update Boundary

**Files:**
- Modify: `apps/macos/Bogi/Package.swift`
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Updates/UpdatePolicy.swift`
- Create: `apps/macos/Bogi/Tests/BogiAppTests/UpdatePolicyTests.swift`

- [ ] **Step 1: Write update policy test**

Create `apps/macos/Bogi/Tests/BogiAppTests/UpdatePolicyTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class UpdatePolicyTests: XCTestCase {
    func testBetaBuildCanCheckForUpdates() {
        XCTAssertTrue(UpdatePolicy(channel: .beta).canCheckForUpdates)
    }
}
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd apps/macos/Bogi
swift test --filter UpdatePolicyTests
```

Expected: FAIL because `UpdatePolicy` does not exist.

- [ ] **Step 3: Add Sparkle dependency and update policy**

Modify `apps/macos/Bogi/Package.swift` dependencies to include Sparkle:

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
```

Modify the `BogiApp` target dependencies to include:

```swift
.product(name: "Sparkle", package: "Sparkle")
```

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Updates/UpdatePolicy.swift`:

```swift
enum UpdateChannel: Equatable {
    case beta
    case stable
}

struct UpdatePolicy: Equatable {
    let channel: UpdateChannel

    var canCheckForUpdates: Bool {
        switch channel {
        case .beta, .stable:
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd apps/macos/Bogi
swift test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi
git commit -m "feat: add sparkle update boundary"
```

### Task 22: Add macOS Distribution Scripts

**Files:**
- Create: `scripts/macos/package-dmg.sh`
- Create: `scripts/macos/notarize.sh`
- Create: `docs/release/macos-distribution.md`

- [ ] **Step 1: Create release documentation**

Create `docs/release/macos-distribution.md`:

```md
# macOS Distribution

Bogi ships outside the Mac App Store for beta distribution.

Required release checks:

- Build a signed app archive.
- Package the app into a DMG.
- Submit the DMG for Apple notarization.
- Staple the notarization ticket.
- Verify Gatekeeper accepts the DMG on a clean macOS account.

Required secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- Developer ID Application certificate in the signing keychain.

Sparkle is added after the first notarized DMG flow works.
```

- [ ] **Step 2: Create DMG packaging script**

Create `scripts/macos/package-dmg.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: package-dmg.sh /path/to/Bogi.app}"
OUTPUT_PATH="${2:?Usage: package-dmg.sh /path/to/Bogi.app /path/to/Bogi.dmg}"

hdiutil create \
  -volname "Bogi" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"
```

- [ ] **Step 3: Create notarization script**

Create `scripts/macos/notarize.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?Usage: notarize.sh /path/to/Bogi.dmg}"

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "${APPLE_ID:?APPLE_ID is required}" \
  --team-id "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}" \
  --password "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}" \
  --wait

xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
```

- [ ] **Step 4: Make scripts executable and verify shell syntax**

Run:

```bash
chmod +x scripts/macos/package-dmg.sh scripts/macos/notarize.sh
bash -n scripts/macos/package-dmg.sh
bash -n scripts/macos/notarize.sh
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/macos docs/release/macos-distribution.md
git commit -m "chore: add macos distribution scripts"
```

## Final Product Acceptance

Run these checks before claiming the full product implementation plan is complete:

```bash
cd apps/macos/Bogi
swift test
cd ../../backend
npm test
npm run typecheck
```

Expected:

- Swift tests pass.
- Backend tests pass.
- TypeScript typecheck passes.
- Manual macOS verification covers menu bar launch, command bar display, calendar permission prompt, microphone permission prompt, accessibility permission detection, lock-in capture indicator, export action, and delete confirmation.
- Shell syntax checks pass for release scripts.

## Spec Coverage Review

Covered by this plan:

- Native Swift macOS app: Tracks 1-5.
- Menu bar, command bar, settings: Track 1.
- Local SQLite and GRDB: Track 1.
- EventKit calendar: Track 2.
- Voice and speech command boundary: Track 3.
- Accessibility context: Track 4.
- ScreenCaptureKit and Vision OCR fallback: Track 5.
- TypeScript Fastify backend: Track 6.
- Zod, Drizzle, Postgres, pgvector, and sync path: Tracks 6 and 8.
- OpenAI agent tool layer: Track 7.
- Stripe payment boundary: Track 8.
- Export/delete/privacy controls: Track 8.
- Google Calendar OAuth: Track 8.
- Distribution requirements: Track 8.
