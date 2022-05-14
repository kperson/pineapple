import Foundation
import SotoS3
import XCTest
import SystemTestsCommon


class S3TestCase: RemoteTestCase {
    
    let bucket = "pineapple-test"
    let s3 = S3(client: AWSClient(httpClientProvider: .createNew))
    
    func testCreateAndDelete() async throws {
        let key = "\(verifier.testRunKey)-create.txt"
        let request = S3.PutObjectRequest(body: .string("hello world"), bucket: bucket, key: key)
        _ = try await s3.putObject(request)
        if let messageCreate = try await verifier.retrieveOrFail(
            key: "objectCreated",
            failureMessage: "Lambda did not set objectCreated receipt in time"
        ) {
            XCTAssertEqual(key, messageCreate)
        }
        _ = try await s3.deleteObject(.init(bucket: bucket, key: key))
        
        if let messageRemove = try await verifier.retrieveOrFail(
            key: "objectRemoved",
            failureMessage: "Lambda did not set objectRemoved receipt in time"
        ) {
            XCTAssertEqual(key, messageRemove)
        }
        
    }
    
}
