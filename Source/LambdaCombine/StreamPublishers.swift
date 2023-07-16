import Foundation
import CombineX
import LambdaApp

private class CancelBag {
    
    static let shared = CancelBag()
    var bag = Set<AnyCancellable>()
    
}

public protocol RecordTransformer {
    
    associatedtype Input
    associatedtype Output
    
    func transform(input: Input) throws -> Output
    
}

public class IdentityRecordTransformer<T>: RecordTransformer {
    
    public typealias Input = T
    public typealias Output = T
    
    public init() {}
    
    public func transform(input: T) throws -> T {
        return input
    }
    
}

public extension LambdaApp {

    func addSNSHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer>(
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        Transformer.Input == SNSEventHandler.HandlerItem,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([SNSEventHandler.HandlerItem]) async throws -> Void) {
            addSNSHandler(handlerKey, handler)
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addSNSHandler<PublisherResult: Publisher>(
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<SNSEventHandler.HandlerItem, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        PublisherResult.Failure == Error {
        addSNSHandler(handlerKey, IdentityRecordTransformer<SNSEventHandler.HandlerItem>(), operation)
    }
    
    func addSNSBodyHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer>(
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        Transformer.Input == SNSEventHandler.Body,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([SNSEventHandler.Body]) async throws -> Void) {
            addSNSBodyHandler(handlerKey, handler)
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addSNSBodyhandler<PublisherResult: Publisher>(
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<SNSEventHandler.Body, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        PublisherResult.Failure == Error {
        addSNSBodyHandler(handlerKey, IdentityRecordTransformer<SNSEventHandler.Body>(), operation)
    }
    
    func addSQSHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer>(
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        Transformer.Input == SQSEventHandler.HandlerItem,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([SQSEventHandler.HandlerItem]) async throws -> Void) {
            addSQSHandler(handlerKey, handler)
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addSQSHandler<PublisherResult: Publisher>(
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<SQSEventHandler.HandlerItem, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        PublisherResult.Failure == Error {
        addSQSHandler(handlerKey, IdentityRecordTransformer<SQSEventHandler.HandlerItem>(), operation)
    }
    
    func addSQSBodyHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer>(
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        Transformer.Input == SQSEventHandler.Body,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([SQSEventHandler.Body]) async throws -> Void) {
            addSQSBodyHandler(handlerKey, handler)
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addSQSBodyHandler<PublisherResult: Publisher>(
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<SQSEventHandler.Body, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        PublisherResult.Failure == Error {
        addSQSBodyHandler(handlerKey, IdentityRecordTransformer<SQSEventHandler.Body>(), operation)
    }
    
    func addS3BodyHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer>(
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == Void,
        Transformer.Input == S3EventHandler.Body,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([S3EventHandler.Body]) async throws -> Void) {
            addS3BodyHandler(handlerKey, handler)
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addS3BodyHandler<PublisherResult: Publisher>(
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<S3EventHandler.Body, Never>) -> PublisherResult
    ) where PublisherResult.Output == Void, PublisherResult.Failure == Error {
        addS3BodyHandler(handlerKey, IdentityRecordTransformer<S3EventHandler.Body>(), operation)
    }

    func addApiGatewayHandler<RecordType, PublisherResult: Publisher, Transformer: RecordTransformer> (
        _ handlerKey: CustomStringConvertible,
        _ recordTransformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == HTTPResponse,
        Transformer.Input == HTTPRequest,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        func add(_ handler: @escaping ([HTTPRequest]) async throws -> HTTPResponse) {
            addApiGateway(handlerKey) { req in
                try await handler([req])
            }
        }
        publisher(add, recordTransformer, operation)
    }
    
    func addApiGatewayHandler<PublisherResult: Publisher> (
        _ handlerKey: CustomStringConvertible,
        _ operation: @escaping (AnyPublisher<HTTPRequest, Never>) -> PublisherResult
    ) where PublisherResult.Output == HTTPResponse, PublisherResult.Failure == Error {
        addApiGatewayHandler(handlerKey, IdentityRecordTransformer<HTTPRequest>(), operation)
    }
    
    private func publisher<
        RecordType,
        PublisherResult: Publisher,
        NativeType,
        Transformer: RecordTransformer,
        SinkResult
    > (
        _ add: (@escaping ([NativeType]) async throws -> SinkResult) -> Void,
        _ transformer: Transformer,
        _ operation: @escaping (AnyPublisher<RecordType, Never>) -> PublisherResult
    ) where
        PublisherResult.Output == SinkResult,
        Transformer.Input == NativeType,
        Transformer.Output == RecordType,
        PublisherResult.Failure == Error {
        add { payload in
            return try await withUnsafeThrowingContinuation { (cont: UnsafeContinuation<SinkResult, Error>) -> Void in
                do {
                    let transformedItems = try payload.map { try transformer.transform(input: $0) }
                    let basePublisher = Publishers.Sequence<[RecordType], Never>(
                        sequence: transformedItems
                    ).eraseToAnyPublisher()
                    var cancellable: AnyCancellable?
                    cancellable = operation(basePublisher)
                        .sink(
                            receiveCompletion: { completion in
                                switch completion {
                                case .failure(let error):
                                    cont.resume(with: .failure(error))
                                    if let currentCancellable = cancellable {
                                        CancelBag.shared.bag.remove(currentCancellable)
                                    }
                                case .finished: Void()
                                }
                            },
                            receiveValue: { value in
                                cont.resume(with: .success(value))
                                if let currentCancellable = cancellable {
                                    CancelBag.shared.bag.remove(currentCancellable)
                                }
                            }
                        )
                    if let currentCancellable = cancellable {
                        CancelBag.shared.bag.insert(currentCancellable)
                    }
                }
                catch let error {
                    cont.resume(with: .failure(error))
                }
            }
        }
    }

}
