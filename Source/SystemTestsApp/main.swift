import Foundation
import LambdaApp

// this works better for cloud watch
func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    print(items, separator: separator, terminator: terminator)
    fflush(stdout)
}

// This is an app shows how to use tooling and test the tooling
let app = LambdaApp(enviromentVariable: "MY_HANDLER")

// when an environment variable of MY_HANDLER=test.sqs, this code will run
app.addSQSBodyHandler("test.sqs") { records in
    log(records)
}

app.runtime.start()
