import Foundation
import LambdaApp
import SotoDynamoDB
import SystemTestsCommon

// this works better for cloud watch
func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    print(items, separator: separator, terminator: terminator)
    fflush(stdout)
}

// This is an app shows how to use tooling and test the tooling
let app = LambdaApp(enviromentVariable: "MY_HANDLER")


let client = AWSClient(httpClientProvider: .createNew)
let dynamo = DynamoDB(client: client)
let verifyTable = ProcessInfo.processInfo.environment["VERIFY_TABLE"]!


// when an environment variable of MY_HANDLER=test.sqs, this code will run
app.addSQSHandler("test.sqs") { records in
    for r in records {
        log(r)
        if let testRunKey = r.body.messageAttributes["testRunKey"]?.stringValue {
            let verifer = RemoteVerify(dynamoDB: dynamo, testRunKey: testRunKey, tableName: verifyTable)
            try await verifer.save(key: "messageBody", value: r.body.body)
        }
        if let testRunKeyBinary = r.body.messageAttributes["testRunKeyAsBinary"]?.binaryValue {
            let testRunKey = String(data: testRunKeyBinary, encoding: .utf8)!
            let verifer = RemoteVerify(dynamoDB: dynamo, testRunKey: testRunKey, tableName: verifyTable)
            try await verifer.save(key: "messageBodyBinary", value: r.body.body)
        }
    
    }
}

app.runtime.start()
