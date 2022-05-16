import Foundation

public protocol Partitionable {
    
    var partitionKey: String? { get }
    
}

public protocol Deduplicatable {
    
    var deduplicationKey: String? { get }
    
}

public protocol PartitionWrite {
        
    associatedtype Out
    
    func write(partitionKey: String, value: Out) async throws -> Void
    
}


public extension PartitionWrite {
    
    func write(value: Out) async throws -> Void {
        try await write(partitionKey: UUID().uuidString, value: value)
    }

}
