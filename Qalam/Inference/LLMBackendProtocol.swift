import Foundation

protocol LLMBackend: Sendable {
    func complete(
        prompt: String,
        model: String,
        maxTokens: Int,
        temperature: Double,
        stop: [String]
    ) -> AsyncThrowingStream<String, Error>
}
