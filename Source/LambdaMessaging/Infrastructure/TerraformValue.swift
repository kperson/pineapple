import Foundation


public enum TerraformValue<T: Hashable & Equatable>: Hashable, Equatable {
    case literal(T)
    case interpolate(T)
}
