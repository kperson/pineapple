import Foundation


public protocol DynamoStreamRecordMeta {
    
    var awsRegion: String { get }
    var eventSourceARN: String { get }
    var eventID: String { get }
    var eventSource: String { get }
    
}

public protocol DynamoStreamBodyAttributes {
    
    var change: ChangeCapture<[String : Any]> { get }
    
}

public struct DynamoStreamRecord: DynamoStreamRecordMeta, DynamoStreamBodyAttributes, RecordsItem {
        
    public typealias Meta = DynamoStreamRecordMeta
    public typealias Body = DynamoStreamBodyAttributes
    
    public let change: ChangeCapture<[String : Any]>
    public let awsRegion: String
    public let eventSourceARN: String
    public let eventID: String
    public let eventSource: String
    public let approximateCreationDateTime: Date
    
    public init?(dict: [String : Any]) {
        print(dict)
        if
            let eventName = dict["eventName"] as? String,
            let eventSourceARN = dict["eventSourceARN"] as? String,
            let awsRegion = dict["awsRegion"] as? String,
            let eventID = dict["eventID"] as? String,
            let eventSource = dict["eventSource"] as? String,
            let dynamodb = dict["dynamodb"] as? [String : Any],
            let approximateCreationDateTimeDouble = dynamodb["ApproximateCreationDateTime"] as? Double
        {
            self.approximateCreationDateTime = Date(timeIntervalSince1970: approximateCreationDateTimeDouble)
            self.eventSourceARN = eventSourceARN
            self.awsRegion = awsRegion
            self.eventID = eventID
            self.eventSource = eventSource
            
            if let newImage = dynamodb["NewImage"] as? [String : Any], eventName == "INSERT" {
                self.change = .create(new: newImage)
            }
            else if let oldImage = dynamodb["OldImage"] as? [String : Any], eventName == "REMOVE" {
                self.change = .delete(old: oldImage)
            }
            else if let newImage = dynamodb["NewImage"] as? [String : Any], let oldImage = dynamodb["OldImage"] as? [String : Any] {
                self.change = .update(new: newImage, old: oldImage)
            }
            else {
                return nil
            }
        }
        else {
            return nil
        }
        
    }
    
    public var recordMeta: DynamoStreamRecordMeta { return self }
    public var recordBody: DynamoStreamBodyAttributes { return self }
    
    public static var recordsKey: String? {
        return "Records"
    }
    
}

public typealias DyanmoEventHandler = RecordsAppsEventHandler<DynamoStreamRecord, Void>

public extension LambdaApp {

    func addDynamoHandler(_ handlerKey: String, _ handler: DyanmoEventHandler) {
        self.addHandler(handlerKey, handler)
    }
    
    func addDynamoHandler(_ handlerKey: String, _ handler: @escaping DyanmoEventHandler.Handler) {
        self.addDynamoHandler(handlerKey, DyanmoEventHandler(handler))
    }
    
    func addDynamoBodyHandler(_ handlerKey: String, _ handler: @escaping DyanmoEventHandler.BodyHandler) {
        self.addDynamoHandler(handlerKey) { items in
            try await handler(items.bodyRecords())
        }
    }
    
}
