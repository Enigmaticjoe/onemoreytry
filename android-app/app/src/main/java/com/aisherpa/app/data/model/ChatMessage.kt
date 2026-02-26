package com.aisherpa.app.data.model

data class ChatMessage(
    val id: String = System.currentTimeMillis().toString(),
    val content: String,
    val role: MessageRole,
    val timestamp: Long = System.currentTimeMillis()
)

enum class MessageRole {
    USER, SHERPA, SYSTEM
}

data class SherpaRequest(
    val message: String
)

data class SherpaResponse(
    val reply: String
)
