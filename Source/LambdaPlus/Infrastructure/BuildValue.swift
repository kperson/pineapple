import Foundation


public enum BuildValue<T: Hashable & Equatable>: Hashable, Equatable {
    case literal(T)
    case ref(T)
}
