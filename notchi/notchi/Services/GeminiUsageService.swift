import Foundation

@MainActor
@Observable
final class GeminiUsageService {
    static let shared = GeminiUsageService()

    var currentUsage: QuotaPeriod?
    var currentWeeklyUsage: QuotaPeriod?
    var lastObservedAt: Date?
    var isUsageStale = false
    private(set) var activeModelId: String?

    var hasUsageData: Bool {
        currentUsage != nil || currentWeeklyUsage != nil
    }

    static let freshnessInterval: TimeInterval = 30 * 60
    private static let refreshInterval: TimeInterval = 15

    private let readUsage: @Sendable (String?, Date) -> GeminiUsage?
    private let now: @Sendable () -> Date
    private var pollTimer: Timer?
    private var isRefreshing = false

    init(
        readUsage: @escaping @Sendable (String?, Date) -> GeminiUsage? = { modelId, now in
            GeminiUsageReader.readUsage(activeModelId: modelId, now: now)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.readUsage = readUsage
        self.now = now
    }

    func setActiveModelId(_ modelId: String?) {
        let trimmed = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeModelId = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let observedAt = now()
        let modelId = activeModelId
        let readUsage = readUsage
        let usage = await Task.detached(priority: .utility) {
            readUsage(modelId, observedAt)
        }.value

        currentUsage = usage?.session
        currentWeeklyUsage = usage?.weekly
        lastObservedAt = hasUsageData ? observedAt : nil
        if hasUsageData, let updatedAt = usage?.updatedAt {
            isUsageStale = observedAt.timeIntervalSince(updatedAt) > Self.freshnessInterval
        } else {
            isUsageStale = false
        }
    }
}
