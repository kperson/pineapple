/// DynamoDB-specific change data capture implementation with automatic type conversion
///
/// Converts DynamoDB Stream event records into strongly-typed `ChangeDataCapture` events.
/// This struct handles the complexity of:
/// - DynamoDB's AttributeValue format
/// - Stream record structure (newImage/oldImage)
/// - Type-safe decoding with automatic filtering of invalid records
///
/// ## Automatic Filtering
///
/// Records that fail to decode to type `T` return `nil` from the initializer.
/// This is intentional and allows processing heterogeneous DynamoDB tables where
/// not all records match your expected schema.
///
/// ## Usage
///
/// This type is used internally by `.addDynamoDBChangeCapture()` but can also
/// be used directly for custom processing:
///
/// ```swift
/// let app = LambdaApp()
///     .addDynamoDB(key: "raw-stream") { context, event in
///         // Manual processing with DynamoDBChangeEvent
///         for record in event.records {
///             if let changeEvent = DynamoDBChangeEvent<UserRecord>(from: record) {
///                 // Process typed change
///                 handleChange(changeEvent.change)
///             } else {
///                 context.logger.debug("Skipping record: \(record.eventID)")
///             }
///         }
///     }
/// ```
///
/// ## Stream View Requirements
///
/// - **INSERT**: Requires `newImage` in stream record (NEW_IMAGE or NEW_AND_OLD_IMAGES view)
/// - **MODIFY**: Requires both `newImage` and `oldImage` (NEW_AND_OLD_IMAGES view)
/// - **REMOVE**: Requires `oldImage` (OLD_IMAGE or NEW_AND_OLD_IMAGES view)
///
/// Records missing required images will be filtered out (initializer returns `nil`).
public struct DynamoDBChangeEvent<T: Decodable> {
    
    /// The typed change event (create, update, or delete)
    public let change: ChangeDataCapture<T>
    
    /// DynamoDB AttributeValue decoder (converts DynamoDB format to Swift types)
    private let decoder = DynamoDBEvent.Decoder()
    
    /// Create a typed change event from a DynamoDB Stream record
    ///
    /// Returns `nil` if:
    /// - Required image (newImage/oldImage) is missing for the event type
    /// - Image fails to decode to type `T`
    ///
    /// - Parameter record: DynamoDB Stream event record
    /// - Returns: Typed change event, or `nil` if record cannot be processed
    public init?(from record: DynamoDBEvent.EventRecord) {
        switch record.eventName {
        case .insert:
            // INSERT requires newImage
            guard let newImage = record.change.newImage,
                  let decoded = try? decoder.decode(T.self, from: newImage) else { return nil }
            self.change = .create(new: decoded)
            
        case .remove:
            // REMOVE requires oldImage
            guard let oldImage = record.change.oldImage,
                  let decoded = try? decoder.decode(T.self, from: oldImage) else { return nil }
            self.change = .delete(old: decoded)
            
        case .modify:
            // MODIFY requires both newImage and oldImage
            guard let newImage = record.change.newImage,
                  let oldImage = record.change.oldImage,
                  let newDecoded = try? decoder.decode(T.self, from: newImage),
                  let oldDecoded = try? decoder.decode(T.self, from: oldImage) else { return nil }
            self.change = .update(new: newDecoded, old: oldDecoded)
        }
    }
}

