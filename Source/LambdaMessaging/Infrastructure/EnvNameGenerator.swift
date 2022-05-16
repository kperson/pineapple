import Foundation

public class EnvNameGenerator {
     
    private class EnvByTypeLookup {
        
        private var cache: [ObjectIdentifier : String] = [:]
        
        public init() { }
        
        func byObjectId(_ id: ObjectIdentifier, _ customize: (Int) -> String) -> String {
            if let cached = cache[id] {
                return cached
            }
            let newValue = customize(cache.count)
            cache[id] = newValue
            return newValue
        }
        
    }
    
    private var cache: [String : EnvByTypeLookup] = [:]
    
    public func topicWriterEnv(ref: PubSubRef) -> String {
        let typeStr = String(describing: type(of: ref))
        let lookup = cache[typeStr, default: EnvByTypeLookup()]
        defer {
            cache[typeStr] = lookup
        }
        let id = ObjectIdentifier(ref)
        return lookup.byObjectId(id) { ct in
            "SNS_TOPIC_\(typeStr.uppercased())_\(ct)_ARN"
        }
    }

}
