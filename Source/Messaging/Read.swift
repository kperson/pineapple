import Foundation


public protocol Read {
    
    associatedtype In
        
    func forEach(_ handler: @escaping (In) async throws -> Void)
    
}

public class PublishReader<In>: Read {
                
    private var handler: ((In) async throws -> Void)?
    
    public func publish(_ input: In) async throws {
        try await handler?(input)
    }
    
    public func forEach(_ handler: @escaping (In) async throws -> Void) {
        self.handler = handler
    }
    
}

public class FilterRead<InRead: Read, Input>: Read where InRead.In == Input {
    
    public typealias In = Input

    private let filterHandler: (InRead.In) async throws -> Bool
    private let inRead: InRead
    
    init(
        inRead: InRead,
        filterHandler: @escaping (InRead.In) async throws -> Bool
    ) {
        self.inRead = inRead
        self.filterHandler = filterHandler
    }
    
    public func forEach(_ handler: @escaping (In) async throws -> Void) {
        inRead.forEach {
            let passes = try await self.filterHandler($0)
            if passes {
                try await handler($0)
            }
        }
    }
}

public class FlatMapRead<InRead: Read, Input, Output>: Read where InRead.In == Input {
    
    public typealias In = Output

    private let flatMapHandler: (InRead.In) async throws -> [Output]
    private let inRead: InRead
    
    init(
        inRead: InRead,
        flatMapHandler: @escaping (InRead.In) async throws -> [Output]
    ) {
        self.inRead = inRead
        self.flatMapHandler = flatMapHandler
    }
    
    public func forEach(_ handler: @escaping (In) async throws -> Void) {
        inRead.forEach {
            let newValues = try await self.flatMapHandler($0)
            for v in newValues {
                try await handler(v)
            }
        }
    }
    
}

public extension Read {

    func flatMap<Out>(_ f: @escaping (In) async throws -> [Out]) -> FlatMapRead<Self, In, Out> {
        return FlatMapRead(inRead: self, flatMapHandler: f)
    }
    
    func compactMap<Out>(_ f: @escaping (In) async throws -> Out?) -> FlatMapRead<Self, In, Out> {
        return flatMap {
            if let v = try await f($0) {
                return [v]
            }
            return []
        }
    }
    
    func map<Out>(_ f: @escaping (In) async throws -> Out) -> FlatMapRead<Self, In, Out> {
        return compactMap(f)
    }

    func filter(_ f: @escaping (In) async throws -> Bool) -> FilterRead<Self, Self.In> {
        return FilterRead(inRead: self, filterHandler: f)
    }

}


public extension Read {

    func sink<Write: PartitionWrite>(
        write: Write,
        _ createPartitionKey: @escaping (In) -> String?
    ) where Write.Out == In {
        forEach {
            if let partitionKey = createPartitionKey($0) {
                try await write.write(partitionKey: partitionKey, value: $0)
            }
            else {
                try await write.write(value: $0)
            }
        }
    }

    func sinkPartitionable<Write: PartitionWrite>(write: Write) where In: Partitionable, Write.Out == In {
        sink(write: write) { $0.partitionKey }
    }
    
    func sink<Write: PartitionWrite>(write: Write) where Write.Out == In {
        sink(write: write) { _ in nil }
    }
    
}

