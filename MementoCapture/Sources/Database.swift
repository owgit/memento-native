import Foundation
import SQLite3

/// SQLite database for storing OCR results
class Database {
    private var db: OpaquePointer?
    private let path: String
    
    init(path: String) {
        self.path = path
        openDatabase()
        createTables()
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func openDatabase() {
        if sqlite3_open(path, &db) != SQLITE_OK {
            print("⚠️ Failed to open database at \(path)")
            return
        }
        
        // Enable WAL mode for better concurrency
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
        
        print("📊 Database opened: \(path)")
    }
    
    private func createTables() {
        // Frame table
        execute("""
            CREATE TABLE IF NOT EXISTS FRAME (
                id INTEGER PRIMARY KEY,
                window_title TEXT NOT NULL,
                time TEXT NOT NULL
            )
        """)
        
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
                FOREIGN KEY (frame_id) REFERENCES FRAME(id)
            )
        """)
        
        // FTS table for fast text search
        execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS CONTENT_FTS USING fts5(
                frame_id, text, x, y, w, h
            )
        """)
        
        // Embeddings table for vector search
        execute("""
            CREATE TABLE IF NOT EXISTS EMBEDDING (
                frame_id INTEGER PRIMARY KEY,
                vector BLOB NOT NULL,
                text_summary TEXT,
                FOREIGN KEY (frame_id) REFERENCES FRAME(id)
            )
        """)
        
        // Indexes
        execute("CREATE INDEX IF NOT EXISTS idx_content_frame_id ON CONTENT(frame_id)")
        execute("CREATE INDEX IF NOT EXISTS idx_frame_time ON FRAME(time)")
        
        // Trigger for FTS
        execute("""
            CREATE TRIGGER IF NOT EXISTS insert_content_fts
            AFTER INSERT ON CONTENT
            BEGIN
                INSERT INTO CONTENT_FTS (frame_id, text, x, y, w, h)
                VALUES (new.frame_id, new.text, new.x, new.y, new.w, new.h);
            END
        """)
    }
    
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    func insertFrame(frameId: Int, windowTitle: String, time: String, textBlocks: [TextBlock]) {
        // Insert frame
        let frameSQL = "INSERT OR REPLACE INTO FRAME (id, window_title, time) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, frameSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(frameId))
            sqlite3_bind_text(stmt, 2, windowTitle, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, time, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        
        // Insert text blocks
        guard !textBlocks.isEmpty else { return }
        
        let contentSQL = "INSERT INTO CONTENT (frame_id, text, x, y, w, h) VALUES (?, ?, ?, ?, ?, ?)"
        
        // Use transaction for batch insert
        execute("BEGIN TRANSACTION")
        
        for block in textBlocks {
            if sqlite3_prepare_v2(db, contentSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(frameId))
                sqlite3_bind_text(stmt, 2, block.text, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 3, Int32(block.x))
                sqlite3_bind_int(stmt, 4, Int32(block.y))
                sqlite3_bind_int(stmt, 5, Int32(block.width))
                sqlite3_bind_int(stmt, 6, Int32(block.height))
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
        
        execute("COMMIT")
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
    
    func search(query: String) -> [(frameId: Int, text: String)] {
        let sql = "SELECT frame_id, text FROM CONTENT_FTS WHERE text MATCH ? ORDER BY rank LIMIT 100"
        var stmt: OpaquePointer?
        var results: [(Int, String)] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, query, -1, nil)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let frameId = Int(sqlite3_column_int(stmt, 0))
                if let textPtr = sqlite3_column_text(stmt, 1) {
                    let text = String(cString: textPtr)
                    results.append((frameId, text))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    // MARK: - Embedding Storage
    
    func insertEmbedding(frameId: Int, vector: Data, textSummary: String) {
        let sql = "INSERT OR REPLACE INTO EMBEDDING (frame_id, vector, text_summary) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(frameId))
            _ = vector.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 2, ptr.baseAddress, Int32(vector.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_text(stmt, 3, textSummary, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
    
    func getAllEmbeddings() -> [(frameId: Int, vector: Data, summary: String)] {
        let sql = "SELECT frame_id, vector, text_summary FROM EMBEDDING"
        var stmt: OpaquePointer?
        var results: [(Int, Data, String)] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let frameId = Int(sqlite3_column_int(stmt, 0))
                
                if let blobPtr = sqlite3_column_blob(stmt, 1) {
                    let blobSize = Int(sqlite3_column_bytes(stmt, 1))
                    let vector = Data(bytes: blobPtr, count: blobSize)
                    
                    let summary: String
                    if let textPtr = sqlite3_column_text(stmt, 2) {
                        summary = String(cString: textPtr)
                    } else {
                        summary = ""
                    }
                    
                    results.append((frameId, vector, summary))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    func getFramesWithoutEmbedding(limit: Int = 100) -> [(frameId: Int, text: String)] {
        let sql = """
            SELECT f.id, GROUP_CONCAT(c.text, ' ') as all_text
            FROM FRAME f
            LEFT JOIN CONTENT c ON f.id = c.frame_id
            WHERE f.id NOT IN (SELECT frame_id FROM EMBEDDING)
            GROUP BY f.id
            HAVING all_text IS NOT NULL
            ORDER BY f.id DESC
            LIMIT ?
        """
        var stmt: OpaquePointer?
        var results: [(Int, String)] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(limit))
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                let frameId = Int(sqlite3_column_int(stmt, 0))
                if let textPtr = sqlite3_column_text(stmt, 1) {
                    let text = String(cString: textPtr)
                    results.append((frameId, text))
                }
            }
            sqlite3_finalize(stmt)
        }
        
        return results
    }
    
    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let error = errorMessage {
                print("⚠️ SQL error: \(String(cString: error))")
                sqlite3_free(error)
            }
            return false
        }
        return true
    }
}
