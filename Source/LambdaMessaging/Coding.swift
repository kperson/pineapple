import Foundation

public protocol Encode {
    
    associatedtype In
    associatedtype Out
    
    func encode(input: In) throws -> Out
    
}

public protocol Decode {
    
    associatedtype In
    associatedtype Out
    
    func decode(input: In) throws -> Out
    
}

public class JSONEncode<In: Encodable>: Encode {
    
    public typealias Out = Data
    
    let encoder: JSONEncoder
        
    public init(encoder: JSONEncoder?) {
        self.encoder = encoder ?? JSONEncoder()
    }
    
    public func encode<In: Encodable>(input: In) throws -> Data  {
        try encoder.encode(input)
    }
    
}

public class JSONDecode<Out: Decodable>: Decode {
    
    public typealias In = Data
    
    let decoder: JSONDecoder
    
    public init(decoder: JSONDecoder?) {
        self.decoder = decoder ?? JSONDecoder()
    }
    
    public func decode(input: Data) throws -> Out {
        try decoder.decode(Out.self, from: input)
    }
    
}

class Demo {
    
    enum Topics: String {
        case valueAsString
    }
    
    func abc()  {
        
//        
//        let aws = AWSI(app: LambdaApp())
//        let stringTopic = aws.pubSub.getTopic(.managed(.init(name: "strToTopic")))
//        let intTopic = aws.pubSub.getTopic(.managed(.init(name: "converToint")))
//
//        let intWriter = intTopic.writer(type: Int.self, envName: "INT_WRITER_TOPIC")
//                
//        let stringToIntLambda = stringTopic.reader(type: String.self, functionName: "converToint")
//        let intPrintLambda = intTopic.reader(type: Int.self, functionName: "intReader")
//            
//        stringToIntLambda.compactMap { str in Int(str) }.sink(write: intWriter)
//        intPrintLambda.forEach { print($0) }
    }
    
}
