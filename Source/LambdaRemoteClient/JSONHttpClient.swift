import AsyncHttp
import Foundation


public struct JSONResponse {
    
    public let response: Response
    public let request: Request
    public let decoder: JSONDecoder
    private let treat400PlusAsError: Bool
    
    public init(request: Request, response: Response, decoder: JSONDecoder, treat400PlusAsError: Bool) {
        self.response = response
        self.request = request
        self.decoder = decoder
        self.treat400PlusAsError = treat400PlusAsError
    }
    
    public func extract<T: Decodable>(type: T.Type) throws -> T {
        if response.statusCode >= 400 && treat400PlusAsError {
            throw HttpFailure(request: request, response: response)
        }
        return try decoder.decode(T.self, from: response.body)
    }
    
    public func extractOptional<T: Decodable>(type: T.Type) throws -> T? {
        if response.statusCode == 404 {
            return nil
        }
        return try extract(type: type)
    }
    
    public func void() throws {
        if response.statusCode >= 400 && treat400PlusAsError {
            throw HttpFailure(request: request, response: response)
        }
        return Void()
    }
    
    public func requestResponse() throws -> Response {
        if response.statusCode >= 400 && treat400PlusAsError {
            throw HttpFailure(request: request, response: response)
        }
        return response
    }
    
    public func requestResponseOptional() throws -> Response? {
        if response.statusCode == 404 {
            return nil
        }
        return try requestResponse()
    }
    
}

public struct HttpFailure: Error {

    public let request: Request
    public let response: Response
    
    public init(request: Request, response: Response) {
        self.request = request
        self.response = response
    }
    
}

public class JSONHttpClient {
        
    public static let sharedHttpClient = HttpClient()
    public let httpClient: HttpClient
    public let baseURL: String
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder
    private let treat400PlusAsError: Bool
    public var transformRequest: (Request) -> Request = { $0 }

    public init(
        baseURL: String,
        httpClient: HttpClient = JSONHttpClient.sharedHttpClient,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        treat400PlusAsError: Bool = true
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.encoder = encoder
        self.decoder = decoder
        self.treat400PlusAsError = treat400PlusAsError
    }
    
    public func get(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:]
    ) async throws -> JSONResponse {
        return try await fetch(method: .GET, path: path, queryParams: queryParams, headers: headers)
    }

    public func post<T: Encodable>(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: T
    ) async throws -> JSONResponse {
        let json = try encoder.encode(body)
        return try await fetch(method: .POST, path: path, queryParams: queryParams, headers: headers, body: json)
    }
    
    public func delete<T: Encodable>(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: T
    ) async throws -> JSONResponse {
        let json = try encoder.encode(body)
        return try await fetch(method: .DELETE, path: path, queryParams: queryParams, headers: headers, body: json)
    }
    
    public func put<T: Encodable>(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: T
    ) async throws -> JSONResponse {
        let json = try encoder.encode(body)
        return try await fetch(method: .PUT, path: path, queryParams: queryParams, headers: headers, body: json)
    }
    
    public func patch<T: Encodable>(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: T
    ) async throws -> JSONResponse {
        let json = try encoder.encode(body)
        return try await fetch(method: .PATCH, path: path, queryParams: queryParams, headers: headers, body: json)
    }
    
    public func postData(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: Data
    ) async throws -> JSONResponse {
        return try await fetch(method: .POST, path: path, queryParams: queryParams, headers: headers, body: body)
    }
    
    public func deleteData(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: Data
    ) async throws -> JSONResponse {
        return try await fetch(method: .DELETE, path: path, queryParams: queryParams, headers: headers, body: body)
    }
    
    public func putData(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: Data
    ) async throws -> JSONResponse {
        return try await fetch(method: .PUT, path: path, queryParams: queryParams, headers: headers, body: body)
    }
    
    public func patchData(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: Data
    ) async throws -> JSONResponse {
        return try await fetch(method: .PATCH, path: path, queryParams: queryParams, headers: headers, body: body)
    }
    
    public func post(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:]
    ) async throws -> JSONResponse {
        return try await fetch(method: .POST, path: path, queryParams: queryParams, headers: headers)
    }
    
    public func delete(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:]
    ) async throws -> JSONResponse {
        return try await fetch(method: .DELETE, path: path, queryParams: queryParams, headers: headers)
    }
    
    public func put(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:]
    ) async throws -> JSONResponse {
        return try await fetch(method: .PUT, path: path, queryParams: queryParams, headers: headers)
    }
    
    public func patch(
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:]
    ) async throws -> JSONResponse {
        return try await fetch(method: .PATCH, path: path, queryParams: queryParams, headers: headers)
    }
    
    private func fetch(
        method: AsyncHttp.RequestMethod,
        path: String,
        queryParams: [String : String?] = [:],
        headers: [String : String] = [:],
        body: Data = Data()
    ) async throws -> JSONResponse {
        var hs = headers
        if !body.isEmpty {
            hs["Content-Type"] = "application/json"
        }
        let builder = RequestBuilder(method: method, url: fullURL(path: path))
        builder.addQueryParams(nameValues: queryParams)
        builder.addHeaders(fieldValues: hs)
        if !body.isEmpty {
            builder.body = body
        }
        let request = transformRequest(builder.build())
        let response = try await httpClient.fetch(request: request)
        return JSONResponse(
            request: request,
            response: response,
            decoder: decoder,
            treat400PlusAsError: treat400PlusAsError
        )
    }
    
    private func fullURL(path: String) -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base + "/" + cleanPath
    }

    
}
