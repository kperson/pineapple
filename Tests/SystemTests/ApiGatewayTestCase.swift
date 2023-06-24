import Foundation
import SotoS3
import XCTest
import SystemTestsCommon
import LambdaApp


class ApiGatewayTestCase: RemoteTestCase {
    
    
    func testHTTP() async throws {
        var request = URLRequest(
            url: URL(string: ProcessInfo.processInfo.environment["HTTP_TEST_URL"]! + "/hello/world")!,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )
        request.httpMethod = "POST"
        request.httpBody = "hello world".data(using: .utf8)
        
        let session = URLSession.shared
        let data = try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request, completionHandler: { data, response, error -> Void in
                if let d = data {
                    continuation.resume(with: .success(d))
                }
                else if let err = error {
                    continuation.resume(with: .failure(err))
                }
            })
            task.resume()
        }
        let echoedRequest: HTTPRequest = try JSONDecoder().decode(HTTPRequest.self, from: data)
        XCTAssertEqual(echoedRequest.httpMethod, request.httpMethod)
        XCTAssertEqual(echoedRequest.path, "/hello/world")
        XCTAssertEqual(echoedRequest.body, request.httpBody)
    }
    
}
