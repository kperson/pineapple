// DynamoDB-specific change data capture implementation with generic type support
public struct DynamoDBChangeEvent<T: Decodable> {
       
    public let change: ChangeDataCapture<T>
    private let decoder = DynamoDBEvent.Decoder()
    
    public init?(from record: DynamoDBEvent.EventRecord) {
        switch record.eventName {
        case .insert:
            
            guard let newImage = record.change.newImage,
                  let decoded = try? decoder.decode(T.self, from: newImage) else { return nil }
            self.change = .create(new: decoded)
        case .remove:
            guard let oldImage = record.change.oldImage,
                  let decoded = try? decoder.decode(T.self, from: oldImage) else { return nil }
            self.change = .delete(old: decoded)
        case .modify:
            guard let newImage = record.change.newImage,
                  let oldImage = record.change.oldImage,
                  let newDecoded = try? decoder.decode(T.self, from: newImage),
                  let oldDecoded = try? decoder.decode(T.self, from: oldImage) else { return nil }
            self.change = .update(new: newDecoded, old: oldDecoded)
        }
    }
}

