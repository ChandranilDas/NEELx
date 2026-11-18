import Foundation

/// Local hardening experiment. Limits authorization, not biometric spoof resistance.
nonisolated struct SessionSecurityPolicy {
    private static let clockOrigin = ContinuousClock.now
    static var now: TimeInterval {
        let elapsed = clockOrigin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    static let maximumAge: TimeInterval = 8 * 60 * 60
    static let maximumFailures = 5
    private(set) var authorizedAt: TimeInterval?
    private(set) var failures = 0

    mutating func authorize(at now: TimeInterval) {
        authorizedAt = now
        failures = 0
    }
    mutating func revoke() { authorizedAt = nil }
    func allows(at now: TimeInterval) -> Bool {
        guard let start = authorizedAt, now.isFinite, start.isFinite else { return false }
        return now >= start && now - start < Self.maximumAge && failures < Self.maximumFailures
    }
    mutating func recordFailure() { failures = min(failures + 1, Self.maximumFailures) }
}
