import Foundation

struct OllamaBackend: LLMBackend {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(
        prompt: String,
        model: String,
        maxTokens: Int = Constants.Suggestion.maxTokens,
        temperature: Double = Constants.Suggestion.temperature,
        stop: [String] = ["\n\n", "###"]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Constants.Ollama.generateURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    let body: [String: Any] = [
                        "model": model,
                        "prompt": prompt,
                        "stream": true,
                        // CRITICAL: disable "thinking". Reasoning models (Gemma 4,
                        // Qwen 3, etc.) otherwise emit ALL their output into a
                        // separate `thinking` channel and leave `response` empty —
                        // which looked like "the model produces nothing / garbage".
                        // With think:false they answer directly, and it's also far
                        // faster (no hidden reasoning tokens) — exactly what inline
                        // autocomplete needs. Harmless for non-thinking models.
                        "think": false,
                        // Keep the model resident for 30 min so quick bursts of
                        // typing don't pay the multi-second cold-reload cost
                        // every time (Ollama unloads after 5 min by default).
                        "keep_alive": "30m",
                        "options": [
                            "temperature": temperature,
                            "num_predict": maxTokens,
                            "stop": stop,
                        ],
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        throw NSError(
                            domain: "Qalam.Ollama",
                            code: http.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(http.statusCode)"]
                        )
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if let token = obj["response"] as? String, !token.isEmpty {
                            continuation.yield(token)
                        }
                        if let done = obj["done"] as? Bool, done { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
