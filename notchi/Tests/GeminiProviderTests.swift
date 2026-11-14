import Foundation
import XCTest
@testable import notchi

final class GeminiProviderTests: XCTestCase {
    func testProviderPropertiesAndVerbs() {
        XCTAssertEqual(AgentProvider.gemini.displayName, "Gemini")
        XCTAssertEqual(AgentProvider.gemini.spriteFamily, .gemini)
        XCTAssertEqual(SpinnerVerbs.providerVerb(for: .gemini), "Geminizing")
        XCTAssertEqual(NotchSlotContent.gemini.spriteProvider, .gemini)
        XCTAssertTrue(NotchSlotContent.gemini.isSprite)
    }

    func testGeminiAdapterNormalizesLifecycleAndMapsTools() throws {
        let adapter = GeminiProviderAdapter(directoryExists: { true }, hooksEnabled: { true })
        XCTAssertTrue(adapter.isProviderAvailable())
        XCTAssertTrue(adapter.isInstalled())

        let preToolJSON = """
        {
          "provider": "gemini",
          "session_id": "gem-1",
          "cwd": "/tmp/proj",
          "event": "PreToolUse",
          "status": "working",
          "tool": "read_file",
          "tool_use_id": "call-1",
          "model": "gemini-4-hydrogen",
          "gemini_process_id": 4242,
          "interactive": true
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(AgentHookEnvelope.self, from: preToolJSON)
        let event = try XCTUnwrap(adapter.normalize(envelope))

        XCTAssertEqual(event.provider, .gemini)
        XCTAssertEqual(event.event, .preToolUse)
        XCTAssertEqual(event.tool, "Read")
        XCTAssertEqual(event.modelId, "gemini-4-hydrogen")
        XCTAssertEqual(event.geminiProcessId, 4242)
    }

    func testGeminiPricingCatalogLoadsFallbackAndNormalizesGooglePrefix() {
        let catalog = PricingCatalog(config: .gemini, fallbackBundle: .main)
        XCTAssertNotNil(catalog.pricing(model: "gemini-4-hydrogen", on: Date()))
        XCTAssertNotNil(catalog.pricing(model: "google/gemini-2.5-pro", on: Date()))
    }

    func testCodexCostScannerWithGeminiFilterIgnoresNonGeminiAndScoresGemini() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gemini-scan-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let gemRollout = root.appendingPathComponent("rollout-gem.jsonl")
        let todayISO = ISO8601DateFormatter().string(from: Date())
        let lines = [
            "{\"timestamp\":\"\(todayISO)\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gemini-4-hydrogen\"}}",
            "{\"timestamp\":\"\(todayISO)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":1000,\"cached_input_tokens\":200,\"output_tokens\":100}}}}",
        ].joined(separator: "\n") + "\n"
        try lines.write(to: gemRollout, atomically: true, encoding: .utf8)

        let openAIRollout = root.appendingPathComponent("rollout-gpt.jsonl")
        let gptLines = [
            "{\"timestamp\":\"\(todayISO)\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-5\"}}",
            "{\"timestamp\":\"\(todayISO)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":5000,\"cached_input_tokens\":0,\"output_tokens\":500}}}}",
        ].joined(separator: "\n") + "\n"
        try gptLines.write(to: openAIRollout, atomically: true, encoding: .utf8)

        let catalog = PricingCatalog(config: .gemini, fallbackBundle: .main)
        let scanner = CodexCostScanner(
            projectsRoots: [root],
            pricing: catalog,
            windowDays: 30,
            calendar: .current,
            normalizeModel: CostPricing.normalizeGeminiModel,
            modelFilter: CostPricing.isGeminiModel
        )
        let updated = scanner.scan(
            cache: CostUsageCache(version: CostUsageCache.currentVersion, files: [:], buckets: [:]),
            now: Date()
        )
        let dayKey = DailyCostReport.dayKey(Date(), calendar: .current)
        let dayModels = try XCTUnwrap(updated.buckets[dayKey])

        XCTAssertNotNil(dayModels["gemini-4-hydrogen"])
        XCTAssertNil(dayModels["gpt-5"])
    }
}
