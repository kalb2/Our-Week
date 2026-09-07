//
//  RateLimiter.swift
//  OurWeek
//
//  Tracks Gemini API usage to stay within free tier limits.
//  Per-minute: 15 requests. Per-day: 1,500 requests.
//

import Foundation

@Observable
class RateLimiter {
    static let shared = RateLimiter()

    // MARK: - Limits

    static let minuteLimit = 15
    static let dailyLimit = 1500

    // MARK: - Tracking

    /// Timestamps of requests in the current minute window
    private var minuteTimestamps: [Date] = []

    /// Daily request count (persisted)
    private(set) var dailyCount: Int {
        didSet { UserDefaults.standard.set(dailyCount, forKey: "gemini_daily_count") }
    }

    /// The date string for which dailyCount applies
    private var dailyCountDate: String {
        didSet { UserDefaults.standard.set(dailyCountDate, forKey: "gemini_daily_date") }
    }

    /// Total all-time request count
    private(set) var totalCount: Int {
        didSet { UserDefaults.standard.set(totalCount, forKey: "gemini_total_count") }
    }

    // MARK: - Init

    private init() {
        self.dailyCount = UserDefaults.standard.integer(forKey: "gemini_daily_count")
        self.dailyCountDate = UserDefaults.standard.string(forKey: "gemini_daily_date") ?? ""
        self.totalCount = UserDefaults.standard.integer(forKey: "gemini_total_count")
        resetIfNeeded()
    }

    // MARK: - Public API

    /// Check if a request can be made. Throws if limit exceeded.
    func canMakeRequest() throws -> Bool {
        resetIfNeeded()
        pruneMinuteTimestamps()

        if minuteTimestamps.count >= Self.minuteLimit {
            throw RateLimitError.minuteLimitExceeded
        }
        if dailyCount >= Self.dailyLimit {
            throw RateLimitError.dailyLimitExceeded
        }
        return true
    }

    /// Record that a request was made.
    func recordRequest() {
        resetIfNeeded()
        minuteTimestamps.append(Date())
        dailyCount += 1
        totalCount += 1
    }

    /// Get remaining requests for both windows without mutating state.
    func getRemainingRequests() -> (perMinute: Int, perDay: Int) {
        let today = todayString()
        let effectiveDailyCount = (dailyCountDate == today) ? dailyCount : 0
        
        let cutoff = Date().addingTimeInterval(-60)
        let validMinuteTimestamps = minuteTimestamps.filter { $0 >= cutoff }
        
        let minuteRemaining = max(0, Self.minuteLimit - validMinuteTimestamps.count)
        let dayRemaining = max(0, Self.dailyLimit - effectiveDailyCount)
        return (minuteRemaining, dayRemaining)
    }

    /// Time until daily limit resets (next midnight).
    var timeUntilDailyReset: TimeInterval {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date())!)
        return tomorrow.timeIntervalSinceNow
    }

    /// Formatted string for daily reset time.
    var dailyResetFormatted: String {
        let seconds = Int(timeUntilDailyReset)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Internal

    /// Reset daily counter if the date has changed.
    func resetIfNeeded() {
        let today = todayString()
        if dailyCountDate != today {
            dailyCount = 0
            dailyCountDate = today
        }
    }

    /// Manually reset all rate limiting counters.
    func resetAllLimits() {
        minuteTimestamps.removeAll()
        dailyCount = 0
        dailyCountDate = todayString()
        totalCount = 0
    }

    /// Remove minute timestamps older than 60 seconds.
    private func pruneMinuteTimestamps() {
        let cutoff = Date().addingTimeInterval(-60)
        minuteTimestamps.removeAll { $0 < cutoff }
    }

    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
