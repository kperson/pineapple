import Foundation
import XCTest
import SotoDynamoDB
import Vapor
import AsyncHttp
@testable import LambdaRemoteAPI


class ProxyTest: DynamoTest {

    let tableName = "testtable"
    private var app: Application?
    
    override func setUp() async throws {
        try await super.setUp()
        _ = try await dynamo.createTable(.init(
            attributeDefinitions: [
                .init(attributeName: "payloadCreatedAt", attributeType: .n),
                .init(attributeName: "requestId", attributeType: .s),
                .init(attributeName: "namespaceKey", attributeType: .s)
            ],
            globalSecondaryIndexes: [
                .init(
                    indexName: "requestIdIndex",
                    keySchema: [.init(attributeName: "requestId", keyType: .hash)],
                    projection: .init(nonKeyAttributes: nil, projectionType: .all),
                    provisionedThroughput: .init(readCapacityUnits: 1, writeCapacityUnits: 1)
                )
            ],
            keySchema: [
                .init(attributeName: "namespaceKey", keyType: .hash),
                .init(attributeName: "payloadCreatedAt", keyType: .range)
            ],
            provisionedThroughput: .init(readCapacityUnits: 1, writeCapacityUnits: 1),
            tableName: tableName
        ))
        if app == nil {
            app = try! Application(.detect())
            let proxyApp = App(
                vaporApp: app!,
                dynamo: dynamo,
                port: 8080,
                table: tableName
            )
            proxyApp.configureRoutes()
            try app!.start()
        }
    }
    
    override class func setUp() {
        super.setUp()
    
    }
    
    override func tearDown() async throws {
        _ = try await dynamo.deleteTable(.init(tableName: tableName))
        app?.shutdown()
    }

}
