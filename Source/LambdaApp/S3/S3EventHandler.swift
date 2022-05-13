import Foundation

public protocol S3RecordMeta {
    
    var eventSource: String { get }
    var eventTime: Date { get }
    var eventVersion: String { get }
    var awsRegion: String { get }
    var ownerIdPrincipalId: String { get }
    var userIdPrincipalId: String { get }
}

public protocol S3BodyAttributes {
    
    var eventName: String { get }
    var s3BucketName: String { get }
    var s3BucketArn: String { get }
    var s3ObjectKey: String { get }
    var s3ObjectSize: Int? { get }
    var s3ObjectETag: String? { get }
    var s3ObjectVersionId: String? { get }
    var s3ObjectSequencer: String { get }
    var eventClass: S3Record.S3EventClass { get }
}

public struct S3Record: S3RecordMeta, S3BodyAttributes, RecordsItem {
    
    public enum S3EventClass {
        case test
        case objectCreated
        case objectRemoved
        case objectRestore
        case replication
        case reducedRedundancyLostObject
        case lifecycleExpiration
        case lifecycleTransition
        case intelligentTiering
        case objectTagging
        case objectAcl
        
    }
        
    public typealias Meta = S3RecordMeta
    public typealias Body = S3BodyAttributes
    
    public let eventName: String
    public let s3BucketName: String
    public let s3BucketArn: String
    public let s3ObjectKey: String
    public let s3ObjectETag: String?
    public let s3ObjectSize: Int?
    
    public let awsRegion: String
    public let eventVersion: String
    public let eventSource: String
    public let eventTime: Date
    public let s3ObjectSequencer: String
    public let s3ObjectVersionId: String?
    public let ownerIdPrincipalId: String
    public let userIdPrincipalId: String
    public let eventClass: S3EventClass
    
    // https://docs.aws.amazon.com/AmazonS3/latest/userguide/notification-content-structure.html
    // doesn't tell you what is optional, but this is best I could find
    // Please report if something is missing

    public init?(dict: [String : Any]) {
        if
            let eventVersion = dict["eventVersion"] as? String,
            let eventName = dict["eventName"] as? String,
            let eventSource = dict["eventSource"] as? String,
            let awsRegion = dict["awsRegion"] as? String,
            let eventTimeStr = dict["eventTime"] as? String,
            let eventTime = SNSRecord.formatter.date(from: eventTimeStr),
            let s3 = dict["s3"] as? [String : Any],
            let bucketDict = s3["bucket"] as? [String : Any],
            let bucketName = bucketDict["name"] as? String,
            let bucketArn = bucketDict["arn"] as? String,
            let objectDict = s3["object"] as? [String : Any],
            let key = objectDict["key"] as? String,
            let sequencer = objectDict["sequencer"] as? String,
            let ownerIdentityDict = bucketDict["ownerIdentity"] as? [String : Any],
            let oPrincipalId = ownerIdentityDict["principalId"] as? String,
            let userIdentityDict = dict["userIdentity"] as? [String : Any],
            let uPrincipalId = userIdentityDict["principalId"] as? String
        {
            self.s3BucketName = bucketName
            self.s3BucketArn = bucketArn
            self.s3ObjectKey = key
            self.eventSource = eventSource
            self.eventTime = eventTime
            self.eventName = eventName
            self.awsRegion = awsRegion
            self.s3ObjectETag = objectDict["eTag"] as? String
            self.s3ObjectSequencer = sequencer
            self.eventVersion = eventVersion
            self.s3ObjectVersionId = objectDict["versionId"] as? String
            self.s3ObjectSize = objectDict["size"] as? Int
            self.ownerIdPrincipalId = oPrincipalId
            self.userIdPrincipalId = uPrincipalId
            
            if eventName.starts(with: "ObjectCreated:") {
                eventClass = .objectCreated
            }
            else if eventName.starts(with: "ObjectRemoved:") {
                eventClass = .objectRemoved
            }
            else if eventName.starts(with: "ObjectRestore:") {
                eventClass = .objectRestore
            }
            else if eventName.starts(with: "ReducedRedundancyLostObject") {
                eventClass = .reducedRedundancyLostObject
            }
            else if eventName.starts(with: "Replication:") {
                eventClass = .replication
            }
            else if eventName.starts(with: "LifecycleExpiration:") {
                eventClass = .lifecycleExpiration
            }
            else if eventName.starts(with: "LifecycleTransition") {
                eventClass = .lifecycleTransition
            }
            else if eventName.starts(with: "IntelligentTiering") {
                eventClass = .intelligentTiering
            }
            else if eventName.starts(with: "ObjectTagging:*") {
                eventClass = .objectTagging
            }
            else if eventName.starts(with: "ObjectAcl:") {
                eventClass = .objectAcl
            }
            else {
                eventClass = .test
            }
        }
        else {
            return nil
        }
        
    }
    
    public var recordMeta: S3RecordMeta { return self }
    public var recordBody: S3BodyAttributes { return self }
    
    public static var recordsKey: String? {
        return "Records"
    }

}


public typealias S3EventHandler = RecordsAppsEventHandler<S3Record, Void>

public extension LambdaApp {

    func addS3Handler(_ handlerKey: String, _ handler: S3EventHandler) {
        self.addHandler(handlerKey, handler)
    }
    
    func addS3Handler(_ handlerKey: String, _ handler: @escaping S3EventHandler.Handler) {
        self.addS3Handler(handlerKey, S3EventHandler(handler))
    }
    
    func addS3BodyHandler(_ handlerKey: String, _ handler: @escaping S3EventHandler.BodyHandler) {
        self.addS3Handler(handlerKey) { items in
            try await handler(items.bodyRecords())
        }
    }
    
}
