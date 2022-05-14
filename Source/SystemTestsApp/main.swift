import Foundation
import LambdaApp
import SotoDynamoDB
import SystemTestsCommon


// This is an app shows how to use tooling and test the tooling
let app = LambdaApp(enviromentVariable: "MY_HANDLER")

let client = AWSClient(httpClientProvider: .createNew)
let dynamo = DynamoDB(client: client)
if let verifyTable = ProcessInfo.processInfo.environment["VERIFY_TABLE"] {

    // when an environment variable of MY_HANDLER=test.sqs, this code will run
    app.addSQSHandler("test.sqs") { records in
        for r in records {
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

    app.addSNSHandler("test.sns") { records in
        for r in records {
            let msg = try DemoMessage(jsonStr: r.body.message)
            let verifer = RemoteVerify(dynamoDB: dynamo, testRunKey: msg.testRunKey, tableName: verifyTable)
            try await verifer.save(key: "messageBody", value: msg.jsonStr())
        }
    }

    app.addS3Handler("test.s3") { records in
        for r in records {
            if let keySubStr = r.body.s3ObjectKey.split(separator: "-").first {
                let verifyKey = String(keySubStr)
                let verifer = RemoteVerify(dynamoDB: dynamo, testRunKey: verifyKey, tableName: verifyTable)
                if r.body.eventClass == .objectCreated {
                    try await verifer.save(key: "objectCreated", value: r.body.s3ObjectKey)
                }
                else if r.body.eventClass == .objectRemoved {
                    try await verifer.save(key: "objectRemoved", value: r.body.s3ObjectKey)
                }
            }
        }
    }
    
    app.addDynamoHandler("test.dynamo") { records in
        func extractVerifyKey(_ dict: [String : Any]) -> String {
            if let key = dict["verifyKey"] as? [String : Any], let value = key["S"] as? String {
                return value
            }
            return ""
        }
        for r in records {
            switch r.body.change {
            case .create(new: let n):
                let verifier = RemoteVerify(dynamoDB: dynamo, testRunKey: extractVerifyKey(n), tableName: verifyTable)
                try await verifier.save(key: "new", value: verifier.testRunKey)
            case .update(new: let n, old: _):
                let verifier = RemoteVerify(dynamoDB: dynamo, testRunKey: extractVerifyKey(n), tableName: verifyTable)
                try await verifier.save(key: "update", value: verifier.testRunKey)
            case .delete(old: let o):
                let verifier = RemoteVerify(dynamoDB: dynamo, testRunKey: extractVerifyKey(o), tableName: verifyTable)
                try await verifier.save(key: "delete", value: verifier.testRunKey)
            }
        }
    }
    
    app.addApiGateway("test.http") { request in
        HTTPResponse(
            statusCode: 200,
            body: "hello_word".data(using: .utf8),
            headers: ["Content-Type" :  "text/plain"]
        )
    }
    
    app.runtime.start()
}
