import Foundation
import Network
import Observation

/// Whether the Mac has an internet connection, for the screens that need one.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "xueji.network"))
    }
}
