/// Local intent, rather than invitation history, determines whether an approval
/// should connect this device. Used by both Apple clients.
public struct JoinApprovalTracker: Sendable {
    private var requested = Set<String>()
    private var attempted = Set<String>()

    public init() {}

    public mutating func requestCreated(_ id: String) { requested.insert(id) }
    public func isAwaitingConnection(_ id: String) -> Bool { requested.contains(id) }
    public func shouldAutomaticallyJoin(_ id: String) -> Bool {
        requested.contains(id) && !attempted.contains(id)
    }
    public mutating func beginAttempt(_ id: String) { attempted.insert(id) }
    public mutating func didJoin(_ id: String) {
        requested.remove(id)
        attempted.remove(id)
    }
    public mutating func clear() {
        requested.removeAll()
        attempted.removeAll()
    }
}
