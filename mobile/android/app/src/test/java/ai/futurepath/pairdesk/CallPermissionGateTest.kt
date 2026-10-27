package ai.futurepath.pairdesk

import org.junit.Assert.*
import org.junit.Test

class CallPermissionGateTest {
    @Test fun firstAnswerWaitsForPermissionAndResumesExactlyOnce() {
        val gate = CallPermissionGate()
        val answer = PendingCallAction.Answer("invitation", "room")
        assertFalse(gate.request(answer, granted = false))
        assertEquals(answer, gate.resolve(granted = true))
        assertNull(gate.resolve(granted = true))
    }

    @Test fun outgoingAndApprovedJoinActionsSurvivePermissionDialog() {
        for (action in listOf(PendingCallAction.Place("person"), PendingCallAction.Join("room"))) {
            val gate = CallPermissionGate()
            assertFalse(gate.request(action, granted = false))
            assertEquals(action, gate.resolve(granted = true))
        }
    }

    @Test fun denialDiscardsActionAndAllowsAnotherAttempt() {
        val gate = CallPermissionGate()
        val answer = PendingCallAction.Answer("invitation", "room")
        gate.request(answer, granted = false)
        assertNull(gate.resolve(granted = false))
        assertNull(gate.resolve(granted = true))
        assertTrue(gate.request(answer, granted = true))
    }
}
