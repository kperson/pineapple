import Foundation

/// Generic change data capture abstraction for stream events
public enum ChangeDataCapture<T> {
    case create(new: T)
    case update(new: T, old: T)
    case delete(old: T)
}

