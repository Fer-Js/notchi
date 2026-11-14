import Foundation
import XCTest
@testable import notchi

@MainActor
final class GeminiUsageServiceTests: XCTestCase {
    private static let observedAt = Date(timeIntervalSince1970: 1_794_694_000)
    private static let sessionQuota = QuotaPeriod(utilization: 12, resetDate: Date(timeIntervalSince1970: 1_794_708_000))
    private static let weeklyQuota = QuotaPeriod(utilization: 37, resetDate: Date(timeIntervalSince1970: 1_795_298_000))

    func testRefreshPublishesSessionAndWeeklyUsageWhenCacheIsFresh() async {
        let service = GeminiUsageService(
            readUsage: { _, _ in
                GeminiUsage(session: Self.sessionQuota, weekly: Self.weeklyQuota, updatedAt: Self.observedAt.addingTimeInterval(-30))
            },
            now: { Self.observedAt }
        )

        await service.refresh()

        XCTAssertEqual(service.currentUsage, Self.sessionQuota)
        XCTAssertEqual(service.currentWeeklyUsage, Self.weeklyQuota)
        XCTAssertEqual(service.lastObservedAt, Self.observedAt)
        XCTAssertFalse(service.isUsageStale)
    }

    func testMarksUsageStaleWhenCacheIsOlderThanFreshnessThreshold() async {
        let service = GeminiUsageService(
            readUsage: { _, _ in
                GeminiUsage(session: Self.sessionQuota, weekly: Self.weeklyQuota, updatedAt: Self.observedAt.addingTimeInterval(-3600))
            },
            now: { Self.observedAt }
        )

        await service.refresh()

        XCTAssertTrue(service.isUsageStale)
        XCTAssertEqual(service.currentUsage, Self.sessionQuota)
    }

    func testClearsUsageWhenCacheDisappears() async {
        var returnNil = false
        let service = GeminiUsageService(
            readUsage: { _, _ in
                if returnNil { return nil }
                return GeminiUsage(session: Self.sessionQuota, weekly: Self.weeklyQuota, updatedAt: Self.observedAt)
            },
            now: { Self.observedAt }
        )

        await service.refresh()
        XCTAssertTrue(service.hasUsageData)

        returnNil = true
        await service.refresh()
        XCTAssertFalse(service.hasUsageData)
        XCTAssertNil(service.lastObservedAt)
    }

    func testUpdatingActiveModelRefreshesWithNewModelId() async {
        var capturedModel: String?
        let service = GeminiUsageService(
            readUsage: { modelId, _ in
                capturedModel = modelId
                return GeminiUsage(session: Self.sessionQuota, weekly: Self.weeklyQuota, updatedAt: Self.observedAt)
            },
            now: { Self.observedAt }
        )

        service.setActiveModelId("claude-sonnet-4-5")
        await service.refresh()

        XCTAssertEqual(capturedModel, "claude-sonnet-4-5")
    }
}
