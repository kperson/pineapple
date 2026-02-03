import Testing
import SystemTestsCommon
import SotoDynamoDB
import SotoSQS
import SotoS3
import SotoSNS
import SotoCore
import NIOCore
import Foundation

/// Check if required environment variables for system tests are present
private let systemTestsEnabled: Bool = {
    ProcessInfo.processInfo.environment["VERIFY_TABLE"] != nil &&
    ProcessInfo.processInfo.environment["TEST_RUN_KEY"] != nil
}()

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
@Suite("Lambda Handler Integration Tests", .enabled(if: systemTestsEnabled))
struct LambdaHandlerTests {

    /// Test resources container that manages AWS client lifecycle
    struct TestResources {
        let client: AWSClient
        let sqs: SotoSQS.SQS
        let s3: SotoS3.S3
        let sns: SotoSNS.SNS
        let dynamo: SotoDynamoDB.DynamoDB
        let verifier: RemoteVerify

        init(verifyTable: String, testRunKey: String) {
            let profile = ProcessInfo.processInfo.environment["AWS_PROFILE"]
            self.client = AWSClient(
                credentialProvider: profile.map { .configFile(profile: $0) } ?? .default
            )
            self.sqs = SotoSQS.SQS(client: client)
            self.s3 = SotoS3.S3(client: client)
            self.sns = SotoSNS.SNS(client: client)
            self.dynamo = SotoDynamoDB.DynamoDB(client: client)
            self.verifier = RemoteVerify(dynamoDB: dynamo, namespace: testRunKey, tableName: verifyTable)
        }

        func shutdown() async throws {
            try await client.shutdown()
        }
    }

    /// Creates test resources and runs a test closure, ensuring cleanup
    func withResources<T>(_ test: (TestResources) async throws -> T) async throws -> T {
        // These are guaranteed to be present due to suite-level .enabled(if:) check
        let verifyTable = ProcessInfo.processInfo.environment["VERIFY_TABLE"]!
        let testRunKey = ProcessInfo.processInfo.environment["TEST_RUN_KEY"]!

        let resources = TestResources(verifyTable: verifyTable, testRunKey: testRunKey)
        defer {
            Task {
                try? await resources.shutdown()
            }
        }

        return try await test(resources)
    }

    // MARK: - SQS Tests

    /// Tests SQS message processing integration.
    ///
    /// This test sends a message to the SQS queue and verifies that the Lambda function
    /// processes it correctly by checking for verification data in DynamoDB that matches
    /// the exact message content.
    @Test("SQS message processing")
    func sqsIntegration() async throws {
        try await withResources { resources in
            let queueUrl = try #require(
                ProcessInfo.processInfo.environment["TEST_SQS_QUEUE_URL"],
                "TEST_SQS_QUEUE_URL environment variable required"
            )

            _ = try await resources.sqs.purgeQueue(SotoSQS.SQS.PurgeQueueRequest(queueUrl: queueUrl))

            let result = try await resources.verifier.checkWithValue(test: "sqs") { key in
                let demoMessage = DemoMessage(message: key)
                let messageBody = try demoMessage.jsonStr()
                _ = try await resources.sqs.sendMessage(SotoSQS.SQS.SendMessageRequest(
                    messageBody: messageBody,
                    queueUrl: queueUrl
                ))
            }

            #expect(result)
        }
    }

    // MARK: - S3 Tests

    /// Tests S3 object event processing integration.
    ///
    /// This test uploads a file to the S3 bucket and verifies that the Lambda function
    /// processes the S3 event correctly by checking for verification data in DynamoDB
    /// that matches the uploaded object key.
    @Test("S3 object creation event processing")
    func s3CreateIntegration() async throws {
        try await withResources { resources in
            let bucketName = try #require(
                ProcessInfo.processInfo.environment["TEST_S3_BUCKET"],
                "TEST_S3_BUCKET environment variable required"
            )

            let result = try await resources.verifier.checkWithValue(test: "s3-create") { key in
                let content = "S3 test content for \(key)"
                let buffer = ByteBuffer(string: content)
                _ = try await resources.s3.putObject(SotoS3.S3.PutObjectRequest(
                    body: AWSHTTPBody(buffer: buffer),
                    bucket: bucketName,
                    key: key
                ))
            }

            #expect(result)
        }
    }

    /// Tests S3 object deletion event processing integration.
    ///
    /// This test creates and then deletes a file from the S3 bucket and verifies that
    /// the Lambda function processes the S3 delete event correctly by checking for
    /// verification data in DynamoDB that matches the deleted object key.
    @Test("S3 object deletion event processing")
    func s3DeletionIntegration() async throws {
        try await withResources { resources in
            let bucketName = try #require(
                ProcessInfo.processInfo.environment["TEST_S3_BUCKET"],
                "TEST_S3_BUCKET environment variable required"
            )

            let result = try await resources.verifier.checkWithValue(test: "s3-delete") { key in
                // First create the object
                let content = "S3 deletion test content for \(key)"
                let buffer = ByteBuffer(string: content)
                _ = try await resources.s3.putObject(SotoS3.S3.PutObjectRequest(
                    body: AWSHTTPBody(buffer: buffer),
                    bucket: bucketName,
                    key: key
                ))

                // Then delete it to trigger the delete event
                _ = try await resources.s3.deleteObject(SotoS3.S3.DeleteObjectRequest(
                    bucket: bucketName,
                    key: key
                ))
            }

            #expect(result)
        }
    }

    // MARK: - SNS Tests

    /// Tests SNS (Simple Notification Service) message processing integration.
    ///
    /// This test publishes a message to an SNS topic and verifies that the Lambda function
    /// processes the SNS event correctly by checking for verification data in DynamoDB
    /// that matches the published message content.
    @Test("SNS message processing")
    func snsIntegration() async throws {
        try await withResources { resources in
            let topicArn = try #require(
                ProcessInfo.processInfo.environment["TEST_SNS_TOPIC_ARN"],
                "TEST_SNS_TOPIC_ARN environment variable required"
            )

            let result = try await resources.verifier.checkWithValue(test: "sns", numAttempts: 60) { message in
                let publishRequest = SNS.PublishInput(
                    message: message,
                    topicArn: topicArn
                )
                _ = try await resources.sns.publish(publishRequest)
            }

            #expect(result)
        }
    }

    // MARK: - DynamoDB Stream Tests

    /// Tests DynamoDB Streams CREATE event processing.
    ///
    /// This test creates a new item in DynamoDB and verifies the Lambda function
    /// processes the INSERT stream event correctly.
    @Test("DynamoDB Streams INSERT event processing")
    func dynamoDBCreateIntegration() async throws {
        try await withResources { resources in
            let testTable = try #require(
                ProcessInfo.processInfo.environment["TEST_TABLE"],
                "TEST_TABLE environment variable required"
            )

            struct TestItem: Codable {
                let id: String
                let data: String
            }

            let encoder = DynamoDBEncoder()

            let result = try await resources.verifier.checkWithValue(test: "dynamo-create") { key in
                let item = TestItem(id: key, data: "test-data")
                let putRequest = DynamoDB.PutItemInput(
                    item: try encoder.encode(item),
                    tableName: testTable
                )
                _ = try await resources.dynamo.putItem(putRequest)
            }

            #expect(result)
        }
    }

    /// Tests DynamoDB Streams UPDATE event processing.
    ///
    /// This test creates an item then updates it, verifying the Lambda function
    /// processes the MODIFY stream event correctly.
    @Test("DynamoDB Streams MODIFY event processing")
    func dynamoDBUpdateIntegration() async throws {
        try await withResources { resources in
            let testTable = try #require(
                ProcessInfo.processInfo.environment["TEST_TABLE"],
                "TEST_TABLE environment variable required"
            )

            struct TestItem: Codable {
                let id: String
                let data: String
            }

            let encoder = DynamoDBEncoder()

            let result = try await resources.verifier.checkWithValue(test: "dynamo-update") { key in
                // Create initial item
                let item = TestItem(id: key, data: "initial-data")
                let putRequest = DynamoDB.PutItemInput(
                    item: try encoder.encode(item),
                    tableName: testTable
                )
                _ = try await resources.dynamo.putItem(putRequest)

                // Update the item to trigger MODIFY event
                let updateRequest = DynamoDB.UpdateItemInput(
                    expressionAttributeNames: ["#data": "data"],
                    expressionAttributeValues: [":newdata": .s("updated-data")],
                    key: ["id": .s(key)],
                    tableName: testTable,
                    updateExpression: "SET #data = :newdata"
                )
                _ = try await resources.dynamo.updateItem(updateRequest)
            }

            #expect(result)
        }
    }

    /// Tests DynamoDB Streams DELETE event processing.
    ///
    /// This test creates an item then deletes it, verifying the Lambda function
    /// processes the REMOVE stream event correctly.
    @Test("DynamoDB Streams REMOVE event processing")
    func dynamoDBDeleteIntegration() async throws {
        try await withResources { resources in
            let testTable = try #require(
                ProcessInfo.processInfo.environment["TEST_TABLE"],
                "TEST_TABLE environment variable required"
            )

            struct TestItem: Codable {
                let id: String
                let data: String
            }

            let encoder = DynamoDBEncoder()

            let result = try await resources.verifier.checkWithValue(test: "dynamo-delete") { key in
                // Create item first
                let item = TestItem(id: key, data: "test-data")
                let putRequest = DynamoDB.PutItemInput(
                    item: try encoder.encode(item),
                    tableName: testTable
                )
                _ = try await resources.dynamo.putItem(putRequest)

                // Delete the item to trigger REMOVE event
                let deleteRequest = DynamoDB.DeleteItemInput(
                    key: ["id": .s(key)],
                    tableName: testTable
                )
                _ = try await resources.dynamo.deleteItem(deleteRequest)
            }

            #expect(result)
        }
    }

    // MARK: - EventBridge Tests

    /// Tests EventBridge (CloudWatch Events) scheduled event processing.
    ///
    /// This test verifies that the Lambda function triggered by EventBridge cron events
    /// correctly processes the events and records verification data in DynamoDB.
    /// The test waits for existing verification data rather than triggering new events.
    @Test("EventBridge scheduled event processing")
    func eventBridgeIntegration() async throws {
        try await withResources { resources in
            let result = try await resources.verifier.check(test: "eventbridge", numAttempts: 60)
            #expect(result)
        }
    }

    // MARK: - HTTP/API Gateway Tests

    /// Tests API Gateway HTTP request processing integration.
    ///
    /// This test sends an HTTP request to the API Gateway endpoint and verifies that
    /// the Lambda function processes it correctly by checking for verification data
    /// in DynamoDB that matches the request path.
    @Test("API Gateway HTTP request processing")
    func httpIntegration() async throws {
        try await withResources { resources in
            let endpoint = try #require(
                ProcessInfo.processInfo.environment["TEST_API_ENDPOINT"],
                "TEST_API_ENDPOINT environment variable required"
            )

            let result = try await resources.verifier.checkWithValue(test: "http") { key in
                let url = URL(string: "\(endpoint)/\(key)")!
                let (_, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    Issue.record("HTTP request failed")
                    return
                }
            }

            #expect(result)
        }
    }

    // MARK: - RemoteVerify Pattern Tests

    /// Tests the RemoteVerify save and check pattern.
    ///
    /// This test verifies the basic functionality of the RemoteVerify system by
    /// saving verification data directly and then checking for its existence.
    /// This simulates the pattern used by Lambda functions and tests.
    @Test("RemoteVerify save and check pattern")
    func remoteVerifyCheckPattern() async throws {
        try await withResources { resources in
            let test = "test-key-\(UUID().uuidString)"

            let result = try await resources.verifier.checkWithValue(test: test) { value in
                try await resources.verifier.save(test: test, value: value)
            }

            #expect(result)
        }
    }
}
