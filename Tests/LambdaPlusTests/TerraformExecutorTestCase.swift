import Foundation
import XCTest
import LambdaPlus

class TerraformExecutorTestCase: XCTestCase {


    func testSNSTopicText() {
        let executor = TerraformExecutor()
        print(executor.snsTopicText(t: .init(name: "abc", isFifo: true)))
    }

}
