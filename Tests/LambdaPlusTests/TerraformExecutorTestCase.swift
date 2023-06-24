import Foundation
import XCTest
import LambdaPlus

class TerraformExecutorTestCase: XCTestCase {

    
    func testRemoveManagedFiles() throws {
        let buildFiles = [
            BuildFile(
                path: "pineapple-hello.tf",
                data: "hello world"
            ),
            BuildFile(
                path: "pineapple-hello.txt",
                data: "hello world"
            ),
            BuildFile(
                path: "over-hello.tf",
                data: "hello world"
            )
        ]
        let tempDir = FileManager.default.temporaryDirectory
        let baseDir = tempDir.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try buildFiles.saveFiles(baseDir: baseDir)
        let executor = TerraformExecutor(outDir: baseDir)
        try executor.removeManagedFiles()
        
        let fileManager = FileManager.default
        
        XCTAssertTrue(fileManager.fileExists(
            atPath: baseDir.appendingPathComponent("pineapple-hello.txt", isDirectory: false).path)
        )
        
        XCTAssertTrue(fileManager.fileExists(
            atPath: baseDir.appendingPathComponent("over-hello.tf", isDirectory: false).path)
        )
        
        XCTAssertFalse(fileManager.fileExists(
            atPath: baseDir.appendingPathComponent("pineapple-hello.tf", isDirectory: false).path)
        )
        
        try fileManager.removeItem(at: baseDir)
    }

}
