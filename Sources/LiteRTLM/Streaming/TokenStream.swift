import Foundation

/// A strongly-typed async sequence of generated tokens.
///
/// Wraps `AsyncThrowingStream<String, Error>` with additional metadata.
///
/// ```swift
/// let stream = session.generateStream("Hello")
/// for try await token in stream {
///     print(token, terminator: "")
/// }
/// ```
public struct TokenStream: AsyncSequence, Sendable {
    public typealias Element = String

    private let base: AsyncThrowingStream<String, Error>

    init(_ stream: AsyncThrowingStream<String, Error>) {
        self.base = stream
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var base: AsyncThrowingStream<String, Error>.AsyncIterator

        init(_ base: AsyncThrowingStream<String, Error>.AsyncIterator) {
            self.base = base
        }

        public mutating func next() async throws -> String? {
            try await base.next()
        }
    }

    /// Collect the full response into a single string.
    public func collect() async throws -> String {
        var result = ""
        for try await token in self {
            result += token
        }
        return result
    }
}
