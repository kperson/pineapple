import Foundation
import XCTest
import LambdaPlus


class BuildFileTestCase: XCTestCase {
    
    func testWrite() throws {
        let buildFiles = [
            BuildFile(
                path: "hello.txt",
                data: "hello world"
            ),
            BuildFile(
                path: "nested/hello.txt",
                data: "hello world"
            )
        ]
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try buildFiles.saveFiles(baseDir: baseDir)
        let fileManager = FileManager.default
        
        XCTAssertTrue(fileManager.fileExists(
            atPath: baseDir.appendingPathComponent("hello.txt", isDirectory: false).path)
        )
        
        XCTAssertTrue(fileManager.fileExists(
            atPath: baseDir.appendingPathComponent("nested/hello.txt", isDirectory: false).path)
        )
        try fileManager.removeItem(at: baseDir)
    }
    
}
