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
