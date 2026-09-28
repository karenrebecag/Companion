import CompanionCore
import Foundation

/// Cheap vision sidecar: JPEG in, SUMMARY + SNIPPETS out. The voice model
/// never sees the image.
public struct ScreenVision: Sendable {
    private let secrets: any SecretStore
    private let transport: any ChatTransport
    private let model: String

    public init(
        secrets: any SecretStore,
        transport: any ChatTransport,
        model: String = "gpt-4o-mini"
    ) {
        self.secrets = secrets
        self.transport = transport
        self.model = model
    }

    public func summarize(jpeg: Data, app: String?) async -> ScreenBrief? {
        guard let text = await complete(
            jpeg: jpeg, prompt: Self.prompt(app: app), maxTokens: 400, timeout: 8)
        else { return nil }
        return ScreenBriefParser.parse(text)
    }

    /// The `see` tool: the window's own text, not the sidecar's 50 words.
    /// The reply is the transcription itself, so it skips the SUMMARY parser.
    public func transcribe(jpeg: Data, app: String?, question: String?) async -> ScreenBrief? {
        guard let text = await complete(
            jpeg: jpeg, prompt: ScreenSeePrompt.prompt(app: app, question: question),
            maxTokens: ScreenSeePrompt.maxTokens, timeout: ScreenSeePrompt.visionTimeout)
        else { return nil }
        let bounded = ScreenSeePrompt.bound(text)
        return bounded.isEmpty ? nil : ScreenBrief(summary: bounded)
    }

    private func complete(jpeg: Data, prompt: String, maxTokens: Int, timeout: TimeInterval) async -> String? {
        if Task.isCancelled { return nil }
        let key: String
        do {
            guard let read = try secrets.read(.openAI), !read.isEmpty else { return nil }
            key = read
        } catch {
            return nil
        }
        guard let url = ProviderDescriptor.openAI.endpoint,
              EndpointPolicy.isAcceptable(url) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let b64 = jpeg.base64EncodedString()
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(b64)"],
                    ],
                ],
            ]],
        ]
        let encoded: Data
        do {
            encoded = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return nil
        }
        request.httpBody = encoded
        do {
            let (data, response) = try await transport.data(for: request)
            guard response.statusCode == 200 else { return nil }
            if Task.isCancelled { return nil }
            return Self.content(from: data)
        } catch {
            Log.app("sight: vision request failed (\(error))")
            return nil
        }
    }

    static func prompt(app: String?) -> String {
        let hint = app.map { "Frontmost app (hint): \($0).\n" } ?? ""
        return hint
            + "Look at this Mac screenshot. Report only what is visibly readable. "
            + "Do not guess, infer intent, or invent names.\n"
            + "Reply exactly:\n"
            + "SUMMARY: <at most 50 words>\n"
            + "SNIPPETS:\n"
            + "[App] \"verbatim fragment\"\n"
            + "Up to 12 snippets, each at most 10 words, copied exactly. "
            + "If the screen is unreadable: SUMMARY: unreadable"
    }

    static func content(from data: Data) -> String? {
        let obj: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.app("sight: vision decode failed (not an object)")
                return nil
            }
            obj = parsed
        } catch {
            Log.app("sight: vision decode failed (\(error))")
            return nil
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String
        else { return nil }
        return text
    }
}
