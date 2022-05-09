import Foundation


public protocol SNSRecordMeta {
    
    var eventSource: String { get }
    var eventSubscriptionArn: String { get }
    var unsubscribeUrl: String { get }
    var timestamp: Date { get }
    var message: String { get }
    var topicArn: String { get }
    var subject: String? { get }
    
}

public protocol SNSBodyAttributes {
    
    var message: String { get }
    
}

public struct SNSRecord: SNSRecordMeta, SNSBodyAttributes, RecordsItem {
    
            
    public typealias Meta = SNSRecordMeta
    public typealias Body = SNSBodyAttributes
    
    static func createDateFormatter() -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        return dateFormatter
    }
    
    public static let formatter = createDateFormatter()
    
    public let eventSource: String
    public let eventSubscriptionArn: String
    public let unsubscribeUrl: String
    public let timestamp: Date
    public let message: String
    public let topicArn: String
    public let messageId: String
    public let subject: String?
    
    public init?(dict: [String : Any]) {
        if
            let eventSource = dict["EventSource"] as? String,
            let eventSubscriptionArn = dict["EventSubscriptionArn"] as? String,
            let snsDict = dict["Sns"] as? [String : Any],
            let unsubscribeUrl = snsDict["UnsubscribeUrl"] as? String,
            let timestampStr = snsDict["Timestamp"] as? String,
            let timestamp = SNSRecord.formatter.date(from: timestampStr),
            let message = snsDict["Message"] as? String,
            let topicArn = snsDict["TopicArn"] as? String,
            let messageId = snsDict["MessageId"] as? String

        {
            self.eventSource = eventSource
            self.eventSubscriptionArn = eventSubscriptionArn
            self.unsubscribeUrl = unsubscribeUrl
            self.timestamp = timestamp
            self.message = message
            self.topicArn = topicArn
            self.messageId = messageId
            self.subject = snsDict["Subject"] as? String
        }
        else {
            return nil
        }
    }
    
    public static var recordsKey: String? {
        return "Records"
    }
    
    public var recordMeta: SNSRecordMeta { return self }
    public var recordBody: SNSBodyAttributes { return self }

}


public typealias SNSEventHandler = RecordsAppsEventHandler<SNSRecord, Void>

public extension LambdaApp {

    func addSNSHandler(_ handlerKey: String, _ handler: SNSEventHandler) {
        addHandler(handlerKey, handler)
    }
    
    func addSNSHandler(_ handlerKey: String, _ handler: @escaping SNSEventHandler.Handler) {
        addSNSHandler(handlerKey, SNSEventHandler(handler))
    }
    
    func addSNSBodyHandler(_ handlerKey: String, _ handler: @escaping SNSEventHandler.BodyHandler) {
        addSNSHandler(handlerKey) { items in
            try await handler(items.bodyRecords())
        }
    }
    
}
