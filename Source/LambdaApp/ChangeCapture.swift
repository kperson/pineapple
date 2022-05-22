import Foundation

public enum ChangeCapture<T> {
    
    case create(new: T)
    case update(new: T, old: T)
    case delete(old: T)
    
    public func map<New>(_ f: (T) throws -> New) rethrows -> ChangeCapture<New> {
        switch self {
        case .create(new: let n): return .create(new: try f(n))
        case .update(new: let n, old: let o): return .update(new: try f(n), old: try f(o))
        case .delete(old: let o): return .delete(old: try f(o))
        }
    }
    
}

public protocol ChangeCapturey {
    
    associatedtype T
    var change: ChangeCapture<T> { get }

}

extension ChangeCapture: ChangeCapturey {
    public var change: ChangeCapture<T> { return self }
}


public extension Array where Element: ChangeCapturey {
    
    var creates: [Element.T] {
        return compactMap { i in
            switch i.change {
            case .create(new: let n): return n
            default: return nil
            }
        }
    }
    
    var deletes: [Element.T] {
        return compactMap { i in
            switch i.change {
            case .delete(old: let o): return o
            default: return nil
            }
        }
    }
    
    var updates: [(new: Element.T, old: Element.T)] {
        return compactMap { i in
            switch i.change {
            case .update(new: let n, old: let o): return (new: n, old: o)
            default: return nil
            }
        }
    }
    
}
