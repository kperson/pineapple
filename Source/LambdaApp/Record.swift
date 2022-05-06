import Foundation

public struct Record<Meta, Body> {

    public let meta: Meta
    public let body: Body

    public init(meta: Meta, body: Body) {
        self.meta = meta
        self.body = body
    }

    public func map<NewBody>(_ f: (Body) throws -> NewBody) rethrows -> Record<Meta, NewBody> {
        return Record<Meta, NewBody>(meta: meta, body: try f(body))
    }

}

public extension Array  {

    func mapBody<NewBody, Meta, Body>(
        _ f: (Body) throws -> NewBody
    ) rethrows -> [Record<Meta, NewBody>] where Element == Record<Meta, Body> {
        return try map {
            let newBody = try f($0.body)
            return Record(meta: $0.meta, body: newBody)
        }
    }

    func filterBody<Meta, Body>(
        _ f: (Body) throws -> Bool
    ) rethrows -> [Record<Meta, Body>] where Element == Record<Meta, Body> {
        return try filter  { try f($0.body) }
    }
    
    func flatMapBody<NewBody, Meta, Body>(
        _ f: (Body) throws -> [NewBody]
    ) rethrows -> [Record<Meta, NewBody>] where Element == Record<Meta, Body> {
        return try flatMap { r in
            try f(r.body).map { newBody in
                return Record(meta: r.meta, body: newBody)
            }
        }
    }
    
    func compactMapBody<NewBody, Meta, Body>(
        _ f: (Body) throws -> NewBody?
    ) rethrows -> [Record<Meta, NewBody>] where Element == Record<Meta, Body> {
        return try compactMap {
            if let newBody = try f($0.body) {
                return Record(meta: $0.meta, body: newBody)
            }
            return nil
        }
    }
}
