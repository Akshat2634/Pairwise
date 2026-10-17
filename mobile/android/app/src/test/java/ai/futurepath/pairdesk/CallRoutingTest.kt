package ai.futurepath.pairdesk

import org.junit.Assert.assertEquals
import org.junit.Test

class CallRoutingTest {
    private val caller = TeamMember("a", "A", "a@example.com")
    private val target = TeamMember("b", "B", "b@example.com")
    private val room = CallRoom("r", "Direct call")

    @Test fun onlyPendingCallsTargetedAtCurrentUserAreIncoming() {
        val calls = listOf(
            Invitation("1", "pending", caller, target, room),
            Invitation("2", "accepted", caller, target, room),
            Invitation("3", "pending", caller, caller, room)
        )
        assertEquals(listOf("1"), incomingCalls(calls, "b").map { it.id })
    }

    @Test fun onlyPendingJoinRequestsFromOtherPeopleNeedApproval() {
        val requests = listOf(
            JoinRequest("1", "pending", caller, room),
            JoinRequest("2", "pending", target, room),
            JoinRequest("3", "declined", caller, room)
        )
        assertEquals(listOf("1"), actionableJoinRequests(requests, "b").map { it.id })
    }

    @Test fun onlyAcceptedJoinRequestsForCurrentUserCanJoin() {
        val requests = listOf(
            JoinRequest("1", "accepted", target, room),
            JoinRequest("2", "pending", target, room),
            JoinRequest("3", "accepted", caller, room)
        )
        assertEquals(listOf("1"), approvedJoins(requests, "b").map { it.id })
    }
}
