import Foundation
import XCTest
@testable import notchi

final class GeminiUsageReaderTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_794_694_000)

    func testReadsGeminiFiveHourAndWeeklyBucketsFromQuotaCache() throws {
        let json = """
        {
          "updatedAt": 1794693820762,
          "buckets": {
            "3p-5h": {
              "remaining_fraction": 0.4,
              "reset_time": "2026-11-15T03:03:40Z",
              "reset_in_seconds": 17999
            },
            "3p-weekly": {
              "remaining_fraction": 0.75,
              "reset_time": "2026-11-21T11:22:11Z",
              "reset_in_seconds": 566310
            },
            "gemini-5h": {
              "remaining_fraction": 0.88968855,
              "reset_time": "2026-11-15T02:22:11Z",
              "reset_in_seconds": 15510
            },
            "gemini-weekly": {
              "remaining_fraction": 0.6295754,
              "reset_time": "2026-11-21T11:22:11Z",
              "reset_in_seconds": 566310
            }
          }
        }
        """.data(using: .utf8)!

        let usage = try XCTUnwrap(GeminiUsageReader.usage(from: json, activeModelId: "gemini-4-hydrogen", now: Self.now))

        XCTAssertEqual(usage.session?.utilization ?? -1, 11.031145, accuracy: 0.001)
        XCTAssertEqual(usage.session?.usagePercentage, 11)
        XCTAssertNotNil(usage.session?.resetDate)
        XCTAssertEqual(usage.weekly?.utilization ?? -1, 37.04246, accuracy: 0.001)
        XCTAssertEqual(usage.weekly?.usagePercentage, 37)
        XCTAssertEqual(usage.updatedAt?.timeIntervalSince1970 ?? 0, 1_794_693_820.762, accuracy: 0.001)
    }

    func testSwitchesToThreePartyBucketsForClaudeOrGptModels() throws {
        let json = """
        {
          "updatedAt": 1794693820762,
          "buckets": {
            "3p-5h": { "remaining_fraction": 0.25, "reset_time": "2026-11-15T03:03:40Z" },
            "3p-weekly": { "remaining_fraction": 0.5, "reset_time": "2026-11-21T11:22:11Z" },
            "gemini-5h": { "remaining_fraction": 0.9, "reset_time": "2026-11-15T02:22:11Z" },
            "gemini-weekly": { "remaining_fraction": 0.8, "reset_time": "2026-11-21T11:22:11Z" }
          }
        }
        """.data(using: .utf8)!

        let claudeUsage = try XCTUnwrap(GeminiUsageReader.usage(from: json, activeModelId: "claude-sonnet-4-5", now: Self.now))
        XCTAssertEqual(claudeUsage.session?.usagePercentage, 75)
        XCTAssertEqual(claudeUsage.weekly?.usagePercentage, 50)

        let gptUsage = try XCTUnwrap(GeminiUsageReader.usage(from: json, activeModelId: "gpt-5", now: Self.now))
        XCTAssertEqual(gptUsage.session?.usagePercentage, 75)
        XCTAssertEqual(gptUsage.weekly?.usagePercentage, 50)
    }

    func testRollsExpiredWindowToZeroWhenResetTimeHasPassed() throws {
        let json = """
        {
          "updatedAt": 1794693820762,
          "buckets": {
            "gemini-5h": {
              "remaining_fraction": 0.15,
              "reset_time": "2026-11-14T20:00:00Z"
            },
            "gemini-weekly": {
              "remaining_fraction": 0.6,
              "reset_time": "2026-11-21T11:22:11Z"
            }
          }
        }
        """.data(using: .utf8)!

        let usage = try XCTUnwrap(GeminiUsageReader.usage(from: json, activeModelId: nil, now: Self.now))

        XCTAssertEqual(usage.session?.usagePercentage, 0)
        XCTAssertEqual(usage.weekly?.usagePercentage, 40)
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(GeminiUsageReader.usage(from: Data("not json".utf8), activeModelId: nil, now: Self.now))
    }
}
