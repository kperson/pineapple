import Foundation

public enum LazyValue<T> {
    
    case value(T)
    case computed(() -> T)
    
    public var materialValue: T {
        switch self {
        case .value(let t): return t
        case .computed(let function): return function()
        }
    }
    
}


public class LazyEnv {
    
    static func envStr(_ key: String) -> LazyValue<String> {
        .computed { ProcessInfo.processInfo.environment[key]! }
    }
    
    static func envOptStr(_ key: String) -> LazyValue<String?> {
        .computed { ProcessInfo.processInfo.environment[key] }
    }
    
}
