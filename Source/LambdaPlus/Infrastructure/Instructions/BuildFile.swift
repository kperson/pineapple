import Foundation


public struct BuildFile {
    
    public let path: String
    public let data: String
    
    public init(path: String, data: String) {
        self.path = path.hasSuffix("/") ? String(path.dropLast()) : path
        self.data = data
    }
    
}

public extension Array where Element == BuildFile {
    
    func saveFiles(baseDir: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        let dir = baseDir
        for file in self {
            let fileURL = dir.appendingPathComponent(file.path, isDirectory: false)
            let parentDir = fileURL.deletingLastPathComponent()
            try manager.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try file.data.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
}
