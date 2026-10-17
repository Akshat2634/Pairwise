package ai.futurepath.pairdesk

/**
 * Authenticated device registration seam. The server's POST /v1/devices request
 * schema is intentionally unspecified until its API contract is merged.
 */
interface PushDeviceRegistrar {
    suspend fun register(deviceId: String, token: String)
    suspend fun unregister(deviceId: String)
}
