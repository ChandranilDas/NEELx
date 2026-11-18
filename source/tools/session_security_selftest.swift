import Foundation
@main struct SessionSecuritySelfTest {
 static func main() {
    var p = SessionSecurityPolicy()
    precondition(!p.allows(at: 0))
    p.authorize(at: 100)
    precondition(p.allows(at: 100))
    precondition(!p.allows(at: 99))
    precondition(!p.allows(at: .nan))
    precondition(!p.allows(at: .infinity))
    precondition(p.allows(at: 100 + SessionSecurityPolicy.maximumAge - 0.001))
    precondition(!p.allows(at: 100 + SessionSecurityPolicy.maximumAge))
    for _ in 0..<4 { p.recordFailure() }
    precondition(p.allows(at: 101))
    p.recordFailure()
    precondition(!p.allows(at: 101))
    for _ in 0..<100 { p.recordFailure() }
    precondition(p.failures == 5)
    p.authorize(at: 200)
    precondition(p.failures == 0 && p.allows(at: 200))
    for n in 0..<100 { precondition(p.allows(at: 200 + Double(n))) }
    precondition(!p.allows(at: 200 + SessionSecurityPolicy.maximumAge))
    p.revoke()
    precondition(!p.allows(at: 201))
    precondition(SessionSecurityPolicy.now.isFinite)
    print("PASS: authorization, expiry boundary, rollback, nonfinite clocks, failure cutoff, saturation, reauthorization, non-sliding expiry, revocation")
 }
}
