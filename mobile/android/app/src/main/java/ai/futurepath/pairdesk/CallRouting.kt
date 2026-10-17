package ai.futurepath.pairdesk

/** Small pure predicates shared by UI and tests so terminal invitations never ring again. */
internal fun incomingCalls(calls: List<Invitation>, currentUserId: String): List<Invitation> =
    calls.filter { it.status == "pending" && it.target.id == currentUserId }

internal fun actionableJoinRequests(requests: List<JoinRequest>, currentUserId: String): List<JoinRequest> =
    requests.filter { it.status == "pending" && it.requester.id != currentUserId }

internal fun approvedJoins(requests: List<JoinRequest>, currentUserId: String): List<JoinRequest> =
    requests.filter { it.status == "accepted" && it.requester.id == currentUserId }
