import Testing
import PairwiseCore

struct JoinApprovalTrackerTests {
    @Test func approvalBeforeFirstPendingPollIsNotLost() {
        var state = JoinApprovalTracker()
        state.requestCreated("new")
        #expect(state.shouldAutomaticallyJoin("new"))
        #expect(!state.shouldAutomaticallyJoin("old-accepted-history"))
    }

    @Test func deferringWhileBusyDoesNotConsumeApproval() {
        var state = JoinApprovalTracker()
        state.requestCreated("new")
        #expect(state.shouldAutomaticallyJoin("new"))
        // Observing approval while busy performs no attempt.
        #expect(state.shouldAutomaticallyJoin("new"))
        state.beginAttempt("new")
        #expect(!state.shouldAutomaticallyJoin("new"))
        #expect(state.isAwaitingConnection("new"), "A failed attempt remains explicitly retryable")
    }

    @Test func joinedAndLeftRequestsNeverRejoinFromHistory() {
        var state = JoinApprovalTracker()
        state.requestCreated("new")
        state.beginAttempt("new")
        state.didJoin("new")
        #expect(!state.isAwaitingConnection("new"))
        #expect(!state.shouldAutomaticallyJoin("new"))
        state.requestCreated("another")
        state.clear()
        #expect(!state.shouldAutomaticallyJoin("another"))
    }
}
