package ai.futurepath.pairdesk

import kotlinx.coroutines.CancellationException

class PairDeskApiException(val statusCode: Int, message: String) : IllegalStateException(message)

internal suspend fun <T> restoreAuthenticatedSession(
    load: suspend () -> T,
    clearSavedToken: () -> Unit,
): Result<T> = try {
    Result.success(load())
} catch (cancelled: CancellationException) {
    throw cancelled
} catch (error: Exception) {
    if (error is PairDeskApiException && error.statusCode == 401) clearSavedToken()
    Result.failure(error)
}
