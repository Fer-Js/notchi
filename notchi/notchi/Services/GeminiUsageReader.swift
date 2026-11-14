import Foundation

nonisolated struct GeminiUsage: Equatable, Sendable {
    let session: QuotaPeriod?
    let weekly: QuotaPeriod?
    let updatedAt: Date?
}

nonisolated enum GeminiUsageReader {
    static var defaultQuotaCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity-cli", isDirectory: true)
            .appendingPathComponent("tui-quota-cache.json")
    }

    private struct QuotaCachePayload: Decodable {
        let updatedAt: Double?
        let buckets: [String: Bucket]?
    }

    private struct Bucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let resetInSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case remainingFraction = "remaining_fraction"
            case resetTime = "reset_time"
            case resetInSeconds = "reset_in_seconds"
        }
    }

    static func readUsage(
        url: URL = defaultQuotaCacheURL,
        activeModelId: String? = nil,
        now: Date = Date()
    ) -> GeminiUsage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return usage(from: data, activeModelId: activeModelId, now: now)
    }

    static func usage(
        from data: Data,
        activeModelId: String? = nil,
        now: Date = Date()
    ) -> GeminiUsage? {
        guard let payload = try? JSONDecoder().decode(QuotaCachePayload.self, from: data),
              let buckets = payload.buckets,
              !buckets.isEmpty else {
            return nil
        }

        let updatedAt = payload.updatedAt.map { ms in
            Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000.0 : ms)
        }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        let preferThirdParty = isThirdPartyModel(activeModelId)
        let sessionKeys = preferThirdParty
            ? ["3p-5h", "gemini-5h"]
            : ["gemini-5h", "3p-5h"]
        let weeklyKeys = preferThirdParty
            ? ["3p-weekly", "gemini-weekly", "gemini-argon-wtu-weekly"]
            : ["gemini-weekly", "gemini-argon-wtu-weekly", "3p-weekly"]

        let sessionBucket = sessionKeys.compactMap { buckets[$0] }.first
        let weeklyBucket = weeklyKeys.compactMap { buckets[$0] }.first

        let session = sessionBucket.flatMap {
            quotaPeriod(from: $0, updatedAt: updatedAt, now: now, isoFractional: isoFractional, isoPlain: isoPlain)
        }
        let weekly = weeklyBucket.flatMap {
            quotaPeriod(from: $0, updatedAt: updatedAt, now: now, isoFractional: isoFractional, isoPlain: isoPlain)
        }

        guard session != nil || weekly != nil else { return nil }
        return GeminiUsage(session: session, weekly: weekly, updatedAt: updatedAt)
    }

    private static func isThirdPartyModel(_ modelId: String?) -> Bool {
        guard let lower = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !lower.isEmpty else {
            return false
        }
        return lower.hasPrefix("claude") || lower.hasPrefix("gpt")
    }

    private static func quotaPeriod(
        from bucket: Bucket,
        updatedAt: Date?,
        now: Date,
        isoFractional: ISO8601DateFormatter,
        isoPlain: ISO8601DateFormatter
    ) -> QuotaPeriod? {
        guard let remaining = bucket.remainingFraction else { return nil }

        let resetDate: Date? = {
            if let resetTime = bucket.resetTime {
                if let parsed = isoFractional.date(from: resetTime) ?? isoPlain.date(from: resetTime) {
                    return parsed
                }
            }
            if let seconds = bucket.resetInSeconds, let base = updatedAt {
                return base.addingTimeInterval(seconds)
            }
            return nil
        }()

        if let resetDate, resetDate <= now {
            return QuotaPeriod(utilization: 0, resetDate: resetDate)
        }

        let usedPercent = min(100.0, max(0.0, (1.0 - remaining) * 100.0))
        return QuotaPeriod(utilization: usedPercent, resetDate: resetDate)
    }
}
