import Foundation
import Logging
import JSONValueCoding

// MARK: - MCP Server Builder

/// MCP (Model Context Protocol) Server for Lambda functions
///
/// MCPServer provides a fluent interface for building MCP-compliant servers that can handle:
/// - **Tools**: Execute functions with typed or untyped parameters
/// - **Resources**: Serve data with URI pattern matching
/// - **Prompts**: Generate conversation templates with typed arguments
///
/// ## Path Parameters
/// All handlers receive `pathParams` which contains parameters extracted from the URL route.
/// This enables multi-tenant applications where the same server handles different customers/tenants.
///
/// Example:
/// ```swift
/// // Route: "mcp" / "customers" / string("customerId") / "files"
/// // URL: "/mcp/customers/cust-123/files"
/// // pathParams.string("customerId") returns "cust-123"
///
/// let server = MCPServer()
///     .addTool("read_file", inputType: FileArgs.self) { context, input, pathParams in
///         let customerId = pathParams?.string("customerId") ?? "unknown"
///         // Tool operates on customer-specific data
///         return ["file": input.filename, "customer": customerId]
///     }
/// ```
///
/// ## Async Support
/// All handlers are async and can perform I/O operations like database queries,
/// API calls, and file operations without blocking.

public typealias InputWithSchema = JSONSchemaProvider & Decodable
public typealias OutputWithSchema = JSONSchemaProvider & Encodable

public class Server {
    
    private var tools: [String: ToolDefinition] = [:]
    private var resources: [String: ResourceDefinition] = [:]
    private var prompts: [String: PromptDefinition] = [:]
    
    public let logger: Logger
    
    private let jsonValueDecoder = JSONValueDecoder()
    private let jsonValueEncoder = JSONValueEncoder()
    private let jsonEncoder = JSONEncoder()
    
    
    public init(logger: Logger = Logger(label: "mcp-server")) {
        self.logger = logger
    }
    

    // MARK: - Tool Registration

    
    /// Registers a tool with typed parameters that returns rich content
    /// - Parameters:
    ///   - name: Tool name (must be unique)
    ///   - description: Optional tool description
    ///   - inputType: Codable type for tool arguments
    ///   - handler: Tool handler that returns MCPToolResult (text, image, audio, etc.)
    /// - Returns: Self for method chaining
    ///
    /// Example:
    /// ```swift
    /// server.addTool("generate_chart", inputType: ChartArgs.self) { context, input, pathParams in
    ///     let chartData = generateChart(input.data)
    ///     return .image(data: chartData, mimeType: "image/png")
    /// }
    /// ```
    public func addTool<T: InputWithSchema>(
        _ name: CustomStringConvertible,
        description: CustomStringConvertible,
        inputType: T.Type,
        handler: @escaping (ToolHandlerRequest<T>) async throws -> ToolHandlerResponse
    ) -> Server {
        let schema = inputType.jsonSchema

        // Wrap the rich content handler to return standard JSON
        let wrappedHandler: (MCPContext, JSONValue, Params?) async throws -> ToolCallResponse = { [unowned self] context, params, pathParams in
            let typedInput = try jsonValueDecoder.decode(inputType, from: params)
            var requestLogger = logger
            requestLogger[metadataKey: "mcpRequestId"] = "\(context.requestId)"
            requestLogger[metadataKey: "mcpMethod"] = "\(context.method)"
            let request = ToolHandlerRequest(
                context: context,
                input: typedInput,
                pathParams: pathParams,
                logger: requestLogger
            )
            let result = try await handler(request)
            let toolsResponseAsJsonValue = try jsonValueEncoder.encode(result)
            
            return ToolCallResponse(content: [toolsResponseAsJsonValue], structuredContent: nil)
        }
        
        let definition = ToolDefinition(
            signature: ToolSignature(
                name: name.description,
                description: description.description,
                inputSchema: schema,
                outputSchema: nil
            ),
            handler: wrappedHandler
        )
        tools[name.description] = definition
        return self
    }
    
    public func addTool<I: InputWithSchema, O: OutputWithSchema>(
        _ name: CustomStringConvertible,
        description: CustomStringConvertible,
        inputType: I.Type,
        outputType: O.Type,
        handler: @escaping (ToolHandlerRequest<I>) async throws -> O
    ) -> Server {
    
        // Wrap the rich content handler to return standard JSON
        let wrappedHandler: (MCPContext, JSONValue, Params?) async throws -> ToolCallResponse = { [unowned self] context, params, pathParams in
            let typedInput = try JSONValueDecoder().decode(inputType, from: params)
            
            var requestLogger = logger
            requestLogger[metadataKey: "mcpRequestId"] = "\(context.requestId)"
            requestLogger[metadataKey: "mcpMethod"] = "\(context.method)"
            let request = ToolHandlerRequest(
                context: context,
                input: typedInput,
                pathParams: pathParams,
                logger: requestLogger
            )
            let result = try await handler(request)
            
            // Encode for content array
            let resultAsJsonString = try String(
                data: jsonEncoder.encode(result),
                encoding: .utf8
            ) ?? "{}"
            let toolResponse = ToolHandlerResponse.text(resultAsJsonString)
            let toolsResponseAsJsonValue = try jsonValueEncoder.encode(toolResponse)
    
            let structuredContent = try jsonValueEncoder.encode(result)
            
            return ToolCallResponse(
                content: [toolsResponseAsJsonValue],
                structuredContent: structuredContent
            )
        }
        
        let inputSchema = inputType.jsonSchema
        let outputSchema = outputType.jsonSchema
        let definition = ToolDefinition(
            signature: ToolSignature(
                name: name.description,
                description: description.description,
                inputSchema: inputSchema,
                outputSchema: outputSchema
                
            ),
            handler: wrappedHandler
        )
        tools[name.description] = definition
        return self
    }
    
    // MARK: - Resource Registration
    
    /// Registers a resource with URI pattern matching
    /// - Parameters:
    ///   - uriPattern: URI pattern with parameters (e.g., "file://{customerId}/docs/{docId}")
    ///   - name: Optional resource name
    ///   - description: Optional resource description
    ///   - mimeType: Optional MIME type
    ///   - handler: Resource handler function
    ///     - context: MCP request context
    ///     - resourceParams: Parameters extracted from the resource URI pattern
    ///     - pathParams: Parameters extracted from the URL route (same as tools)
    /// - Returns: Self for method chaining
    public func addResource(
        _ uriPattern: CustomStringConvertible,
        name: CustomStringConvertible,
        description: CustomStringConvertible,
        mimeType: CustomStringConvertible,
        handler: @escaping (ResourceHandlerRequest) async throws -> ResourceHandlerResponse
    ) -> Server {
        let pattern = ResourcePattern(uriPattern.description)
        let definition = ResourceDefinition(
            signature: .init(
                pattern: pattern,
                name: name.description,
                description: description.description,
                mimeType: mimeType.description
            ),
            handler: handler
        )
        resources[uriPattern.description] = definition
        return self
    }
    
    // MARK: - Prompt Registration
    
    /// Registers a prompt with arguments
    /// - Parameters:
    ///   - name: Prompt name (must be unique)
    ///   - description: Optional prompt description
    ///   - arguments: Manual argument definitions
    ///   - handler: Prompt handler function that receives a PromptHandlerRequest
    /// - Returns: Self for method chaining
    ///
    /// Example:
    /// ```swift
    /// .addPrompt("code_review",
    ///     description: "Generate code review prompts",
    ///     arguments: [
    ///         PromptArgument(name: "code", description: "Code to review", required: true),
    ///         PromptArgument(name: "language", description: "Programming language")
    ///     ]
    /// ) { request in
    ///     let code = try request.argumentOrThrow("code")
    ///     let language = request.arguments.string("language") ?? "unknown"
    ///     let customerId = request.pathParams?.string("customerId") ?? "default"
    ///
    ///     return PromptHandlerResponse(messages: [
    ///         PromptMessage(role: "system", content: .text("Review this \(language) code for customer \(customerId)")),
    ///         PromptMessage(role: "user", content: .text(code))
    ///     ])
    /// }
    /// ```
    public func addPrompt(
        _ name: String,
        description: String? = nil,
        arguments: [PromptArgument] = [],
        handler: @escaping (PromptHandlerRequest) async throws -> PromptHandlerResponse
    ) -> Server {
        let definition = PromptDefinition(
            prompt: Prompt(name: name, description: description, arguments: arguments),
            handler: handler
        )
        prompts[name] = definition
        return self
    }
    
    // MARK: - Request Handling

    public func handleRequest(_ envelope: TransportEnvelope, pathParams: Params?, logger: Logger) async throws -> JSONValue {
        let request = envelope.mcpRequest
        let encoder = JSONValueEncoder()
        let context = MCPContext(
            requestId: request.id ?? .string("unknown"),
            method: request.method,
            logger: logger,
            metadata: envelope.metadata
        )
        do {
            switch request.method {
            case "initialize":
                let initResponse = try await handleInitialize(context)
                return try encoder.encode(initResponse)
            case "tools/list":
                let toolList = try await handleToolsList(context)
                return try encoder.encode(toolList)
            case "tools/call":
                let toolCall = try await handleToolsCall(request, context, pathParams)
                return try encoder.encode(toolCall)
            case "resources/list":
                let resourceList = try await handleResourcesList(context)
                return try encoder.encode(resourceList)
            case "resources/templates/list":
                let resourceList = try await handleResourcesTemplateList(context)
                return try encoder.encode(resourceList)
            case "resources/read":
                let resourceRead = try await handleResourcesRead(request, context, pathParams)
                return try encoder.encode(resourceRead)
            case "prompts/list":
                let promptsList = try await handlePromptsList(context)
                return try encoder.encode(promptsList)
            case "prompts/get":
                let promptGet = try await handlePromptsGet(request, context, pathParams)
                return try encoder.encode(promptGet)
            default:
                let error = MCPError(code: .methodNotFound, message: "Method not found")
                let errorRes = Response<String>.fromError(id: request.id, error: error)
                return try encoder.encode(errorRes)
            }
        } catch let error as MCPError {
            let errorRes = Response<String>.fromError(id: request.id, error: error)
            return try encoder.encode(errorRes)
        } catch let error {
            context.logger.log(level: .error, "Unhandled exception in MCP request error: \(error)")
            let errorRes = Response<String>.fromError(id: request.id, error: .init(code: MCPErrorCode.internalError, message: "Unhandled exception in MCP request"))
            return try encoder.encode(errorRes)
        }
    }
    
    public func handleRequest(_ envelope: TransportEnvelope, pathParams: Params?, logger: Logger) async throws -> Data {
        let response: JSONValue = try await handleRequest(envelope, pathParams: pathParams, logger: logger)
        return try jsonEncoder.encode(response)
    }
    
    // MARK: - Private Handler Methods
    
    private func handleInitialize(_ context: MCPContext) async throws -> Response<InitializeResponse> {
        let hasTools = !tools.isEmpty
        let hasPrompts = !prompts.isEmpty
        let hasResources = !resources.isEmpty
        let response = InitializeResponse(
            capabilities: Capabilities(
                tools: hasTools ? [:] : nil,
                resources: hasResources ? [:] : nil,
                prompts: hasPrompts ? [:] : nil
            ),
            serverInfo: ServerInfo(name: "Swift MCP Server", version: "1.0.0")
        )
        
        return Response(id: context.requestId, result: response)
    }
    
    private func handleToolsList(_ context: MCPContext) async throws -> Response<ToolsListResponse> {
        let toolInfos = tools.values.map { definition in
            ToolInfo(
                name: definition.signature.name,
                description: definition.signature.description,
                inputSchema: definition.signature.inputSchema,
                outputSchema: definition.signature.outputSchema
            )
        }
        
        let response = ToolsListResponse(tools: toolInfos)
        return Response(id: context.requestId, result: response)
    }
    
    private func handleToolsCall(
        _ request: Request,
        _ context: MCPContext,
        _ pathParams: Params?
    ) async throws -> Response<ToolCallResponse> {
        guard let params = request.params,
              let toolName = params["name"]?.string else {
            throw MCPError(code: .invalidParams, message: "Invalid params")
        }
        
        guard let toolDef = tools[toolName] else {
            throw MCPError(code: .methodNotFound, message: "Tool not found")
        }
        
        let arguments = params["arguments"] ?? JSONValue([:])
        
        let result = try await toolDef.handler(context, arguments, pathParams)
        return Response(id: request.id, result: result)
    }
    
    private func handleResourcesList(_ context: MCPContext) async throws -> Response<ResourcesListResponse> {
        let resourceInfos = resources.values
            .filter { def in def.signature.pattern.parameterNames.isEmpty }
            .map { def in
                ResourcesListResponse.StaticResource(
                    uri: def.signature.pattern.pattern,
                    name: def.signature.name,
                    description: def.signature.description,
                    mimeType: def.signature.mimeType
                )
            }
        
        let response = ResourcesListResponse(resources: resourceInfos)
        return Response(id: context.requestId, result: response)
    }
    
    private func handleResourcesTemplateList(_ context: MCPContext) async throws -> Response<ResourcesTemplateResponse> {
        let templates = resources.values
            .filter { def in !def.signature.pattern.parameterNames.isEmpty }
            .map { def in
                ResourcesTemplateResponse.Template(
                    uriTemplate: def.signature.pattern.pattern,
                    name: def.signature.name,
                    description: def.signature.description,
                    mimeType: def.signature.mimeType
                )
        }
        
        let response = ResourcesTemplateResponse(resourceTemplates: templates)
        return Response(id: context.requestId, result: response)
    }
    
    private func handleResourcesRead(
        _ request: Request,
        _ context: MCPContext,
        _ pathParams: Params?
    ) async throws -> Response<ResourceReadResponse> {
        guard let params = request.params, let uri = params["uri"]?.string else {
            throw MCPError(code: .invalidParams, message: "Invalid params")
        }
        // Find matching resource pattern
        for (_, resourceDef) in resources {
            
            if let resourceParams = resourceDef.signature.pattern.match(uri) {
            
                let resourceRequest = ResourceHandlerRequest(
                    pathParams: pathParams,
                    resourceParams: resourceParams,
                    context: context
                )
                let handlerResponse = try await resourceDef.handler(resourceRequest)
                let response = ResourceResponse(handlerResponse: handlerResponse, mimeType: resourceDef.signature.mimeType)
                let resource = Resource(uri: uri, response: response)
                let readResponse = ResourceReadResponse(contents: [resource])
                return Response(id: request.id, result: readResponse)
            }
        }
        throw MCPError(code: .methodNotFound, message: "Resource not found")
    }
    
    private func handlePromptsList(_ context: MCPContext) async throws -> Response<PromptsListResponse> {
        let promptInfos = prompts.values.map { definition in
            PromptInfo(
                name: definition.prompt.name,
                description: definition.prompt.description ?? "",
                arguments: definition.prompt.arguments?.map { arg in
                    PromptArgumentInfo(
                        name: arg.name,
                        description: arg.description ?? "",
                        required: arg.required ?? false
                    )
                } ?? []
            )
        }
        
        let response = PromptsListResponse(prompts: promptInfos)
        return Response(id: context.requestId, result: response)
    }
    
    private func handlePromptsGet(_ request: Request, _ context: MCPContext, _ pathParams: Params?) async throws -> Response<PromptGetResponse> {
        guard let params = request.params,
              let promptName = params["name"]?.string else {
            throw MCPError(code: .invalidParams, message: "Invalid params")
        }

        guard let promptDef = prompts[promptName] else {
            throw MCPError(code: .methodNotFound, message: "Prompt not found")
        }

        let argumentsJson = params["arguments"] ?? JSONValue([:])
        let arguments = try Params(argumentsJson)

        // Create request-scoped logger with metadata
        var requestLogger = logger
        requestLogger[metadataKey: "mcpRequestId"] = "\(context.requestId)"
        requestLogger[metadataKey: "mcpMethod"] = "\(context.method)"

        // Construct the prompt handler request
        let promptRequest = PromptHandlerRequest(
            context: context,
            arguments: arguments,
            pathParams: pathParams,
            logger: requestLogger
        )

        // Call the handler and extract messages from response
        let handlerResponse = try await promptDef.handler(promptRequest)
        let messageInfos = handlerResponse.messages.map { message in
            PromptMessageInfo(
                role: message.role.rawValue,
                content: message.content
            )
        }

        let response = PromptGetResponse(
            description: promptDef.prompt.description ?? "",
            messages: messageInfos
        )
        return Response(id: request.id, result: response)
    }
}
