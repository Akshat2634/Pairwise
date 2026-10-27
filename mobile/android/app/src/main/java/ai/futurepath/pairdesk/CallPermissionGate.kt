package ai.futurepath.pairdesk

internal sealed interface PendingCallAction {
    data class Place(val userId: String) : PendingCallAction
    data class Answer(val invitationId: String, val roomId: String) : PendingCallAction
    data class Join(val roomId: String) : PendingCallAction
}

/** Keep the user's action while Android presents its asynchronous permission UI. */
internal class CallPermissionGate {
    private var pending: PendingCallAction? = null

    fun request(action: PendingCallAction, granted: Boolean): Boolean {
        if (granted) { pending = null; return true }
        pending = action
        return false
    }

    fun resolve(granted: Boolean): PendingCallAction? {
        val action = pending
        pending = null
        return action.takeIf { granted }
    }
}
