import Foundation
import SQLite3

/// SQLite database for storing OCR results
final class Database {
    private var db: OpaquePointer?
    private let path: String
    private var insertFrameStatement: OpaquePointer?
    private var insertContentStatement: OpaquePointer?
    private var insertEmbeddingStatement: OpaquePointer?
    
    init(path: String) {
        self.path = path
        openDatabase()
        createTables()
    }
    
    deinit {
        close()
    }

    func close() {
        guard db != nil else { return }
        finalizeStatements()
        sqlite3_close(db)
        db = nil
    }
    
    private func openDatabase() {
        if sqlite3_open(path, &db) != SQLITE_OK {
            AppLog.warning("⚠️ Failed to open database at \(path)")
            return
        }
        
        // Enable WAL mode for better concurrency
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        // Enforce declared FOREIGN KEYs (off by default in SQLite; per connection)
        execute("PRAGMA foreign_keys=ON")
        // Maintenance may write concurrently; wait briefly instead of failing with SQLITE_BUSY
        sqlite3_busy_timeout(db, 5000)

        AppLog.info("📊 Database opened: \(path)")
    }
    
    private func createTables() {
        // Frame table
        execute("""
            CREATE TABLE IF NOT EXISTS FRAME (
                id INTEGER PRIMARY KEY,
                window_title TEXT NOT NULL,
                time TEXT NOT NULL,
                url TEXT,
                tab_title TEXT,
                app_bundle_id TEXT,
                clipboard TEXT
            )
        """)
        
        // Add new columns if they don't exist (migration)
        addColumnIfMissing(table: "FRAME", column: "url", definition: "url TEXT")
        addColumnIfMissing(table: "FRAME", column: "tab_title", definition: "tab_title TEXT")
        addColumnIfMissing(table: "FRAME", column: "app_bundle_id", definition: "app_bundle_id TEXT")
        addColumnIfMissing(table: "FRAME", column: "clipboard", definition: "clipboard TEXT")
        addColumnIfMissing(table: "FRAME", column: "app_category", definition: "app_category TEXT")
        
        // Content table
        execute("""
            CREATE TABLE IF NOT EXISTS CONTENT (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                frame_id INTEGER NOT NULL,
                text TEXT NOT NULL,
                x INTEGER NOT NULL,
                y INTEGER NOT NULL,
                w INTEGER NOT NULL,
                h INTEGER NOT NULL,
                FOREIGN KEY (frame_id) REFERENCES FRAME(id) ON DELETE RESTRICT
            )
        """)

        // FTS table for fast text search
        execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS CONTENT_FTS USING fts5(
                frame_id, text, x, y, w, h
            )
        """)
        
        // Embeddings table for vector search (quantized int8 for 8x compression)
        execute("""
            CREATE TABLE IF NOT EXISTS EMBEDDING (
                frame_id INTEGER PRIMARY KEY,
                vector BLOB NOT NULL,
                quantized INTEGER DEFAULT 1,
                text_summary TEXT,
                language TEXT,
                revision INTEGER DEFAULT 0,
                FOREIGN KEY (frame_id) REFERENCES FRAME(id) ON DELETE RESTRICT
            )
        """)
        addColumnIfMissing(table: "EMBEDDING", column: "language", definition: "language TEXT")
        addColumnIfMissing(table: "EMBEDDING", column: "revision", definition: "revision INTEGER DEFAULT 0")
        
        // Indexes
        execute("CREATE INDEX IF NOT EXISTS idx_content_frame_id ON CONTENT(frame_id)")
        execute("CREATE INDEX IF NOT EXISTS idx_frame_time ON FRAME(time)")
        
        configureContentFTS()

        prepareStatements()
    }

    private func configureContentFTS() {
        execute("DROP TRIGGER IF EXISTS insert_content_fts")
        execute("DROP TRIGGER IF EXISTS delete_content_fts")
        execute("DROP TRIGGER IF EXISTS update_content_fts")

        execute("""
            CREATE TRIGGER insert_content_fts
            AFTER INSERT ON CONTENT
            BEGIN
                INSERT INTO CONTENT_FTS (rowid, frame_id, text, x, y, w, h)
                VALUES (new.id, new.frame_id, new.text, new.x, new.y, new.w, new.h);
            END
        """)

        execute("""
            CREATE TRIGGER delete_content_fts
            AFTER DELETE ON CONTENT
            BEGIN
                DELETE FROM CONTENT_FTS WHERE rowid = old.id;
            END
        """)

        execute("""
            CREATE TRIGGER update_content_fts
            AFTER UPDATE ON CONTENT
            BEGIN
                DELETE FROM CONTENT_FTS WHERE rowid = old.id;
                INSERT INTO CONTENT_FTS (rowid, frame_id, text, x, y, w, h)
                VALUES (new.id, new.frame_id, new.text, new.x, new.y, new.w, new.h);
            END
        """)

        markContentFTSMigrationAppliedIfNeeded()
    }

    private func markContentFTSMigrationAppliedIfNeeded() {
        // A full FTS rebuild can rewrite gigabytes for long-running timelines.
        // Future inserts/deletes are covered by triggers and StorageCleaner removes
        // frame-scoped FTS rows explicitly, so do not rebuild at app startup.
        guard contentFTSSchemaVersionValue() < 1 else { return }
        execute("PRAGMA user_version = 1")
    }

    private func contentFTSSchemaVersionValue() -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

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

    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func prepareStatements() {
        prepareStatement(
            """
            INSERT OR REPLACE INTO FRAME (id, window_title, time, url, tab_title, app_bundle_id, clipboard, app_category)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            statement: &insertFrameStatement
        )
        prepareStatement(
            "INSERT INTO CONTENT (frame_id, text, x, y, w, h) VALUES (?, ?, ?, ?, ?, ?)",
            statement: &insertContentStatement
        )
        prepareStatement(
            "INSERT OR REPLACE INTO EMBEDDING (frame_id, vector, quantized, text_summary, language, revision) VALUES (?, ?, ?, ?, ?, ?)",
            statement: &insertEmbeddingStatement
        )
    }

    private func prepareStatement(_ sql: String, statement: inout OpaquePointer?) {
        finalizeStatement(&statement)
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if let db {
                AppLog.warning("⚠️ Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
            }
            return
        }
    }

    private func resetStatement(_ statement: OpaquePointer?) {
        sqlite3_clear_bindings(statement)
        sqlite3_reset(statement)
    }

    private func finalizeStatements() {
        finalizeStatement(&insertFrameStatement)
        finalizeStatement(&insertContentStatement)
        finalizeStatement(&insertEmbeddingStatement)
    }

    private func finalizeStatement(_ statement: inout OpaquePointer?) {
        if let pointer = statement {
            sqlite3_finalize(pointer)
            statement = nil
        }
    }
    
    func insertFrame(
        frameId: Int,
        windowTitle: String,
        time: String,
        textBlocks: [TextBlock],
        url: String? = nil,
        tabTitle: String? = nil,
        appBundleId: String? = nil,
        clipboard: String? = nil,
        appCategory: String? = nil
    ) -> Bool {
        guard execute("BEGIN IMMEDIATE TRANSACTION") else { return false }

        var shouldRollback = true
        defer {
            if shouldRollback {
                _ = execute("ROLLBACK")
            }
        }

        guard let frameStatement = insertFrameStatement else {
            logSQLiteError("frame insert statement unavailable")
            return false
        }

        resetStatement(frameStatement)
        sqlite3_bind_int(frameStatement, 1, Int32(frameId))
        sqlite3_bind_text(frameStatement, 2, windowTitle, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(frameStatement, 3, time, -1, SQLITE_TRANSIENT)
        if let url = url {
            sqlite3_bind_text(frameStatement, 4, url, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(frameStatement, 4)
        }
        if let tabTitle = tabTitle {
            sqlite3_bind_text(frameStatement, 5, tabTitle, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(frameStatement, 5)
        }
        if let appBundleId = appBundleId {
            sqlite3_bind_text(frameStatement, 6, appBundleId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(frameStatement, 6)
        }
        if let clipboard = clipboard {
            sqlite3_bind_text(frameStatement, 7, clipboard, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(frameStatement, 7)
        }
        if let appCategory = appCategory {
            sqlite3_bind_text(frameStatement, 8, appCategory, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(frameStatement, 8)
        }

        guard step(frameStatement, context: "insert frame \(frameId)") else {
            return false
        }

        if !textBlocks.isEmpty {
            guard let contentStatement = insertContentStatement else {
                logSQLiteError("content insert statement unavailable")
                return false
            }

            for block in textBlocks {
                resetStatement(contentStatement)
                sqlite3_bind_int(contentStatement, 1, Int32(frameId))
                sqlite3_bind_text(contentStatement, 2, block.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(contentStatement, 3, Int32(block.x))
                sqlite3_bind_int(contentStatement, 4, Int32(block.y))
                sqlite3_bind_int(contentStatement, 5, Int32(block.width))
                sqlite3_bind_int(contentStatement, 6, Int32(block.height))

                guard step(contentStatement, context: "insert OCR block for frame \(frameId)") else {
                    return false
                }
            }
        }

        guard execute("COMMIT") else { return false }
        shouldRollback = false
        return true
    }
    
    func getMaxFrameId() -> Int {
        let sql = "SELECT MAX(id) FROM FRAME"
        var stmt: OpaquePointer?
        var maxId = 0
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxId = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
        }
        return maxId
    }
    
    // MARK: - Embedding Storage (Quantized Int8)
    
    func insertEmbedding(
        frameId: Int,
        vector: Data,
        textSummary: String,
        quantized: Bool = true,
        language: String? = nil,
        revision: Int = 0
    ) -> Bool {
        guard let stmt = insertEmbeddingStatement else {
            logSQLiteError("embedding insert statement unavailable")
            return false
        }

        resetStatement(stmt)
        sqlite3_bind_int(stmt, 1, Int32(frameId))
        _ = vector.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(vector.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(stmt, 3, quantized ? 1 : 0)
        sqlite3_bind_text(stmt, 4, textSummary, -1, SQLITE_TRANSIENT)
        if let language, !language.isEmpty {
            sqlite3_bind_text(stmt, 5, language, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_bind_int(stmt, 6, Int32(revision))
        return step(stmt, context: "insert embedding for frame \(frameId)")
    }
    
    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let error = errorMessage {
                AppLog.warning("⚠️ SQL error: \(String(cString: error))")
                sqlite3_free(error)
            }
            return false
        }
        return true
    }

    private func step(_ statement: OpaquePointer?, context: String) -> Bool {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            logSQLiteError("\(context) failed (\(result))")
            return false
        }
        return true
    }

    private func logSQLiteError(_ prefix: String) {
        guard let db else {
            AppLog.warning("⚠️ SQLite error: \(prefix)")
            return
        }
        AppLog.warning("⚠️ SQLite error: \(prefix): \(String(cString: sqlite3_errmsg(db)))")
    }
}
