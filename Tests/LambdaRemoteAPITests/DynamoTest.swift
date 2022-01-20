import XCTest
import SotoDynamoDB
@testable import LambdaRemoteAPI

class DynamoTest: XCTestCase {
    
    static let containerName = "dynamo-local-test-container"
    
    override class func setUp() {
        super.setUp()
        removeContainers()
        startContainers()
        Thread.sleep(forTimeInterval: 2)
    }
    
    override class func tearDown() {
        super.tearDown()
        removeContainers()
        try? Self.client.syncShutdown()
    }
    
    class func startContainers() {
        shell("\(docker) run --rm -d --name=\(containerName) -p \(testingPort):8000 amazon/dynamodb-local")
    }
    
    class func removeContainers() {
        shell("\(docker) rm -f \(containerName)")
    }
    
    static private var docker: String {
         ProcessInfo.processInfo.environment["DOCKER_EXECUTABLE"] ?? "/usr/local/bin/docker"
    }
    
    static var testingPort: Int {
        Int(ProcessInfo.processInfo.environment["TESTING_PORT"] ?? "8049") ?? 8049
    }
    
    static var testingHost: String {
        ProcessInfo.processInfo.environment["TESTING_HOST"] ?? "localhost"
    }
    
    static var endpointUrl: String {
        "http://\(testingHost):\(testingPort)"
    }
    
    static let client: AWSClient = AWSClient(
        credentialProvider: .default,
        httpClientProvider: .createNew
    )
        
    var dynamo: DynamoDB {
        return DynamoDB(
            client: Self.client,
            partition: .aws,
            endpoint: Self.endpointUrl
        )
    }

    
    @discardableResult private static func shell(_ command: String, traceId: String? = nil) -> (Bool, String) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        try! task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        task.waitUntilExit()
        let exitStatus = task.terminationStatus
        return (exitStatus == 0, output)
    }
    
}
