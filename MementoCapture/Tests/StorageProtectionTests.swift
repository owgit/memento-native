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
