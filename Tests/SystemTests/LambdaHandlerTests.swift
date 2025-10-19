import XCTest
import SystemTestsCommon
import SotoDynamoDB
import SotoSQS
import SotoS3
import SotoSNS
import SotoCore
import NIOCore
import Foundation

/// Integration tests for Lambda function event processing.
/// 
/// These tests verify that deployed Lambda functions correctly process various AWS events
/// and record verification data in DynamoDB. The tests use RemoteVerify to coordinate
/// between test execution and Lambda function processing.
/// 
/// Required environment variables:
/// - `AWS_PROFILE`: AWS profile for authentication
/// - `TEST_RUN_KEY`: Unique identifier for this test run (matches Lambda environment)
/// - `VERIFY_TABLE`: DynamoDB table name for verification data
/// - `TEST_SQS_QUEUE_URL`: SQS queue URL for SQS integration tests
/// - `TEST_SNS_TOPIC_ARN`: SNS topic ARN for SNS integration tests
/// - `TEST_API_ENDPOINT`: API Gateway endpoint for HTTP integration tests
final class LambdaHandlerTests: XCTestCase {
    
    private var client: AWSClient!
    private var sqs: SotoSQS.SQS!
    private var s3: SotoS3.S3!
    private var sns: SotoSNS.SNS!
    private var dynamo: SotoDynamoDB.DynamoDB!
    private var verifier: RemoteVerify!
    
    override func setUp() async throws {
        // Support profile injection via AWS_PROFILE environment variable
        let profile = ProcessInfo.processInfo.environment["AWS_PROFILE"]
        client = AWSClient(
            credentialProvider: profile.map { .configFile(profile: $0) } ?? .default
        )
        sqs = SotoSQS.SQS(client: client)
        s3 = SotoS3.S3(client: client)
        sns = SotoSNS.SNS(client: client)
        dynamo = SotoDynamoDB.DynamoDB(client: client)
        
        guard let verifyTable = ProcessInfo.processInfo.environment["VERIFY_TABLE"] else {
            throw XCTSkip("VERIFY_TABLE environment variable required for integration tests")
        }
        
        guard let testRunKey = ProcessInfo.processInfo.environment["TEST_RUN_KEY"] else {
            throw XCTSkip("TEST_RUN_KEY environment variable required for integration tests")
        }
        
        verifier = RemoteVerify(dynamoDB: dynamo, namespace: testRunKey, tableName: verifyTable)
    }
    
    override func tearDown() async throws {
        try await client.shutdown()
    }
    
    /// Tests SQS message processing integration.
    /// 
    /// This test sends a message to the SQS queue and verifies that the Lambda function
    /// processes it correctly by checking for verification data in DynamoDB that matches
    /// the exact message content.
    func testSQSIntegration() async throws {
        guard let queueUrl = ProcessInfo.processInfo.environment["TEST_SQS_QUEUE_URL"] else {
            throw XCTSkip("TEST_SQS_QUEUE_URL environment variable required")
        }
        
        _ = try await sqs.purgeQueue(SotoSQS.SQS.PurgeQueueRequest(queueUrl: queueUrl))
        
        let result = try await verifier.checkWithValue(test: "sqs") { key in
            let demoMessage = DemoMessage(message: key)
            let messageBody = try demoMessage.jsonStr()
            _ = try await sqs.sendMessage(SotoSQS.SQS.SendMessageRequest(
                messageBody: messageBody,
                queueUrl: queueUrl
            ))
        }

        XCTAssertTrue(result)
    }
    
    /// Tests S3 object event processing integration.
    /// 
    /// This test uploads a file to the S3 bucket and verifies that the Lambda function
    /// processes the S3 event correctly by checking for verification data in DynamoDB
    /// that matches the uploaded object key.
    func testS3CreateIntegration() async throws {
        guard let bucketName = ProcessInfo.processInfo.environment["TEST_S3_BUCKET"] else {
            throw XCTSkip("TEST_S3_BUCKET environment variable required")
        }
        
        let result = try await verifier.checkWithValue(test: "s3-create") { key in
            let content = "S3 test content for \(key)"
            let buffer = ByteBuffer(string: content)
            _ = try await s3.putObject(SotoS3.S3.PutObjectRequest(
                body: AWSHTTPBody(buffer: buffer),
                bucket: bucketName,
                key: key
            ))
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests S3 object deletion event processing integration.
    /// 
    /// This test creates and then deletes a file from the S3 bucket and verifies that 
    /// the Lambda function processes the S3 delete event correctly by checking for 
    /// verification data in DynamoDB that matches the deleted object key.
    func testS3DeletionIntegration() async throws {
        guard let bucketName = ProcessInfo.processInfo.environment["TEST_S3_BUCKET"] else {
            throw XCTSkip("TEST_S3_BUCKET environment variable required")
        }
        
        let result = try await verifier.checkWithValue(test: "s3-delete") { key in
            // First create the object
            let content = "S3 deletion test content for \(key)"
            let buffer = ByteBuffer(string: content)
            _ = try await s3.putObject(SotoS3.S3.PutObjectRequest(
                body: AWSHTTPBody(buffer: buffer),
                bucket: bucketName,
                key: key
            ))
            
            // Then delete it to trigger the delete event
            _ = try await s3.deleteObject(SotoS3.S3.DeleteObjectRequest(
                bucket: bucketName,
                key: key
            ))
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests SNS (Simple Notification Service) message processing integration.
    /// 
    /// This test publishes a message to an SNS topic and verifies that the Lambda function
    /// processes the SNS event correctly by checking for verification data in DynamoDB
    /// that matches the published message content.
    func testSNSIntegration() async throws {
        guard let topicArn = ProcessInfo.processInfo.environment["TEST_SNS_TOPIC_ARN"] else {
            throw XCTSkip("TEST_SNS_TOPIC_ARN environment variable required")
        }
        
        // Use checkWithValue to generate a unique message and verify it was processed
        let result = try await verifier.checkWithValue(test: "sns", numAttempts: 60) { message in
            // Publish message to SNS topic
            let publishRequest = SNS.PublishInput(
                message: message,
                topicArn: topicArn
            )
            
            _ = try await sns.publish(publishRequest)
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests DynamoDB Streams CREATE event processing.
    /// 
    /// This test creates a new item in DynamoDB and verifies the Lambda function
    /// processes the INSERT stream event correctly.
    func testDynamoDBCreateIntegration() async throws {
        guard let testTable = ProcessInfo.processInfo.environment["TEST_TABLE"] else {
            throw XCTSkip("TEST_TABLE environment variable required")
        }
        
        struct TestItem: Codable {
            let id: String
            let data: String
        }
        
        let encoder = DynamoDBEncoder()
        
        let result = try await verifier.checkWithValue(test: "dynamo-create") { key in
            let item = TestItem(id: key, data: "test-data")
            let putRequest = DynamoDB.PutItemInput(
                item: try encoder.encode(item),
                tableName: testTable
            )
            _ = try await dynamo.putItem(putRequest)
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests DynamoDB Streams UPDATE event processing.
    /// 
    /// This test creates an item then updates it, verifying the Lambda function
    /// processes the MODIFY stream event correctly.
    func testDynamoDBUpdateIntegration() async throws {
        guard let testTable = ProcessInfo.processInfo.environment["TEST_TABLE"] else {
            throw XCTSkip("TEST_TABLE environment variable required")
        }
        
        struct TestItem: Codable {
            let id: String
            let data: String
        }
        
        let encoder = DynamoDBEncoder()
        
        let result = try await verifier.checkWithValue(test: "dynamo-update") { key in
            // Create initial item
            let item = TestItem(id: key, data: "initial-data")
            let putRequest = DynamoDB.PutItemInput(
                item: try encoder.encode(item),
                tableName: testTable
            )
            _ = try await dynamo.putItem(putRequest)
            
            // Update the item to trigger MODIFY event
            let updateRequest = DynamoDB.UpdateItemInput(
                expressionAttributeNames: ["#data": "data"],
                expressionAttributeValues: [":newdata": .s("updated-data")],
                key: ["id": .s(key)],
                tableName: testTable,
                updateExpression: "SET #data = :newdata"
            )
            _ = try await dynamo.updateItem(updateRequest)
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests DynamoDB Streams DELETE event processing.
    /// 
    /// This test creates an item then deletes it, verifying the Lambda function
    /// processes the REMOVE stream event correctly.
    func testDynamoDBDeleteIntegration() async throws {
        guard let testTable = ProcessInfo.processInfo.environment["TEST_TABLE"] else {
            throw XCTSkip("TEST_TABLE environment variable required")
        }
        
        struct TestItem: Codable {
            let id: String
            let data: String
        }
        
        let encoder = DynamoDBEncoder()
        
        let result = try await verifier.checkWithValue(test: "dynamo-delete") { key in
            // Create item first
            let item = TestItem(id: key, data: "test-data")
            let putRequest = DynamoDB.PutItemInput(
                item: try encoder.encode(item),
                tableName: testTable
            )
            _ = try await dynamo.putItem(putRequest)
            
            // Delete the item to trigger REMOVE event
            let deleteRequest = DynamoDB.DeleteItemInput(
                key: ["id": .s(key)],
                tableName: testTable
            )
            _ = try await dynamo.deleteItem(deleteRequest)
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests EventBridge (CloudWatch Events) scheduled event processing.
    /// 
    /// This test verifies that the Lambda function triggered by EventBridge cron events
    /// correctly processes the events and records verification data in DynamoDB.
    /// The test waits for existing verification data rather than triggering new events.
     func testEventBridgeIntegration() async throws {
         let result = try await verifier.check(test: "eventbridge", numAttempts: 60)
         XCTAssertTrue(result)
     }
    
    /// Tests API Gateway HTTP request processing integration.
    /// 
    /// This test sends an HTTP request to the API Gateway endpoint and verifies that 
    /// the Lambda function processes it correctly by checking for verification data 
    /// in DynamoDB that matches the request path.
    func testHTTPIntegration() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["TEST_API_ENDPOINT"] else {
            throw XCTSkip("TEST_API_ENDPOINT environment variable required")
        }
        
        let result = try await verifier.checkWithValue(test: "http") { key in
            let url = URL(string: "\(endpoint)/\(key)")!
            let (_, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                XCTFail("HTTP request failed")
                return
            }
        }
        
        XCTAssertTrue(result)
    }
    
    /// Tests the RemoteVerify save and check pattern.
    /// 
    /// This test verifies the basic functionality of the RemoteVerify system by
    /// saving verification data directly and then checking for its existence.
    /// This simulates the pattern used by Lambda functions and tests.
    func testRemoteVerifyCheckPattern() async throws {
        let test = "test-key-\(UUID().uuidString)"
    
        // Test save and fetch cycle
        let result = try await verifier.checkWithValue(test: test) { value in
            try await verifier.save(test: test, value: value)
        }
        
        XCTAssertTrue(result)
    }

}
