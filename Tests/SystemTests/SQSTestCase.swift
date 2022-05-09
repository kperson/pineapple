import Foundation
import XCTest


class SQSTestCase: RemoteTestCase {
    
        
    func testHello() async throws {
        try await verifier.save(key: "hello", value: "hello_world")
        
        if let rs = try await verifier.fetch(key: "hello") {
            print(rs)
        }
    }
    
    
}
