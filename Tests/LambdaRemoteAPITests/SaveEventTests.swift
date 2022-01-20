import Foundation
import XCTest
import SotoDynamoDB
import Vapor
@testable import LambdaRemoteAPI
@testable import LambdaRemoteClient


class SaveEventTests: ProxyTest {

    func testNilRequestId404() async throws {
        let client = LambdaRemoteClient(baseURL: "http://localhost:8080")
        let requestId = UUID().uuidString
        let res = try await client.fetchEvent(requestId: requestId)
        XCTAssertNil(res)
    }
}
