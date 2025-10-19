import Foundation
import Logging

/// Handler for SQS (Simple Queue Service) events - processes queue messages
public protocol SQSHandler: LambdaVoidEventHandler where Event == SQSEvent {}

/// Handler for SNS (Simple Notification Service) events - processes notifications
public protocol SNSHandler: LambdaVoidEventHandler where Event == SNSEvent {}

/// Handler for DynamoDB stream events - processes database change events
public protocol DynamoDBHandler: LambdaVoidEventHandler where Event == DynamoDBEvent {}

/// Handler for S3 bucket events - processes object created, deleted, etc.
public protocol S3Handler: LambdaVoidEventHandler where Event == S3Event {}

/// Handler for API Gateway events - processes HTTP requests and returns responses
public protocol APIGatewayHandler: LambdaEventHandler where Event == APIGatewayRequest, Output == APIGatewayResponse {}

/// Handler for EventBridge/CloudWatch Events - processes custom events
public protocol BasicHandler: LambdaEventHandler where Event == String, Output == String {}

/// Handler for EventBridge events with void return - fire-and-forget processing
public protocol BasicVoidHandler: LambdaVoidEventHandler where Event == String {}

public final class LambdaApp: RuntimeEventHandler, @unchecked Sendable {
    
    /// Internal storage for registered handlers with their associated keys
    internal var handlers: [String: Handler] = [:]
    
    private var logger: Logger
    public typealias LogFactory = (String) -> Logger
    private var loggerFactory: LogFactory = { label in Logger(label: label) }

    
    /// Enum representing all supported handler types with their implementations
    public enum Handler {
        case sqs(any SQSHandler)
        case sns(any SNSHandler)
        case dynamodb(any DynamoDBHandler)
        case s3(any S3Handler)
        case apiGateway(any APIGatewayHandler)
        case basic(any BasicHandler)
        case basicVoid(any BasicVoidHandler)
    }
    
    private var handlerKey: String?
    
    public init() {
        self.logger = loggerFactory("lambda")
    }
    
    /// Register a handler with a specific key for routing
    @discardableResult
    public func add(key: String, handler: Handler) -> LambdaApp {
        handlers[key] = handler
        return self
    }
    
    /// Retrieve a handler by key (for testing)
    public func handler(for key: String) -> Handler? {
        return handlers[key]
    }
    
    /// Register SQS handler with closure
    @discardableResult
    public func addSQS(key: String, handler: @escaping (LambdaContext, SQSEvent) async throws -> Void) -> LambdaApp {
        struct ClosureHandler: SQSHandler {
            let closure: (LambdaContext, SQSEvent) async throws -> Void
            func handleEvent(context: LambdaContext, event: SQSEvent) async throws {
                try await closure(context, event)
            }
        }
        return add(key: key, handler: .sqs(ClosureHandler(closure: handler)))
    }
    
    /// Register S3 handler with closure
    @discardableResult
    public func addS3(key: String, handler: @escaping (LambdaContext, S3Event) async throws -> Void) -> LambdaApp {
        struct ClosureHandler: S3Handler {
            let closure: (LambdaContext, S3Event) async throws -> Void
            func handleEvent(context: LambdaContext, event: S3Event) async throws {
                try await closure(context, event)
            }
        }
        return add(key: key, handler: .s3(ClosureHandler(closure: handler)))
    }
    
    /// Register SNS handler with closure
    @discardableResult
    public func addSNS(key: String, handler: @escaping (LambdaContext, SNSEvent) async throws -> Void) -> LambdaApp {
        struct ClosureHandler: SNSHandler {
            let closure: (LambdaContext, SNSEvent) async throws -> Void
            func handleEvent(context: LambdaContext, event: SNSEvent) async throws {
                try await closure(context, event)
            }
        }
        return add(key: key, handler: .sns(ClosureHandler(closure: handler)))
    }
    
    /// Register DynamoDB Streams handler with closure
    @discardableResult
    public func addDynamoDB(key: String, handler: @escaping (LambdaContext, DynamoDBEvent) async throws -> Void) -> LambdaApp {
        struct ClosureHandler: DynamoDBHandler {
            let closure: (LambdaContext, DynamoDBEvent) async throws -> Void
            func handleEvent(context: LambdaContext, event: DynamoDBEvent) async throws {
                try await closure(context, event)
            }
        }
        return add(key: key, handler: .dynamodb(ClosureHandler(closure: handler)))
    }
    
    /// Register API Gateway V1 handler with closure
    @discardableResult
    public func addAPIGateway(key: String, handler: @escaping (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse) -> LambdaApp {
        struct ClosureHandler: APIGatewayHandler {
            let closure: (LambdaContext, APIGatewayRequest) async throws -> APIGatewayResponse
            func handleEvent(context: LambdaContext, event: APIGatewayRequest) async throws -> APIGatewayResponse {
                return try await closure(context, event)
            }
        }
        return add(key: key, handler: .apiGateway(ClosureHandler(closure: handler)))
    }
    
    /// Register EventBridge handler with closure (uses String for flexibility)
    @discardableResult
    public func addEventBridge(key: String, handler: @escaping (LambdaContext, String) async throws -> Void) -> LambdaApp {
        struct ClosureHandler: BasicVoidHandler {
            let closure: (LambdaContext, String) async throws -> Void
            func handleEvent(context: LambdaContext, event: String) async throws {
                try await closure(context, event)
            }
        }
        return add(key: key, handler: .basicVoid(ClosureHandler(closure: handler)))
    }
    
    /// Get all registered handler keys
    public var handlerKeys: [String] {
        return Array(handlers.keys)
    }
    
    /// Get handler count
    public var handlerCount: Int {
        return handlers.count
    }
    
    // MARK: - LambdaEventHandler Implementation
    
    public func handleEvent(_ event: LambdaEvent) {
        logger.debug("LambdaApp.handleEvent called")
        let capturedHandlers = handlers
        let capturedHandlerCount = handlerCount
        let capturedHandlerKey = handlerKey
        Task {
            do {
                // Resolve handler key
                let key: String
                if let firstKey = capturedHandlers.keys.first, capturedHandlerCount == 1 {
                    key = firstKey
                } else {
                    guard let resolvedHandlerKey = capturedHandlerKey else {
                        throw LambdaError(errorMessage: "Multiple handlers registered but no handler key specified")
                    }
                    key = resolvedHandlerKey
                }
                
                logger.debug("Resolved handler key: \(key)")
                guard let handler = capturedHandlers[key] else {
                    throw LambdaError(errorMessage: "No handler found for key: \(key)")
                }
                
                logger.debug("Found handler, processing event")
                let perEventLogger = loggerFactory(key)
                try await Self.processHandler(handler, event: event, logger: perEventLogger)
                
            } catch {
                logger.error("Handler failed: \(error)")
                event.sendInvocationError(error: LambdaError(error: error))
            }
        }
    }
    
    private static func processHandler(_ handler: Handler, event: LambdaEvent, logger: Logger) async throws {
        let context = PineappleLambdaContext(
            requestId: event.requestId,
            headers: event.payload.headers,
            logger: logger
        )
        switch handler {
        case .sqs(let sqsHandler):
            logger.debug("Starting SQS handler")
            let sqsEvent = try JSONDecoder().decode(SQSEvent.self, from: event.payload.body)
            try await sqsHandler.handleEvent(context: context, event: sqsEvent)
            logger.debug("SQS handler completed")
            event.sendResponse(data: Data())
            
        case .s3(let s3Handler):
            logger.debug("Starting S3 handler")
            let s3Event = try JSONDecoder().decode(S3Event.self, from: event.payload.body)
            try await s3Handler.handleEvent(context: context, event: s3Event)
            logger.debug("S3 handler completed")
            event.sendResponse(data: Data())
            
        case .sns(let snsHandler):
            logger.debug("Starting SNS handler")
            let snsEvent = try JSONDecoder().decode(SNSEvent.self, from: event.payload.body)
            try await snsHandler.handleEvent(context: context, event: snsEvent)
            logger.debug("SNS handler completed")
            event.sendResponse(data: Data())
            
        case .dynamodb(let dynamodbHandler):
            logger.debug("Starting DynamoDB handler")
            let dynamodbEvent = try JSONDecoder().decode(DynamoDBEvent.self, from: event.payload.body)
            try await dynamodbHandler.handleEvent(context: context, event: dynamodbEvent)
            logger.debug("DynamoDB handler completed")
            event.sendResponse(data: Data())
            
        case .basicVoid(let basicVoidHandler):
            logger.debug("Starting EventBridge handler")
            let eventString = String(data: event.payload.body, encoding: .utf8) ?? ""
            try await basicVoidHandler.handleEvent(context: context, event: eventString)
            logger.debug("EventBridge handler completed")
            event.sendResponse(data: Data())
            
        case .apiGateway(let apiGatewayHandler):
            logger.debug("Starting API Gateway V1 handler")
            let apiGatewayEvent = try JSONDecoder().decode(APIGatewayRequest.self, from: event.payload.body)
            let response = try await apiGatewayHandler.handleEvent(context: context, event: apiGatewayEvent)
            logger.debug("API Gateway V1 handler completed")
            let responseData = try JSONEncoder().encode(response)
            event.sendResponse(data: responseData)
            
        default:
            throw LambdaError(errorMessage: "Handler type not implemented yet")
        }
    }
}

/// Convenience extension for DynamoDB handler with generic type support
public extension LambdaApp {
    @discardableResult
    func addDynamoDBChangeCapture<T: Decodable>(key: String, type: T.Type, handler: @escaping (LambdaContext, [ChangeDataCapture<T>]) async throws -> Void) -> LambdaApp {
        return addDynamoDB(key: key) { context, event in
            let changes = event.records.compactMap { DynamoDBChangeEvent<T>(from: $0)?.change }
            try await handler(context, changes)
        }
    }
}

public extension LambdaApp {
    
    func run(handlerKey: String? = nil, logFactory: LogFactory? = nil, logLevel: Logger.Level?) {
        self.handlerKey = handlerKey
        if let factory = logFactory {
            self.logger = factory("lambda")
        }
        self.logger.logLevel = logLevel ?? .info
        self.logger.debug("Starting custom Lambda runtime")
        
        let runtime = LambdaRuntime(runAsync: true, logger: self.logger)
        runtime.eventHandler = self
        runtime.start()
        
        // Keep process alive without blocking main thread
        dispatchMain()
    }
}
