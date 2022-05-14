import LambdaRuntimeAPI
import Foundation

public protocol RecordsItem {
    
    associatedtype Meta
    associatedtype Body
    
    init?(dict: [String : Any])
    
    var recordMeta: Meta { get }
    var recordBody: Body { get }
    
    static var recordsKey: String? { get }
}

public protocol RecordsEventHandler {
    
    associatedtype Meta
    associatedtype Body
    associatedtype Returning
    
    func handleEvent(_ event: [Record<Meta, Body>]) async throws -> Returning
    
}


public class RecordsAppsEventHandler<T: RecordsItem, R>: LambdaAppEventHandler {
    
    public typealias Handler = ([Record<T.Meta, T.Body>]) async throws -> R
    public typealias BodyHandler = ([T.Body]) async throws -> R
    public let handler: Handler

    public init(_ h: @escaping Handler) {
        self.handler = h
    }
    
    public init<H: RecordsEventHandler>(_ h: H) where H.Body == T.Body, H.Meta == T.Meta, H.Returning == R {
        self.handler = {
            try await h.handleEvent($0)
        }
    }
    
    public func handleEvent(_ event: LambdaEvent) {
        let d = try? JSONSerialization.jsonObject(with: event.payload.body) as? [String : Any]
        let data = d ?? [:]
        let recordsKey = T.recordsKey ?? "Records"
        if let records = data[recordsKey] as? [[String : Any]] {
            let transformedRecords = records
                .compactMap { T(dict: $0) }
                .map { r in Record(meta: r.recordMeta, body: r.recordBody) }
            Task {
                do {
                    _ = try await handler(transformedRecords)
                    event.sendResponse(data: [:])
                }
                catch let error {
                    event.sendInvocationError(error: LambdaError(error: error))
                }
            }
        }
        else {
            event.sendResponse(data: [:])
        }
        
    }
}
