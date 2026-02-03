import Foundation

/// Generic change data capture abstraction for stream events
///
/// Represents the three types of changes that can occur in a data stream:
/// - **create**: New record inserted
/// - **update**: Existing record modified (provides both old and new versions)
/// - **delete**: Record removed
///
/// ## Usage with DynamoDB Streams
///
/// ```swift
/// struct UserRecord: Codable {
///     let userId: String
///     let email: String
/// }
///
/// let app = LambdaApp()
///     .addDynamoDBChangeCapture(key: "user-stream", type: UserRecord.self) { context, changes in
///         for change in changes {
///             switch change {
///             case .create(let user):
///                 context.logger.info("New user: \(user.userId)")
///
///             case .update(let new, let old):
///                 context.logger.info("Updated user \(new.userId): \(old.email) → \(new.email)")
///
///             case .delete(let user):
///                 context.logger.info("Deleted user: \(user.userId)")
///             }
///         }
///     }
/// ```
///
/// This enum automatically filters out records that fail to decode to type `T`,
/// making it safe to use with heterogeneous tables.
public enum ChangeDataCapture<T> {
    /// A new record was inserted
    /// - Parameter new: The newly created record
    case create(new: T)
    
    /// An existing record was modified
    /// - Parameters:
    ///   - new: The updated record
    ///   - old: The previous version of the record
    case update(new: T, old: T)
    
    /// A record was deleted
    /// - Parameter old: The deleted record (as it existed before deletion)
    case delete(old: T)
}

