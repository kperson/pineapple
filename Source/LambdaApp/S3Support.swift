/// Convenience extensions for S3 event records
///
/// Provides helper properties for common S3 event type checks.
public extension S3Event.Record {
    
    /// Returns `true` if this is an object creation event
    ///
    /// Matches any of:
    /// - `ObjectCreated:Put`
    /// - `ObjectCreated:Post`
    /// - `ObjectCreated:Copy`
    /// - `ObjectCreated:CompleteMultipartUpload`
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = LambdaApp()
    ///     .addS3(key: "bucket-events") { context, event in
    ///         for record in event.records {
    ///             if record.isCreatedEvent {
    ///                 context.logger.info("New file: \(record.s3.object.key)")
    ///                 // Process new file...
    ///             }
    ///         }
    ///     } 
    /// ```
    var isCreatedEvent: Bool {
        return eventName.hasPrefix("ObjectCreated")
    }
    
    /// Returns `true` if this is an object deletion event
    ///
    /// Matches any of:
    /// - `ObjectRemoved:Delete`
    /// - `ObjectRemoved:DeleteMarkerCreated`
    ///
    /// ## Example
    ///
    /// ```swift
    /// let app = LambdaApp()
    ///     .addS3(key: "bucket-events") { context, event in
    ///         for record in event.records {
    ///             if record.isRemovedEvent {
    ///                 context.logger.info("Deleted file: \(record.s3.object.key)")
    ///                 // Clean up references...
    ///             }
    ///         }
    ///     }
    /// ```
    var isRemovedEvent: Bool {
        return eventName.hasPrefix("ObjectRemoved")
    }
    
}
