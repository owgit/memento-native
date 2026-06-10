# Privacy, Integrity & Storage Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the eight parts of `docs/superpowers/specs/2026-06-10-weakness-fixes-design.md`: clipboard concealed-type filtering, storage protection (0700 + backup-exclusion setting), FK enforcement, quiet migrations, async storage metrics (settings-window slow-load fix), custom retention, max storage size with periodic maintenance — all TDD.

**Architecture:** All changes are in the `MementoCapture` package (the Timeline module is read-only and untouched). New types follow the existing stateless-enum-namespace convention. Heavy filesystem work always runs via `Task.detached(priority: .utility)`; UI state stays `@MainActor`. Swift 6 strict concurrency — no `@unchecked Sendable`, no `DispatchQueue`.

**Tech Stack:** Swift 6, SwiftPM, XCTest (`MementoCaptureTests` target exists), SQLite3 C API, AppKit/SwiftUI. Zero external dependencies (hard constraint).

**Working directory:** `/Users/uygarduzgun/Sites/memento-native` (paths below relative to repo root). Test command: `cd MementoCapture && swift test`.

**Commit style:** imperative, no prefix (matches `git log`: "Add hideable timeline toolbar"). Every commit ends with:
```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```

**Test file conventions** (match `MementoCapture/Tests/TimelineWindowControllerTests.swift`): XCTest, `@testable import MementoCapture`, `@MainActor` on classes touching main-actor types. Shared helper for temp dirs used by several test files below — define it ONCE in Task 2 (`TestSupport.swift`) and reuse.

---

### Task 0: Baseline

**Files:** none modified.

- [ ] **Step 0.1: Verify the existing suite is green**

Run: `cd /Users/uygarduzgun/Sites/memento-native/MementoCapture && swift test`
Expected: `Test Suite 'All tests' passed` with 2 tests (TimelineWindowControllerTests). If this fails, STOP and report — do not start on a red baseline.

---

### Task 1: ClipboardCapture — concealed/transient filtering

**Files:**
- Modify: `MementoCapture/Sources/ClipboardCapture.swift` (whole file, 42 lines)
- Create: `MementoCapture/Tests/ClipboardCaptureTests.swift`

Design note: the spec sketched per-call pasteboard injection; constructor injection is used instead so `lastChangeCount` always tracks one pasteboard. Same testability intent, safer semantics. The singleton `shared` is unchanged.

- [ ] **Step 1.1: Write the failing tests**

Create `MementoCapture/Tests/ClipboardCaptureTests.swift`:

```swift
import AppKit
import XCTest
@testable import MementoCapture

@MainActor
final class ClipboardCaptureTests: XCTestCase {
    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.memento.\(UUID().uuidString)"))
    }

    private func makeCapture(_ pasteboard: NSPasteboard) -> ClipboardCapture {
        let capture = ClipboardCapture(pasteboard: pasteboard)
        capture.isEnabled = true
        return capture
    }

    func testCapturesPlainTextWhenEnabled() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("hello world", forType: .string)

        XCTAssertEqual(capture.getNewClipboardContent(), "hello world")
    }

    func testReturnsNilWhenDisabled() {
        let pasteboard = makePasteboard()
        let capture = ClipboardCapture(pasteboard: pasteboard)
        capture.isEnabled = false

        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        XCTAssertNil(capture.getNewClipboardContent())
    }

    func testUnchangedPasteboardReturnsNilOnSecondCall() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("once", forType: .string)

        XCTAssertEqual(capture.getNewClipboardContent(), "once")
        XCTAssertNil(capture.getNewClipboardContent())
    }

    func testSkipsConcealedContent() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
            owner: nil
        )
        pasteboard.setString("hunter2", forType: .string)

        XCTAssertNil(capture.getNewClipboardContent())
    }

    func testSkipsTransientContent() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")],
            owner: nil
        )
        pasteboard.setString("temp", forType: .string)

        XCTAssertNil(capture.getNewClipboardContent())
    }

    func testSkipsAutoGeneratedContent() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")],
            owner: nil
        )
        pasteboard.setString("generated", forType: .string)

        XCTAssertNil(capture.getNewClipboardContent())
    }

    func testConcealedContentDoesNotBlockNextPlainCopy() {
        let pasteboard = makePasteboard()
        let capture = makeCapture(pasteboard)

        pasteboard.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
            owner: nil
        )
        pasteboard.setString("secret", forType: .string)
        XCTAssertNil(capture.getNewClipboardContent())

        pasteboard.clearContents()
        pasteboard.setString("normal again", forType: .string)
        XCTAssertEqual(capture.getNewClipboardContent(), "normal again")
    }
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter ClipboardCaptureTests`
Expected: COMPILE ERROR — `ClipboardCapture` has `private init()`, no `init(pasteboard:)`. This is the expected failure mode.

- [ ] **Step 1.3: Implement**

Replace the full contents of `MementoCapture/Sources/ClipboardCapture.swift` with:

```swift
import Foundation
import AppKit

/// Captures clipboard content (can be disabled in settings)
@MainActor
final class ClipboardCapture {

    static let shared = ClipboardCapture()

    /// Marker types from the nspasteboard.org de facto standard. Password
    /// managers set ConcealedType on copied secrets; transient/auto-generated
    /// content is never worth indexing.
    private static let sensitiveMarkerTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    ]

    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int

    /// Enable/disable clipboard capture (controlled by Settings)
    var isEnabled: Bool = false

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Get clipboard content if it changed since last check
    /// Returns nil if disabled, unchanged, or marked concealed/transient
    func getNewClipboardContent() -> String? {
        guard isEnabled else { return nil }

        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return nil }

        lastChangeCount = currentCount

        if let types = pasteboard.types,
           types.contains(where: { Self.sensitiveMarkerTypes.contains($0) }) {
            return nil
        }

        // Only capture text content
        guard let content = pasteboard.string(forType: .string) else { return nil }

        // Skip if too long (probably not useful text)
        guard content.count < 10000 else { return nil }

        // Skip if it looks like a file path or binary data
        if content.hasPrefix("/") && content.contains(".") && !content.contains(" ") {
            return nil
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 1.4: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter ClipboardCaptureTests`
Expected: 7 tests PASS.

- [ ] **Step 1.5: Commit**

```bash
git add MementoCapture/Sources/ClipboardCapture.swift MementoCapture/Tests/ClipboardCaptureTests.swift
git commit -m "Never capture concealed or transient clipboard content

Password managers mark copied secrets with org.nspasteboard.ConcealedType;
those never reach the database now. Pasteboard is constructor-injected for
testability.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Quiet schema migrations

**Files:**
- Modify: `MementoCapture/Sources/Database.swift:56-61` and `:96-97` (blind `ALTER TABLE` calls), plus new private helpers
- Create: `MementoCapture/Tests/TestSupport.swift`
- Create: `MementoCapture/Tests/DatabaseMigrationTests.swift`

- [ ] **Step 2.1: Create the shared test helper**

Create `MementoCapture/Tests/TestSupport.swift`:

```swift
import Foundation
import SQLite3
import XCTest

enum TestSupport {
    /// Creates a unique temp directory; caller cleans up via defer if desired.
    static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("memento-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Column names for a table, via an independent connection.
    static func columnNames(table: String, dbPath: String) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var names: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 1) {
                names.append(String(cString: cString))
            }
        }
        return names
    }

    /// Scalar integer query (e.g. COUNT(*)), via an independent connection.
    static func scalarInt(_ sql: String, dbPath: String) -> Int {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return -1 }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Executes raw SQL on a fresh connection (for seeding legacy schemas).
    static func executeRaw(_ sql: String, dbPath: String) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            XCTFail("could not open \(dbPath)")
            return
        }
        defer { sqlite3_close(db) }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            XCTFail("raw SQL failed: \(sql)")
        }
    }
}
```

- [ ] **Step 2.2: Write the failing tests**

Create `MementoCapture/Tests/DatabaseMigrationTests.swift`:

```swift
import Foundation
import SQLite3
import XCTest
@testable import MementoCapture

final class DatabaseMigrationTests: XCTestCase {
    func testLegacySchemaGainsNewColumnsOnInit() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        TestSupport.executeRaw(
            "CREATE TABLE FRAME (id INTEGER PRIMARY KEY, window_title TEXT NOT NULL, time TEXT NOT NULL)",
            dbPath: dbPath
        )

        let database = Database(path: dbPath)
        database.close()

        let frameColumns = TestSupport.columnNames(table: "FRAME", dbPath: dbPath)
        for expected in ["url", "tab_title", "app_bundle_id", "clipboard", "app_category"] {
            XCTAssertTrue(frameColumns.contains(expected), "missing FRAME column \(expected)")
        }
    }

    func testRepeatedInitIsIdempotent() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        Database(path: dbPath).close()
        Database(path: dbPath).close()

        let frameColumns = TestSupport.columnNames(table: "FRAME", dbPath: dbPath)
        XCTAssertEqual(frameColumns.filter { $0 == "url" }.count, 1)
        let embeddingColumns = TestSupport.columnNames(table: "EMBEDDING", dbPath: dbPath)
        for expected in ["language", "revision"] {
            XCTAssertTrue(embeddingColumns.contains(expected), "missing EMBEDDING column \(expected)")
        }
    }

    func testColumnExistsHelper() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        let database = Database(path: dbPath)
        defer { database.close() }

        XCTAssertTrue(database.columnExists(table: "FRAME", column: "url"))
        XCTAssertFalse(database.columnExists(table: "FRAME", column: "no_such_column"))
    }
}
```

- [ ] **Step 2.3: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter DatabaseMigrationTests`
Expected: COMPILE ERROR — `columnExists` does not exist. (The first two tests would pass against current code since blind ALTERs do add columns — the helper test is the one driving the change.)

- [ ] **Step 2.4: Implement**

In `MementoCapture/Sources/Database.swift`, add below `contentFTSSchemaVersionValue()`:

```swift
    /// PRAGMA cannot take bound parameters; `table` is always an internal
    /// constant within this file — never external input.
    func columnExists(table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePointer = sqlite3_column_text(stmt, 1),
               String(cString: namePointer) == column {
                return true
            }
        }
        return false
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) {
        guard !columnExists(table: table, column: column) else { return }
        execute("ALTER TABLE \(table) ADD COLUMN \(definition)")
    }
```

Replace the five blind FRAME ALTERs (lines 56–61):

```swift
        // Add new columns if they don't exist (migration)
        addColumnIfMissing(table: "FRAME", column: "url", definition: "url TEXT")
        addColumnIfMissing(table: "FRAME", column: "tab_title", definition: "tab_title TEXT")
        addColumnIfMissing(table: "FRAME", column: "app_bundle_id", definition: "app_bundle_id TEXT")
        addColumnIfMissing(table: "FRAME", column: "clipboard", definition: "clipboard TEXT")
        addColumnIfMissing(table: "FRAME", column: "app_category", definition: "app_category TEXT")
```

Replace the two blind EMBEDDING ALTERs (lines 96–97):

```swift
        addColumnIfMissing(table: "EMBEDDING", column: "language", definition: "language TEXT")
        addColumnIfMissing(table: "EMBEDDING", column: "revision", definition: "revision INTEGER DEFAULT 0")
```

- [ ] **Step 2.5: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter DatabaseMigrationTests`
Expected: 3 tests PASS.

- [ ] **Step 2.6: Commit**

```bash
git add MementoCapture/Sources/Database.swift MementoCapture/Tests/TestSupport.swift MementoCapture/Tests/DatabaseMigrationTests.swift
git commit -m "Guard schema migrations with column checks

ALTER TABLE only runs when the column is missing — no more SQL error
log lines on every launch.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Foreign key enforcement + busy timeout

**Files:**
- Modify: `MementoCapture/Sources/Database.swift:29-40` (`openDatabase()`)
- Modify: `MementoCapture/Sources/StorageCleaner.swift:28-31` (after `sqlite3_open` in `cleanup`)
- Create: `MementoCapture/Tests/DatabaseForeignKeyTests.swift`
- Create: `MementoCapture/Tests/StorageCleanerTests.swift`

Note: `LegacyTimelineMigration` was inspected — it never opens a database connection (filesystem only), so it needs no pragma. The Timeline module reads only and is untouched.

- [ ] **Step 3.1: Write the failing FK tests**

Create `MementoCapture/Tests/DatabaseForeignKeyTests.swift`:

```swift
import Foundation
import XCTest
@testable import MementoCapture

final class DatabaseForeignKeyTests: XCTestCase {
    func testReplacingFrameWithOcrChildrenFailsLoudly() throws {
        let dir = try TestSupport.makeTempDirectory()
        let database = Database(path: dir.appendingPathComponent("memento.db").path)
        defer { database.close() }

        let block = TextBlock(text: "hello", x: 1, y: 2, width: 3, height: 4)
        XCTAssertTrue(database.insertFrame(
            frameId: 1, windowTitle: "App", time: "2026-06-10T00:00:00Z", textBlocks: [block]
        ))

        // REPLACE would delete the old FRAME row and orphan its CONTENT child.
        // With foreign_keys=ON this must fail (loudly) instead.
        XCTAssertFalse(database.insertFrame(
            frameId: 1, windowTitle: "App", time: "2026-06-10T00:00:01Z", textBlocks: []
        ))
    }

    func testReplacingChildlessFrameSucceeds() throws {
        let dir = try TestSupport.makeTempDirectory()
        let database = Database(path: dir.appendingPathComponent("memento.db").path)
        defer { database.close() }

        XCTAssertTrue(database.insertFrame(
            frameId: 2, windowTitle: "App", time: "2026-06-10T00:00:00Z", textBlocks: []
        ))
        XCTAssertTrue(database.insertFrame(
            frameId: 2, windowTitle: "App", time: "2026-06-10T00:00:01Z", textBlocks: []
        ))
    }
}
```

- [ ] **Step 3.2: Write the StorageCleaner cutoff test**

Create `MementoCapture/Tests/StorageCleanerTests.swift`:

```swift
import Foundation
import XCTest
@testable import MementoCapture

final class StorageCleanerTests: XCTestCase {
    func testCutoffDeletesOnlyWholeOldVideos() throws {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        let database = Database(path: dbPath)
        for id in 1...10 {
            let time = id <= 5 ? "2020-01-01T00:00:0\(id)Z" : "2030-01-01T00:00:0\(id)Z"
            XCTAssertTrue(database.insertFrame(
                frameId: id, windowTitle: "App", time: time, textBlocks: []
            ))
        }
        database.close()

        try Data(count: 1_000).write(to: dir.appendingPathComponent("1.mp4"))
        try Data(count: 1_000).write(to: dir.appendingPathComponent("6.mp4"))

        let result = StorageCleaner.cleanup(
            dbPath: dbPath,
            cachePath: dir,
            cutoffISO8601: "2025-01-01T00:00:00Z",
            deleteAll: false,
            framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedFrames, 5)
        XCTAssertEqual(result.deletedVideos, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6.mp4").path))
        XCTAssertEqual(TestSupport.scalarInt("SELECT COUNT(*) FROM FRAME", dbPath: dbPath), 5)
    }
}
```

- [ ] **Step 3.3: Run tests to verify the FK test fails**

Run: `cd MementoCapture && swift test --filter DatabaseForeignKeyTests`
Expected: `testReplacingFrameWithOcrChildrenFailsLoudly` FAILS (the REPLACE currently succeeds because FK is off). `testReplacingChildlessFrameSucceeds` passes.

Run: `cd MementoCapture && swift test --filter StorageCleanerTests`
Expected: PASS (locks in current behavior before the pragma change).

- [ ] **Step 3.4: Implement**

In `MementoCapture/Sources/Database.swift` `openDatabase()`, after the WAL pragmas (line 37):

```swift
        // Enable WAL mode for better concurrency
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        // Enforce declared FOREIGN KEYs (off by default in SQLite; per connection)
        execute("PRAGMA foreign_keys=ON")
        // Maintenance may write concurrently; wait briefly instead of failing with SQLITE_BUSY
        sqlite3_busy_timeout(db, 5000)
```

In `MementoCapture/Sources/StorageCleaner.swift` `cleanup(...)`, directly after `defer { sqlite3_close(db) }` (line 31):

```swift
        sqlite3_busy_timeout(db, 5000)
        execute(db: db, sql: "PRAGMA foreign_keys=ON")
```

- [ ] **Step 3.5: Run the full suite**

Run: `cd MementoCapture && swift test`
Expected: ALL tests pass — including Task 2's migration tests and the cleaner test (delete order is already child-first, so FK enforcement must not break it). If `testCutoffDeletesOnlyWholeOldVideos` now fails, the cleaner's delete order has an FK problem — STOP and investigate, do not weaken the pragma.

- [ ] **Step 3.6: Commit**

```bash
git add MementoCapture/Sources/Database.swift MementoCapture/Sources/StorageCleaner.swift MementoCapture/Tests/DatabaseForeignKeyTests.swift MementoCapture/Tests/StorageCleanerTests.swift
git commit -m "Enforce foreign keys and add busy timeout on write connections

SQLite ships with foreign_keys OFF; the declared constraints were
decorative. A conflicting frame REPLACE now fails loudly instead of
silently orphaning OCR rows.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: StorageProtection + backup-exclusion setting

**Files:**
- Create: `MementoCapture/Sources/StorageProtection.swift`
- Create: `MementoCapture/Tests/StorageProtectionTests.swift`
- Modify: `MementoCapture/Sources/Settings.swift` (new key + property + init line)
- Modify: `MementoCapture/Sources/CaptureService.swift:529-552` (`prepareCaptureResourcesIfNeeded`) and `:104-121` (`switchStoragePath` success path)
- Modify: `MementoCapture/Sources/SettingsWindow.swift` (storage section + `L` extension)
- Modify: `docs/SETTINGS.md` (Storage section)

- [ ] **Step 4.1: Write the failing tests**

Create `MementoCapture/Tests/StorageProtectionTests.swift`:

```swift
import Foundation
import XCTest
@testable import MementoCapture

final class StorageProtectionTests: XCTestCase {
    func testAppliesOwnerOnlyPermissions() throws {
        let dir = try TestSupport.makeTempDirectory()

        StorageProtection.applyDirectoryPermissions(to: dir)

        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        let permissions = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o700)
    }

    func testBackupExclusionRoundTrips() throws {
        let dir = try TestSupport.makeTempDirectory()

        StorageProtection.setExcludedFromBackup(true, on: dir)
        var values = try URL(fileURLWithPath: dir.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)

        StorageProtection.setExcludedFromBackup(false, on: dir)
        values = try URL(fileURLWithPath: dir.path)
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup ?? false, false)
    }
}
```

- [ ] **Step 4.2: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter StorageProtectionTests`
Expected: COMPILE ERROR — `StorageProtection` does not exist.

- [ ] **Step 4.3: Implement StorageProtection**

Create `MementoCapture/Sources/StorageProtection.swift`:

```swift
import Foundation

/// Hardens the storage directory: restrictive permissions and optional
/// Time Machine backup exclusion. All functions log-and-continue on failure
/// (e.g. exFAT volumes without POSIX permission support).
enum StorageProtection {
    /// Restrict the storage directory to the current user (rwx------).
    static func applyDirectoryPermissions(to url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: url.path
            )
        } catch {
            AppLog.warning("⚠️ Could not restrict storage permissions: \(error.localizedDescription)")
        }
    }

    /// Include or exclude the storage directory from Time Machine backups.
    static func setExcludedFromBackup(_ excluded: Bool, on url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            AppLog.warning("⚠️ Could not update backup exclusion: \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4.4: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter StorageProtectionTests`
Expected: 2 tests PASS.

- [ ] **Step 4.5: Wire up Settings**

In `MementoCapture/Sources/Settings.swift`:

Add to the `Key` enum (after `pauseDuringPrivateBrowsing`):

```swift
        case excludeFromBackup = "excludeFromBackup"
```

Add the published property (after `pauseDuringPrivateBrowsing`'s property):

```swift
    @Published var excludeFromBackup: Bool {
        didSet {
            defaults.set(excludeFromBackup, forKey: Key.excludeFromBackup.rawValue)
            StorageProtection.setExcludedFromBackup(excludeFromBackup, on: storageURL)
        }
    }
```

Add to `init()` (with the other loads, BEFORE the `storagePath` assignment — note: `didSet` does not fire during init, so this is just the load):

```swift
        self.excludeFromBackup = defaults.object(forKey: Key.excludeFromBackup.rawValue) as? Bool ?? true
```

- [ ] **Step 4.6: Wire up CaptureService**

In `prepareCaptureResourcesIfNeeded()` after `try? FileManager.default.createDirectory(...)` (line 533):

```swift
        StorageProtection.applyDirectoryPermissions(to: cachePath)
        StorageProtection.setExcludedFromBackup(Settings.shared.excludeFromBackup, on: cachePath)
```

In `switchStoragePath(to:)` after `cachePath = normalizedPath` (line 110):

```swift
            StorageProtection.applyDirectoryPermissions(to: cachePath)
            StorageProtection.setExcludedFromBackup(Settings.shared.excludeFromBackup, on: cachePath)
```

- [ ] **Step 4.7: Add the toggle to SettingsWindow**

In `MementoCapture/Sources/SettingsWindow.swift`, in the Storage `Section`, after the storage-location `VStack` (after line 183, before the `folderSize()` block):

```swift
                    Toggle(L.excludeFromBackup, isOn: $settings.excludeFromBackup)
                    Text(L.excludeFromBackupHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
```

Add to the `private extension L` at the bottom of the file:

```swift
    static var excludeFromBackup: String {
        isSwedish ? "Exkludera från Time Machine-backup" : "Exclude from Time Machine backups"
    }
    static var excludeFromBackupHint: String {
        isSwedish
            ? "Håller skärmhistoriken borta från backupdiskar. Stäng av om du vill kunna återställa historiken från backup."
            : "Keeps your screen history off backup disks. Turn off if you want history restorable from backups."
    }
```

- [ ] **Step 4.8: Document in docs/SETTINGS.md**

In the `## Storage Settings / Lagring` section, after the "Storage location" entry, add:

```markdown
### Exclude from Time Machine backups

Default: `On`

**EN:** Keeps the screen history out of Time Machine backups. Turn off if you want history restorable from backups (at the cost of copying sensitive history to backup disks).

**SV:** Håller skärmhistoriken utanför Time Machine-backuper. Stäng av om du vill kunna återställa historiken från backup (till priset av att känslig historik kopieras till backupdiskar).
```

- [ ] **Step 4.9: Build + full suite**

Run: `cd MementoCapture && swift build && swift test`
Expected: builds clean, all tests pass.

- [ ] **Step 4.10: Commit**

```bash
git add MementoCapture/Sources/StorageProtection.swift MementoCapture/Tests/StorageProtectionTests.swift MementoCapture/Sources/Settings.swift MementoCapture/Sources/CaptureService.swift MementoCapture/Sources/SettingsWindow.swift docs/SETTINGS.md
git commit -m "Harden storage directory permissions and add backup exclusion setting

Storage directory is now chmod 0700 and excluded from Time Machine by
default (new excludeFromBackup setting, off-switchable in Settings).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Async storage metrics — settings window fix

**Files:**
- Modify: `MementoCapture/Sources/AppRuntimeInfo.swift:67-85` (replace `StorageMetrics`)
- Modify: `MementoCapture/Sources/SettingsWindow.swift` (`folderSize()` → async state, lines 185-192 and 338-347)
- Modify: `MementoCapture/Sources/MenuBarManager.swift:827-880` (`showStats()`)
- Create: `MementoCapture/Tests/StorageMetricsTests.swift`

- [ ] **Step 5.1: Write the failing tests**

Create `MementoCapture/Tests/StorageMetricsTests.swift`:

```swift
import Foundation
import XCTest
@testable import MementoCapture

final class StorageMetricsTests: XCTestCase {
    func testWalkSumsFileSizesIncludingSubdirectories() throws {
        let dir = try TestSupport.makeTempDirectory()
        try Data(count: 100).write(to: dir.appendingPathComponent("a.bin"))
        try Data(count: 250).write(to: dir.appendingPathComponent("b.bin"))
        let sub = dir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data(count: 50).write(to: sub.appendingPathComponent("c.bin"))

        XCTAssertEqual(StorageMetrics.walkTotalBytes(in: dir), 400)
    }

    @MainActor
    func testTotalBytesCachesWithinTTLAndBypassRefreshes() async throws {
        let dir = try TestSupport.makeTempDirectory()
        try Data(count: 100).write(to: dir.appendingPathComponent("a.bin"))
        StorageMetrics.invalidateCache()

        let first = await StorageMetrics.totalBytes(in: dir)
        XCTAssertEqual(first, 100)

        try Data(count: 100).write(to: dir.appendingPathComponent("b.bin"))

        let cached = await StorageMetrics.totalBytes(in: dir)
        XCTAssertEqual(cached, 100, "second call within TTL must return the cached value")

        let fresh = await StorageMetrics.totalBytes(in: dir, bypassCache: true)
        XCTAssertEqual(fresh, 200)
    }
}
```

- [ ] **Step 5.2: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter StorageMetricsTests`
Expected: COMPILE ERROR — `walkTotalBytes`, `invalidateCache`, async `totalBytes` do not exist.

- [ ] **Step 5.3: Implement the new StorageMetrics**

In `MementoCapture/Sources/AppRuntimeInfo.swift`, replace the whole `enum StorageMetrics { ... }` (lines 67-85) with:

```swift
enum StorageMetrics {
    private struct CacheEntry {
        let bytes: Int64
        let computedAt: Date
    }

    @MainActor private static var cache: [String: CacheEntry] = [:]
    private static let cacheTTL: TimeInterval = 5 * 60

    /// Cached, off-main-thread directory size. Safe to call from UI code.
    @MainActor
    static func totalBytes(in directoryURL: URL, bypassCache: Bool = false) async -> Int64? {
        let key = directoryURL.standardizedFileURL.path
        if !bypassCache,
           let entry = cache[key],
           Date().timeIntervalSince(entry.computedAt) < cacheTTL {
            return entry.bytes
        }

        let measured = await Task.detached(priority: .utility) {
            walkTotalBytes(in: directoryURL)
        }.value

        if let measured {
            cache[key] = CacheEntry(bytes: measured, computedAt: Date())
        }
        return measured
    }

    @MainActor
    static func invalidateCache() {
        cache.removeAll()
    }

    /// Synchronous full directory walk. NEVER call on the main thread for real
    /// storage directories — 100k+ files take 10+ seconds (measured).
    nonisolated static func walkTotalBytes(in directoryURL: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        return totalSize
    }
}
```

- [ ] **Step 5.4: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter StorageMetricsTests`
Expected: 2 tests PASS. NOTE: the build will FAIL right now if the old sync `totalBytes(in:)` call sites still exist — fix them in the next two steps before running if so (compiler will point at `SettingsWindow.swift:340` and `MenuBarManager.swift:854`).

- [ ] **Step 5.5: Fix SettingsView**

In `MementoCapture/Sources/SettingsWindow.swift`:

Add state (after `@State private var hasLegacyTimelineApp ...`, line 41):

```swift
    @State private var folderSizeText: String?
```

Replace the `folderSize()` usage block (lines 185-192):

```swift
                    HStack {
                        Text(L.currentUsage)
                        Spacer()
                        Text(folderSizeText ?? L.computingSize)
                            .foregroundColor(.secondary)
                    }
```

Replace `.onAppear(perform: refreshLegacyTimelineStatus)` (line 281) with:

```swift
        .onAppear(perform: refreshLegacyTimelineStatus)
        .task { await refreshFolderSize() }
```

Delete the entire `private func folderSize() -> String?` (lines 338-347) and add instead:

```swift
    private func refreshFolderSize(bypassCache: Bool = false) async {
        let url = URL(fileURLWithPath: settings.storagePath)
        guard let totalBytes = await StorageMetrics.totalBytes(in: url, bypassCache: bypassCache) else {
            folderSizeText = nil
            return
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        folderSizeText = formatter.string(fromByteCount: totalBytes)
    }
```

In `selectFolder()`'s success path, after the success alert's `alert.runModal()` (line 325), add:

```swift
                    await refreshFolderSize(bypassCache: true)
```

Add to the `private extension L`:

```swift
    static var computingSize: String { isSwedish ? "Beräknar…" : "Computing…" }
```

- [ ] **Step 5.6: Fix MenuBarManager.showStats**

In `MementoCapture/Sources/MenuBarManager.swift`, the current `showStats()` (line 827) runs DB counts, the directory walk, and `NSAlert` synchronously. Restructure to:

```swift
    @objc private func showStats() {
        let cachePath = Settings.shared.storageURL
        let dbPath = cachePath.appendingPathComponent("memento.db").path
        let displayPath = (cachePath.path as NSString).abbreviatingWithTildeInPath

        Task { @MainActor in
            let counts = await Task.detached(priority: .userInitiated) {
                Self.fetchFrameAndEmbeddingCounts(dbPath: dbPath)
            }.value

            var diskUsage = "?"
            if let totalSize = await StorageMetrics.totalBytes(in: cachePath) {
                if totalSize > 1_000_000_000 {
                    diskUsage = String(format: "%.1f GB", Double(totalSize) / 1_000_000_000)
                } else {
                    diskUsage = String(format: "%.0f MB", Double(totalSize) / 1_000_000)
                }
            }

            presentStatsAlert(
                frameCount: counts.frames,
                embeddingCount: counts.embeddings,
                diskUsage: diskUsage,
                displayPath: displayPath,
                cachePath: cachePath
            )
        }
    }

    nonisolated private static func fetchFrameAndEmbeddingCounts(dbPath: String) -> (frames: Int, embeddings: Int) {
        var frameCount = 0
        var embeddingCount = 0

        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM FRAME", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    frameCount = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM EMBEDDING", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    embeddingCount = Int(sqlite3_column_int(stmt, 0))
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }

        return (frameCount, embeddingCount)
    }
```

Then create `presentStatsAlert(frameCount:embeddingCount:diskUsage:displayPath:cachePath:)` by MOVING the existing alert construction and response handling (from `let alert = NSAlert()` at line 862 through the end of the original function, including the `openFolder` button response handling) into it UNCHANGED — only the local variable names now come from the parameters. Read the original tail of the function before cutting; do not re-type it from memory.

- [ ] **Step 5.7: Build + full suite**

Run: `cd MementoCapture && swift build && swift test`
Expected: builds clean (no remaining callers of the old sync API), all tests pass.

- [ ] **Step 5.8: Commit**

```bash
git add MementoCapture/Sources/AppRuntimeInfo.swift MementoCapture/Sources/SettingsWindow.swift MementoCapture/Sources/MenuBarManager.swift MementoCapture/Tests/StorageMetricsTests.swift
git commit -m "Compute storage size off the main thread

The settings window blocked 10+ seconds walking 145k files inside
SwiftUI body. Size is now computed via Task.detached with a 5-minute
cache; the window opens instantly with a computing placeholder. The
statistics alert gets the same treatment.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Custom retention ("keep data")

**Files:**
- Create: `MementoCapture/Sources/RetentionOptions.swift`
- Create: `MementoCapture/Tests/RetentionOptionsTests.swift`
- Modify: `MementoCapture/Sources/SettingsWindow.swift` (retention picker block, lines 141-153, + `L` extension)

- [ ] **Step 6.1: Write the failing tests**

Create `MementoCapture/Tests/RetentionOptionsTests.swift`:

```swift
import XCTest
@testable import MementoCapture

final class RetentionOptionsTests: XCTestCase {
    func testPresetRecognition() {
        XCTAssertTrue(RetentionOptions.isPreset(1))
        XCTAssertTrue(RetentionOptions.isPreset(7))
        XCTAssertTrue(RetentionOptions.isPreset(30))
        XCTAssertTrue(RetentionOptions.isPreset(RetentionOptions.forever))
        XCTAssertFalse(RetentionOptions.isPreset(12))
        XCTAssertFalse(RetentionOptions.isPreset(365))
    }

    func testClampingCustomDays() {
        XCTAssertEqual(RetentionOptions.clampedCustom(0), 1)
        XCTAssertEqual(RetentionOptions.clampedCustom(-5), 1)
        XCTAssertEqual(RetentionOptions.clampedCustom(12), 12)
        XCTAssertEqual(RetentionOptions.clampedCustom(365), 365)
        XCTAssertEqual(RetentionOptions.clampedCustom(9000), 365)
    }
}
```

- [ ] **Step 6.2: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter RetentionOptionsTests`
Expected: COMPILE ERROR — `RetentionOptions` does not exist.

- [ ] **Step 6.3: Implement the helper**

Create `MementoCapture/Sources/RetentionOptions.swift`:

```swift
import Foundation

/// Maps between the retention presets and the custom-days field in Settings.
/// `Settings.retentionDays` stays a plain Int; 9999 is the legacy ∞ sentinel.
enum RetentionOptions {
    static let presets: [Int] = [1, 3, 7, 14, 30]
    static let forever = 9999
    static let customRange = 1...365

    /// The sentinel used by the picker UI for the "Custom…" row.
    static let customPickerTag = -1

    static func isPreset(_ days: Int) -> Bool {
        presets.contains(days) || days == forever
    }

    static func clampedCustom(_ days: Int) -> Int {
        min(max(days, customRange.lowerBound), customRange.upperBound)
    }
}
```

- [ ] **Step 6.4: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter RetentionOptionsTests`
Expected: 2 tests PASS.

- [ ] **Step 6.5: Wire the UI**

In `MementoCapture/Sources/SettingsWindow.swift`:

Add state (next to the other `@State` vars):

```swift
    @State private var isCustomRetention = false
    @State private var customRetentionDays = 7
```

Add the derived binding + commit helper (near `refreshLegacyTimelineStatus()`):

```swift
    private var retentionSelection: Binding<Int> {
        Binding(
            get: {
                isCustomRetention ? RetentionOptions.customPickerTag : settings.retentionDays
            },
            set: { newValue in
                if newValue == RetentionOptions.customPickerTag {
                    isCustomRetention = true
                    if !RetentionOptions.isPreset(settings.retentionDays) {
                        customRetentionDays = settings.retentionDays
                    }
                    commitCustomRetention()
                } else {
                    isCustomRetention = false
                    settings.retentionDays = newValue
                }
            }
        )
    }

    private func commitCustomRetention() {
        let clamped = RetentionOptions.clampedCustom(customRetentionDays)
        customRetentionDays = clamped
        settings.retentionDays = clamped
    }
```

Replace the retention picker block (lines 141-153) with:

```swift
                    HStack {
                        Text(L.retentionDays)
                        Spacer()
                        Picker("", selection: retentionSelection) {
                            Text("1 " + L.day).tag(1)
                            Text("3 " + L.days).tag(3)
                            Text("7 " + L.days).tag(7)
                            Text("14 " + L.days).tag(14)
                            Text("30 " + L.days).tag(30)
                            Text("∞").tag(RetentionOptions.forever)
                            Text(L.customRetention).tag(RetentionOptions.customPickerTag)
                        }
                        .frame(width: 140)
                    }

                    if isCustomRetention {
                        HStack {
                            Text(L.customRetentionDaysLabel)
                            Spacer()
                            TextField("", value: $customRetentionDays, format: .number)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                                .onSubmit(commitCustomRetention)
                            Stepper("", value: $customRetentionDays, in: RetentionOptions.customRange)
                                .labelsHidden()
                                .onChange(of: customRetentionDays) { _, _ in
                                    commitCustomRetention()
                                }
                            Text(L.days)
                        }
                    }
```

In `body`, replace the previous `.onAppear(perform: refreshLegacyTimelineStatus)` (keep the `.task { await refreshFolderSize() }` from Task 5):

```swift
        .onAppear {
            refreshLegacyTimelineStatus()
            if !RetentionOptions.isPreset(settings.retentionDays) {
                isCustomRetention = true
                customRetentionDays = settings.retentionDays
            }
        }
        .task { await refreshFolderSize() }
```

Add to the `private extension L`:

```swift
    static var customRetention: String { isSwedish ? "Anpassad…" : "Custom…" }
    static var customRetentionDaysLabel: String { isSwedish ? "Antal dagar" : "Number of days" }
```

- [ ] **Step 6.6: Update docs/SETTINGS.md**

Replace the "Keep data (retention)" entry's `Options:` line with:

```markdown
Options: `1, 3, 7, 14, 30 days, ∞, custom (1-365 days)`
```

- [ ] **Step 6.7: Build + full suite**

Run: `cd MementoCapture && swift build && swift test`
Expected: builds clean, all tests pass.

- [ ] **Step 6.8: Commit**

```bash
git add MementoCapture/Sources/RetentionOptions.swift MementoCapture/Tests/RetentionOptionsTests.swift MementoCapture/Sources/SettingsWindow.swift docs/SETTINGS.md
git commit -m "Add custom retention period to keep-data setting

Preset picker gains a Custom… entry with a 1-365 day field. The
retentionDays storage format is unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Max storage size + periodic maintenance

**Files:**
- Modify: `MementoCapture/Sources/StorageCleaner.swift` (new `cleanupToFit`)
- Modify: `MementoCapture/Sources/Settings.swift` (new `maxStorageGB`)
- Modify: `MementoCapture/Sources/CaptureService.swift` (replace `applyRetentionPolicyIfNeeded` with maintenance runner + timer; `start()`/`stop()`)
- Modify: `MementoCapture/Sources/SettingsWindow.swift` (max-size field + `L` strings)
- Modify: `docs/SETTINGS.md`
- Create: `MementoCapture/Tests/StorageCleanerFitTests.swift`

- [ ] **Step 7.1: Write the failing tests**

Create `MementoCapture/Tests/StorageCleanerFitTests.swift`:

```swift
import Foundation
import XCTest
@testable import MementoCapture

final class StorageCleanerFitTests: XCTestCase {
    /// Seeds 10 frames (1...10) and two 1 MB videos: 1.mp4 (frames 1-5) and
    /// 6.mp4 (frames 6-10). Returns (dir, dbPath).
    private func seedStorage() throws -> (URL, String) {
        let dir = try TestSupport.makeTempDirectory()
        let dbPath = dir.appendingPathComponent("memento.db").path

        let database = Database(path: dbPath)
        for id in 1...10 {
            XCTAssertTrue(database.insertFrame(
                frameId: id, windowTitle: "App", time: "2026-06-10T00:00:0\(id)Z", textBlocks: []
            ))
        }
        database.close()

        try Data(count: 1_000_000).write(to: dir.appendingPathComponent("1.mp4"))
        try Data(count: 1_000_000).write(to: dir.appendingPathComponent("6.mp4"))
        return (dir, dbPath)
    }

    func testEvictsOldestWholeVideoWhenOverCap() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 1_500_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 1)
        XCTAssertEqual(result.deletedFrames, 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("1.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6.mp4").path))
        XCTAssertEqual(TestSupport.scalarInt("SELECT COUNT(*) FROM FRAME", dbPath: dbPath), 5)
        XCTAssertEqual(TestSupport.scalarInt("SELECT MIN(id) FROM FRAME", dbPath: dbPath), 6)
    }

    func testNeverDeletesTheNewestVideo() throws {
        let (dir, dbPath) = try seedStorage()

        // Cap so small that even deleting 1.mp4 cannot reach it.
        let result = StorageCleaner.cleanupToFit(
            maxBytes: 100_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 1, "only the oldest video may go; the newest is protected")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("6.mp4").path))
    }

    func testNoOpWhenUnderCap() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 50_000_000, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 0)
        XCTAssertEqual(result.deletedFrames, 0)
        XCTAssertEqual(TestSupport.scalarInt("SELECT COUNT(*) FROM FRAME", dbPath: dbPath), 10)
    }

    func testNoOpWhenCapIsZero() throws {
        let (dir, dbPath) = try seedStorage()

        let result = StorageCleaner.cleanupToFit(
            maxBytes: 0, dbPath: dbPath, cachePath: dir, framesPerVideo: 5
        )

        XCTAssertEqual(result.deletedVideos, 0)
        XCTAssertEqual(result.deletedFrames, 0)
    }
}
```

- [ ] **Step 7.2: Run tests to verify they fail**

Run: `cd MementoCapture && swift test --filter StorageCleanerFitTests`
Expected: COMPILE ERROR — `cleanupToFit` does not exist.

- [ ] **Step 7.3: Implement cleanupToFit**

Add to `MementoCapture/Sources/StorageCleaner.swift` (after `cleanup(...)`):

```swift
    /// Deletes oldest whole videos (and their DB rows) until total directory
    /// usage is at or below ~95% of `maxBytes`. The newest video is never
    /// deleted (the encoder may still be writing to it). `maxBytes <= 0` is
    /// a no-op. Always call off the main thread — this walks the directory.
    static func cleanupToFit(
        maxBytes: Int64,
        dbPath: String,
        cachePath: URL,
        framesPerVideo: Int = 5
    ) -> Result {
        guard maxBytes > 0,
              let currentBytes = StorageMetrics.walkTotalBytes(in: cachePath),
              currentBytes > maxBytes else {
            return Result(deletedFrames: 0, deletedVideos: 0)
        }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            return Result(deletedFrames: 0, deletedVideos: 0)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 5000)
        execute(db: db, sql: "PRAGMA foreign_keys=ON")

        let maxFrameId = fetchMaxFrameId(db: db)
        let videoRanges = buildVideoRanges(
            cachePath: cachePath,
            maxFrameId: maxFrameId,
            defaultFramesPerVideo: framesPerVideo
        )

        let targetBytes = Int64(Double(maxBytes) * 0.95)
        var bytesToFree = currentBytes - targetBytes
        var deletedFrames = 0
        var deletedVideos = 0

        // buildVideoRanges returns ranges sorted by start frame id (oldest
        // first); dropLast() protects the newest, possibly in-progress video.
        for videoRange in videoRanges.dropLast() {
            guard bytesToFree > 0 else { break }

            let fileSize = (try? FileManager.default
                .attributesOfItem(atPath: videoRange.fileURL.path)[.size] as? NSNumber)
                .map(\.int64Value) ?? 0

            let frameIds = Array(videoRange.frameIds)
            guard execute(db: db, sql: "BEGIN TRANSACTION"),
                  deleteRows(forFrameIds: frameIds, db: db),
                  execute(db: db, sql: "COMMIT") else {
                execute(db: db, sql: "ROLLBACK")
                break
            }
            deletedFrames += frameIds.count

            if (try? FileManager.default.removeItem(at: videoRange.fileURL)) != nil {
                deletedVideos += 1
                bytesToFree -= fileSize
            }
        }

        return Result(deletedFrames: deletedFrames, deletedVideos: deletedVideos)
    }
```

- [ ] **Step 7.4: Run tests to verify they pass**

Run: `cd MementoCapture && swift test --filter StorageCleanerFitTests`
Expected: 4 tests PASS. (`testNeverDeletesTheNewestVideo` exercises the `dropLast()` guard; the WAL/db sizes are tiny relative to the 1 MB videos so the byte math is robust.)

- [ ] **Step 7.5: Add the Settings property**

In `MementoCapture/Sources/Settings.swift`:

`Key` enum:

```swift
        case maxStorageGB = "maxStorageGB"
```

Published property (after `excludeFromBackup`):

```swift
    /// Max total storage in GB. 0 = no limit (default).
    @Published var maxStorageGB: Int {
        didSet {
            let sanitized = max(0, maxStorageGB)
            if sanitized != maxStorageGB {
                maxStorageGB = sanitized
                return
            }
            defaults.set(sanitized, forKey: Key.maxStorageGB.rawValue)
        }
    }
```

`init()` (with the other loads):

```swift
        self.maxStorageGB = defaults.object(forKey: Key.maxStorageGB.rawValue) as? Int ?? 0
```

- [ ] **Step 7.6: Replace retention-at-start with periodic maintenance**

In `MementoCapture/Sources/CaptureService.swift`:

Add state (next to `private var timer: Timer?`):

```swift
    private var maintenanceTimer: Timer?
    private static let maintenanceInterval: TimeInterval = 6 * 60 * 60
```

In `start()`, replace `applyRetentionPolicyIfNeeded()` with:

```swift
        runStorageMaintenance()
        scheduleMaintenanceTimer()
```

In `stop()`, after `timer = nil`:

```swift
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
```

Replace the whole `applyRetentionPolicyIfNeeded()` (lines 602-638) with:

```swift
    private func scheduleMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = Timer.scheduledTimer(
            withTimeInterval: Self.maintenanceInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.runStorageMaintenance()
            }
        }
    }

    /// Retention first, then the size cap — whichever demands more wins.
    /// One sequential detached task; both cleaners open their own connection.
    private func runStorageMaintenance() {
        let dbPath = cachePath.appendingPathComponent("memento.db").path
        let framesPerVideo = self.framesPerVideo
        let cachePath = self.cachePath
        let retentionCutoff = retentionCutoffISO8601IfDue()
        let maxGB = Settings.shared.maxStorageGB
        let maxBytes = maxGB > 0 ? Int64(maxGB) * 1_000_000_000 : 0

        guard retentionCutoff != nil || maxBytes > 0 else { return }

        Task.detached(priority: .utility) {
            if let cutoff = retentionCutoff {
                let result = StorageCleaner.cleanup(
                    dbPath: dbPath,
                    cachePath: cachePath,
                    cutoffISO8601: cutoff,
                    deleteAll: false,
                    framesPerVideo: framesPerVideo
                )
                if result.deletedFrames > 0 || result.deletedVideos > 0 {
                    AppLog.info("🧹 Retention cleanup: \(result.deletedFrames) frames, \(result.deletedVideos) videos deleted")
                }
            }

            if maxBytes > 0 {
                let result = StorageCleaner.cleanupToFit(
                    maxBytes: maxBytes,
                    dbPath: dbPath,
                    cachePath: cachePath,
                    framesPerVideo: framesPerVideo
                )
                if result.deletedFrames > 0 || result.deletedVideos > 0 {
                    AppLog.info("🧹 Storage limit cleanup: \(result.deletedFrames) frames, \(result.deletedVideos) videos deleted")
                }
            }

            await MainActor.run { StorageMetrics.invalidateCache() }
        }
    }

    /// Returns the retention cutoff if a cleanup is due, else nil.
    /// Keeps the existing 12h throttle and its UserDefaults timestamp key
    /// (internal bookkeeping, not a user setting — predates the Settings rule).
    private func retentionCutoffISO8601IfDue() -> String? {
        let daysToKeep = Settings.shared.retentionDays
        guard daysToKeep > 0 && daysToKeep < 9999 else { return nil }

        let defaults = UserDefaults.standard
        let lastCleanupKey = "lastRetentionCleanupAt"
        let minimumInterval: TimeInterval = 12 * 60 * 60
        let now = Date()

        if let lastCleanup = defaults.object(forKey: lastCleanupKey) as? Date,
           now.timeIntervalSince(lastCleanup) < minimumInterval {
            return nil
        }
        defaults.set(now, forKey: lastCleanupKey)

        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: now) else {
            return nil
        }
        return Self.iso8601Formatter.string(from: cutoffDate)
    }
```

- [ ] **Step 7.7: Add the max-size field to SettingsWindow**

In the Storage `Section`, after the retention rows from Task 6:

```swift
                    HStack {
                        Text(L.maxStorageSize)
                        Spacer()
                        TextField("", value: $settings.maxStorageGB, format: .number)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("GB")
                    }
                    Text(L.maxStorageHint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
```

`private extension L`:

```swift
    static var maxStorageSize: String { isSwedish ? "Max lagringsstorlek" : "Max storage size" }
    static var maxStorageHint: String {
        isSwedish
            ? "0 = ingen gräns. När gränsen överskrids raderas äldsta inspelningarna automatiskt."
            : "0 = no limit. When exceeded, the oldest recordings are deleted automatically."
    }
```

- [ ] **Step 7.8: Document in docs/SETTINGS.md**

In `## Storage Settings / Lagring`, after the retention entry:

```markdown
### Max storage size

Default: `0` (no limit)

**EN:** Hard cap in GB. When total usage exceeds the cap, the oldest whole video files and their database rows are deleted until usage is back under ~95% of the cap. Enforced at app start and every 6 hours, together with retention (whichever demands more deletion wins).

**SV:** Hård gräns i GB. När total användning överskrider gränsen raderas äldsta hela videofiler och deras databasrader tills användningen är under ~95 % av gränsen. Tillämpas vid appstart och var 6:e timme, tillsammans med retention (den som kräver mest radering vinner).
```

- [ ] **Step 7.9: Build + full suite**

Run: `cd MementoCapture && swift build && swift test`
Expected: builds clean, ALL tests pass (now ~20 tests).

- [ ] **Step 7.10: Commit**

```bash
git add MementoCapture/Sources/StorageCleaner.swift MementoCapture/Sources/Settings.swift MementoCapture/Sources/CaptureService.swift MementoCapture/Sources/SettingsWindow.swift docs/SETTINGS.md MementoCapture/Tests/StorageCleanerFitTests.swift
git commit -m "Add max storage size with oldest-first eviction and periodic maintenance

New maxStorageGB setting (0 = no limit). Retention and the size cap now
run at start and every 6 hours instead of start-only, in one sequential
background pass.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation (CLAUDE.md, ADRs, Dev Log)

**Files:**
- Modify: `CLAUDE.md`
- Obsidian (via MCP tools): `Projects/Memento Native/Architecture Decisions.md`, `Projects/Memento Native/Dev Log.md`

- [ ] **Step 8.1: Update CLAUDE.md**

Make these exact changes:

1. **Key Types Reference** — add rows:

```markdown
| `StorageProtection` | Capture | StorageProtection.swift | Storage dir permissions + backup exclusion |
| `RetentionOptions` | Capture | RetentionOptions.swift | Retention preset/custom mapping |
```

2. **Storage Schema** section — add after the video files line:

```markdown
**Integrity:** `PRAGMA foreign_keys=ON` and `sqlite3_busy_timeout(5000)` are set per write connection (`Database`, `StorageCleaner`). The pragma is per-connection — any new connection that writes must set both.
```

3. **Common Gotchas** — append:

```markdown
14. **Concealed pasteboard types** — `ClipboardCapture` skips content marked `org.nspasteboard.ConcealedType`/`TransientType`/`AutoGeneratedType` (password managers set these). Never remove this filter.

15. **FK pragma is per connection** — `PRAGMA foreign_keys=ON` is set in `Database.openDatabase()` and `StorageCleaner`. A new SQLite connection that writes must set it too, plus `sqlite3_busy_timeout`, since maintenance and capture write concurrently.

16. **`PRAGMA table_info` cannot be parameterized** — `Database.columnExists` interpolates the table name from internal constants only. This is the single sanctioned exception to the no-SQL-interpolation rule.

17. **`StorageMetrics.walkTotalBytes` must never run on the main thread** — a real storage directory has 100k+ files and takes 10+ seconds to walk. Use the async cached `totalBytes(in:)` from UI code.

18. **Maintenance schedule** — retention + size cap run via `CaptureService.runStorageMaintenance()` at `start()` and every 6 hours. Retention keeps its own 12h throttle (`lastRetentionCleanupAt` in UserDefaults).
```

4. **Rules for AI Agents → Never Do These** — replace the stale bullet:

```markdown
- **Never add unit test stubs.** There is no test framework configured; do not create one unless explicitly asked.
```

with:

```markdown
- **Tests live in `MementoCapture/Tests` (`MementoCaptureTests`, XCTest).** Write tests there for capture-side changes; do not add new test frameworks or stub tests without behavior.
```

5. **Settings Access** section — after the code example, add:

```markdown
New settings keys (2026-06-10): `excludeFromBackup` (Bool, default true), `maxStorageGB` (Int, default 0 = no limit).
```

- [ ] **Step 8.2: Write ADRs and Dev Log in Obsidian**

Use the Obsidian MCP tools (load via ToolSearch: `select:mcp__MCP_DOCKER__obsidian_get_file_contents,mcp__MCP_DOCKER__obsidian_append_content`).

1. Read `Projects/Memento Native/Architecture Decisions.md` to find the next ADR number (call it N).
2. Append three ADRs (numbered N, N+1, N+2), each in the file's existing format (Decision → Alternatives considered → Motivering):
   - **ADR-N: Clipboard concealed-type filtering.** Decision: always skip pasteboard content marked with nspasteboard.org marker types. Alternatives: setting-gated filtering (rejected — correctness, not preference); app-specific blocklist (rejected — the marker standard is universal). Motivering: passwords from password managers must never reach the database.
   - **ADR-N+1: Storage protection & encryption stance.** Decision: POSIX 0700 + `isExcludedFromBackup` setting (default on) + FK enforcement; full encryption at rest rejected because SQLCipher violates the zero-dependency constraint — stance is FileVault + hardening. Alternatives: SQLCipher (rejected), encrypted sparse bundle (rejected — fragile), no change (rejected).
   - **ADR-N+2: Storage maintenance.** Decision: periodic (6h) retention + size-cap enforcement with oldest-first whole-video eviction to 95% of cap, async cached storage metrics, busy_timeout on write connections. Alternatives: enforce per capture frame (rejected — walk cost), incremental byte accounting (rejected for now — drift risk, YAGNI), warning-only cap (rejected by user).
3. Append to `Projects/Memento Native/Dev Log.md`:

```markdown
## 2026-06-10 — Privacy, integrity & storage hardening

Implemented from docs/superpowers/specs/2026-06-10-weakness-fixes-design.md:
clipboard concealed-type filtering, StorageProtection (0700 + Time Machine
exclusion setting), foreign key enforcement + busy_timeout, quiet schema
migrations, async storage metrics (settings window blocked 10+ s walking
145k files on the main thread — root-caused and measured), custom retention
(1-365 days), maxStorageGB cap with oldest-first eviction, 6-hour maintenance
schedule. All TDD — new XCTest suites in MementoCaptureTests.
Lesson: SwiftUI body must never do filesystem walks; SQLite pragmas are
per-connection.
```

If the Obsidian MCP is unavailable in this session, write the same content to `docs/superpowers/notes/2026-06-10-obsidian-pending.md` instead and flag it in the final report so it can be transferred.

- [ ] **Step 8.3: Commit**

```bash
git add CLAUDE.md
git commit -m "Document hardening changes in CLAUDE.md

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Final verification + deploy

- [ ] **Step 9.1: Full build + test, both packages**

```bash
cd /Users/uygarduzgun/Sites/memento-native/MementoCapture && swift build -c release && swift test
cd /Users/uygarduzgun/Sites/memento-native/MementoTimeline && swift build -c release
```
Expected: both build clean; full suite passes.

- [ ] **Step 9.2: Ask the user before deploying**

The running menu bar app still uses the old binary. Ask the user whether to deploy now via `cd MementoCapture && ./bundle.sh`. Do NOT deploy without confirmation (it restarts their capture agent).

- [ ] **Step 9.3 (if approved): Deploy and verify the running binary**

```bash
cd /Users/uygarduzgun/Sites/memento-native/MementoCapture && ./bundle.sh
ps aux | grep memento | grep -v grep
```
Expected: the running process path matches the freshly bundled binary (CLAUDE.md gotcha #12 — check for stale `Memento Capture` vs `memento-capture` shadowing). Then verify behavior: settings window opens instantly with "Beräknar…" placeholder; copying a password from a password manager (with clipboard capture on) stores nothing.

- [ ] **Step 9.4: Report**

Summarize: tests added/passing, commits made, behavior changes, and the one user-visible default change (Time Machine exclusion on).
