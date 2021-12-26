// Generated using Sourcery 1.6.1 — https://github.com/krzysztofzablocki/Sourcery
// DO NOT EDIT
//  LambdaRemoteEventCopy.generated.swift
//

extension LambdaRemoteEvent {
	// A default style constructor for the .copy fn to use
	init(
		requestId: String,
		namespaceKey: String,
		payloadCreatedAt: Int64,
		request: LambdaRemoteRequest,
		response: LambdaRemoteResponse?,
		// This is to prevent overriding the default init if it exists already
		forCopyInit: Void? = nil
	) {
		self.requestId = requestId
		self.namespaceKey = namespaceKey
		self.payloadCreatedAt = payloadCreatedAt
		self.request = request
		self.response = response
	}

	// struct copy, lets you overwrite specific variables retaining the value of the rest
	// using a closure to set the new values for the copy of the struct
	public func copy(_ build: (inout Builder) -> Void) -> LambdaRemoteEvent {
		var builder = Builder(original: self)
		build(&builder)
		return builder.toLambdaRemoteEvent()
	}

	public struct Builder {
		public var requestId: String
		public var namespaceKey: String
		public var payloadCreatedAt: Int64
		public var request: LambdaRemoteRequest
		public var response: LambdaRemoteResponse?

		fileprivate init(original: LambdaRemoteEvent) {
			self.requestId = original.requestId
			self.namespaceKey = original.namespaceKey
			self.payloadCreatedAt = original.payloadCreatedAt
			self.request = original.request
			self.response = original.response
		}

		fileprivate func toLambdaRemoteEvent() -> LambdaRemoteEvent {
			return LambdaRemoteEvent(
				requestId: requestId, 
				namespaceKey: namespaceKey, 
				payloadCreatedAt: payloadCreatedAt, 
				request: request, 
				response: response
			)
		}
	}

}
