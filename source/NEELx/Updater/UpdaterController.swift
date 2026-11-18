import Foundation
import Observation

/// This local experimental build must never auto-replace itself with an upstream release.
@Observable
@MainActor
final class UpdaterController {
    var automaticallyChecksForUpdates = false
    let canCheckForUpdates = false
    let isPresentingUpdateUI = false
    func start() {}
    func checkForUpdates() {}
}
