public extension S3Event.Record {
    
    var isCreatedEvent: Bool {
        return eventName.hasPrefix("ObjectCreated")
    }
    
    var isRemovedEvent: Bool {
        return eventName.hasPrefix("ObjectRemoved")
    }
    
}
