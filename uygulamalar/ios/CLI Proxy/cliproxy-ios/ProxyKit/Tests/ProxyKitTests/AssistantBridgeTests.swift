import Foundation
import Testing
@testable import ProxyKit

@Suite struct AssistantBridgeTests {
    @Test(arguments: ["low", "medium", "high"])
    func claudeEffortSurvivesCanonicalConversion(_ effort: String) async throws {
        let transport = MockTransport()
        transport.onSSE(urlContains: "api.anthropic.com/v1/messages", Fixtures.anthropicSSE)
        let engine = try await makeEngine(sampleState(), transport)
        let body: JSON = ["model": "claude-opus-5-5", "reasoning_effort": .string(effort),
                          "messages": [["role": "user", "content": "Selam"]]]
        let result = await engine.handle(post("/v1/chat/completions", String(data: try body.data(), encoding: .utf8)!))
        #expect(result.status == 200)
        _ = try await collectString(result)
        let request = try #require(transport.requests(containing: "anthropic.com").first)
        #expect(request.jsonBody["output_config"]?["effort"] == .string(effort))
    }

    @Test func openAIToolRequestsUseResponses() async throws {
        let transport = MockTransport()
        transport.onSSE(urlContains: "api.openai.com/v1/responses", Fixtures.responsesSSE)
        let engine = try await makeEngine(sampleState(), transport)
        let result = await engine.handle(post("/v1/messages", #"{"model":"gpt-6.1-sol","output_config":{"effort":"low"},"max_tokens":1000,"stream":true,"messages":[{"role":"user","content":"Saat?"}],"tools":[{"name":"saat","input_schema":{"type":"object","properties":{}}}]}"#))
        #expect(result.status == 200)
        let output = try await collectString(result)
        #expect(output.contains("Selam"))
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/v1/responses")
        #expect(request.jsonBody["tools"]?[0]?["name"] == "saat")
        #expect(request.jsonBody["max_output_tokens"] == 1000)
        #expect(request.jsonBody["store"] == false)
        #expect(request.jsonBody["reasoning"]?["effort"] == "low")
    }

    @Test func geminiSignatureSurvivesAnthropicRoundTrip() throws {
        let cache = GeminiSignatureCache()
        var decoder = GeminiDecoder { id, sig in cache.save(model: "gemini-test", id: id, signature: sig) }
        var parser = SSEParser()
        let source = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"saat\",\"args\":{}},\"thoughtSignature\":\"opaque-test-signature\"}]}}]}\n\n"
        var id = ""
        for event in parser.feed(Data(source.utf8)) {
            for value in try decoder.decode(event) { if case .toolStart(_, let callID, _) = value { id = callID } }
        }
        #expect(!id.isEmpty)
        let input: JSON = ["model": "gemini-test", "messages": [
            ["role": "assistant", "content": [["type": "tool_use", "id": .string(id), "name": "saat", "input": [:]]]],
            ["role": "user", "content": [["type": "tool_result", "tool_use_id": .string(id), "content": "09:00"]]]
        ]]
        let canonical = try Inbound.anthropic(input)
        let body = Antigravity.body(canonical, model: "gemini-test", thinking: nil, project: "test",
                                   signatures: cache.signatures(model: "gemini-test", ids: [id]))
        #expect(body["request"]?["contents"]?[0]?["parts"]?[0]?["thoughtSignature"] == "opaque-test-signature")
        #expect(cache.signatures(model: "different-model", ids: [id]).isEmpty)
        for n in 0..<257 { cache.save(model: "gemini-test", id: "\(n)", signature: "test") }
        #expect(cache.signatures(model: "gemini-test", ids: [id]).isEmpty)
    }
}
