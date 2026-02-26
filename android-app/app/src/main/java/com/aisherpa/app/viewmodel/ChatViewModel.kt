package com.aisherpa.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aisherpa.app.BuildConfig
import com.aisherpa.app.data.api.ApiClient
import com.aisherpa.app.data.api.SherpaChatBody
import com.aisherpa.app.data.model.ChatMessage
import com.aisherpa.app.data.model.MessageRole
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ChatViewModel : ViewModel() {

    private val _messages = MutableStateFlow<List<ChatMessage>>(
        listOf(
            ChatMessage(
                id = "welcome",
                content = "Welcome, traveler! I'm the AI Sherpa — your guide through the Grand Unified AI Home Lab.\n\nI can help you with:\n" +
                    "  - Installing & configuring nodes\n" +
                    "  - Docker & container setup\n" +
                    "  - LiteLLM & model management\n" +
                    "  - KVM automation\n" +
                    "  - Troubleshooting any service\n\n" +
                    "What would you like help with?",
                role = MessageRole.SHERPA
            )
        )
    )
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _isTyping = MutableStateFlow(false)
    val isTyping: StateFlow<Boolean> = _isTyping.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private var commandCenterUrl = BuildConfig.DEFAULT_COMMAND_CENTER_URL

    fun updateBaseUrl(url: String) {
        commandCenterUrl = url
    }

    fun sendMessage(text: String) {
        if (text.isBlank()) return

        val userMsg = ChatMessage(content = text.trim(), role = MessageRole.USER)
        _messages.value = _messages.value + userMsg
        _isTyping.value = true
        _error.value = null

        viewModelScope.launch {
            try {
                val api = ApiClient.createSherpaService(commandCenterUrl)
                val response = api.sherpaChat(SherpaChatBody(message = text.trim()))
                val sherpaMsg = ChatMessage(
                    content = response.reply,
                    role = MessageRole.SHERPA
                )
                _messages.value = _messages.value + sherpaMsg
            } catch (e: Exception) {
                _error.value = "Connection failed: ${e.message}"
                val errMsg = ChatMessage(
                    content = "I couldn't reach the Command Center at $commandCenterUrl. Please check that Node A is running and your network settings are correct.",
                    role = MessageRole.SYSTEM
                )
                _messages.value = _messages.value + errMsg
            } finally {
                _isTyping.value = false
            }
        }
    }

    fun clearChat() {
        _messages.value = listOf(
            ChatMessage(
                id = "welcome",
                content = "Chat cleared. How can I help you?",
                role = MessageRole.SHERPA
            )
        )
        _error.value = null
    }

    fun dismissError() {
        _error.value = null
    }
}
