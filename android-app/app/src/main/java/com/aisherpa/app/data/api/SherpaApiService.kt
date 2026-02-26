package com.aisherpa.app.data.api

import com.aisherpa.app.data.model.SherpaResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

data class SherpaChatBody(
    val message: String
)

data class GeneralChatBody(
    val message: String,
    val model: String = "brain-heavy"
)

data class StatusResponse(
    val litellm: String = "unknown",
    val brain: String = "unknown",
    val nodeC: String = "unknown",
    val nodeD: String = "unknown",
    val nodeE: String = "unknown",
    val uptimeKuma: String = "unknown",
    val dozzle: String = "unknown",
    val homepage: String = "unknown"
)

interface SherpaApiService {
    @POST("/api/sherpa-chat")
    suspend fun sherpaChat(@Body body: SherpaChatBody): SherpaResponse

    @POST("/api/chat")
    suspend fun generalChat(@Body body: GeneralChatBody): SherpaResponse

    @GET("/api/status")
    suspend fun getStatus(): StatusResponse
}
