import Foundation

class Async {
    
    static func retryOptional<T>(
        seconds duration: TimeInterval,
        delayIncrease: Double,
        maxAttempts: UInt,
        _ f: () async throws -> T?) async rethrows -> T? {
        return try await retryOptional(
            f,
            delayNanoSeconds: UInt64(Double(duration) * 1_000_000_000),
            increase: delayIncrease,
            attemptCount: 0,
            maxAttempts: maxAttempts
        )
    }
    
    private static func retryOptional<T>(
        _ f: () async throws -> T?,
        delayNanoSeconds: UInt64,
        increase: Double,
        attemptCount: UInt,
        maxAttempts: UInt
    ) async rethrows -> T? {
        if delayNanoSeconds != 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoSeconds)
            }
            catch {
                //we don't return the task so the CancellationError is impossible
            }
        }
        if let result = try await f() {
            return result
        }
        else if attemptCount + 1 == maxAttempts {
            return nil
        }
        else {
            return try await retryOptional(
                f,
                delayNanoSeconds: UInt64(Double(delayNanoSeconds) * increase),
                increase: increase,
                attemptCount: attemptCount + 1,
                maxAttempts: maxAttempts
            )
        }
    }
    
}
