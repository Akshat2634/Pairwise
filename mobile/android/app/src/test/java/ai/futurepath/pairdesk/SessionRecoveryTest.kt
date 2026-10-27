package ai.futurepath.pairdesk

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class SessionRecoveryTest {
    @Test fun offlineAndServerFailureKeepCredentialsForRetry() = runTest {
        var cleared = false
        for (error in listOf(IOException("offline"), PairDeskApiException(503, "unavailable"))) {
            val result = restoreAuthenticatedSession<String>({ throw error }, { cleared = true })
            assertTrue(result.isFailure)
            assertFalse(cleared)
        }
        val retried = restoreAuthenticatedSession({ "restored user" }, { cleared = true })
        assertEquals("restored user", retried.getOrThrow())
        assertFalse(cleared)
    }

    @Test fun onlyAnAuthenticationRejectionClearsCredentials() = runTest {
        var cleared = false
        val result = restoreAuthenticatedSession<String>({ throw PairDeskApiException(401, "expired") }, { cleared = true })
        assertTrue(result.isFailure)
        assertTrue(cleared)
    }

    @Test fun cancellationDoesNotBecomeALogout() = runTest {
        var cleared = false
        try {
            restoreAuthenticatedSession<String>({ throw CancellationException() }, { cleared = true })
            fail("Cancellation must propagate")
        } catch (_: CancellationException) { }
        assertFalse(cleared)
    }
}
