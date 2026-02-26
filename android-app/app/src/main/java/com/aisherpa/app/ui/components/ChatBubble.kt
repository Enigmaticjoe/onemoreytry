package com.aisherpa.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Terrain
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aisherpa.app.data.model.ChatMessage
import com.aisherpa.app.data.model.MessageRole
import com.aisherpa.app.ui.theme.ChatSherpaBubble
import com.aisherpa.app.ui.theme.ChatTimestamp
import com.aisherpa.app.ui.theme.ChatUserBubble
import com.aisherpa.app.ui.theme.NodeWarning
import com.aisherpa.app.ui.theme.SherpaAccent
import com.aisherpa.app.ui.theme.TextOnPrimary
import com.aisherpa.app.ui.theme.TextPrimary

@Composable
fun ChatBubble(message: ChatMessage) {
    val isUser = message.role == MessageRole.USER
    val isSystem = message.role == MessageRole.SYSTEM

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 4.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        if (!isUser && !isSystem) {
            Icon(
                imageVector = Icons.Default.Terrain,
                contentDescription = "Sherpa",
                tint = SherpaAccent,
                modifier = Modifier
                    .size(24.dp)
                    .padding(top = 4.dp)
            )
        }
        if (isSystem) {
            Icon(
                imageVector = Icons.Default.Warning,
                contentDescription = "System",
                tint = NodeWarning,
                modifier = Modifier
                    .size(24.dp)
                    .padding(top = 4.dp)
            )
        }

        Surface(
            modifier = Modifier
                .widthIn(max = 300.dp)
                .padding(horizontal = 6.dp),
            shape = RoundedCornerShape(
                topStart = if (isUser) 16.dp else 4.dp,
                topEnd = if (isUser) 4.dp else 16.dp,
                bottomStart = 16.dp,
                bottomEnd = 16.dp
            ),
            color = when {
                isSystem -> NodeWarning.copy(alpha = 0.2f)
                isUser -> ChatUserBubble
                else -> ChatSherpaBubble
            }
        ) {
            Column(modifier = Modifier.padding(12.dp)) {
                if (!isUser) {
                    Text(
                        text = if (isSystem) "System" else "AI Sherpa",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (isSystem) NodeWarning else SherpaAccent
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                }
                Text(
                    text = message.content,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (isUser) TextOnPrimary else TextPrimary
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = formatTime(message.timestamp),
                    style = MaterialTheme.typography.labelSmall,
                    color = ChatTimestamp,
                    modifier = Modifier.align(Alignment.End)
                )
            }
        }
    }
}

private fun formatTime(ts: Long): String {
    return java.text.SimpleDateFormat(
        "h:mm a", java.util.Locale.getDefault()
    ).format(java.util.Date(ts))
}
