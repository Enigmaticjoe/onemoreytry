package com.aisherpa.app.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.aisherpa.app.data.model.Node
import com.aisherpa.app.data.model.NodeStatus
import com.aisherpa.app.ui.theme.NodeOffline
import com.aisherpa.app.ui.theme.NodeOnline
import com.aisherpa.app.ui.theme.NodeUnknown
import com.aisherpa.app.ui.theme.NodeWarning
import com.aisherpa.app.ui.theme.SherpaCard
import com.aisherpa.app.ui.theme.TextPrimary
import com.aisherpa.app.ui.theme.TextSecondary

@Composable
fun NodeStatusCard(node: Node, modifier: Modifier = Modifier) {
    val statusColor by animateColorAsState(
        targetValue = when (node.status) {
            NodeStatus.ONLINE -> NodeOnline
            NodeStatus.OFFLINE -> NodeOffline
            NodeStatus.WARNING -> NodeWarning
            NodeStatus.UNKNOWN -> NodeUnknown
        },
        label = "statusColor"
    )

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = SherpaCard),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Header row: icon + name + status dot
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = nodeIcon(node.id),
                        contentDescription = node.name,
                        tint = statusColor,
                        modifier = Modifier.size(28.dp)
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Column {
                        Text(
                            text = node.name,
                            style = MaterialTheme.typography.titleMedium,
                            color = TextPrimary
                        )
                        Text(
                            text = node.role,
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary
                        )
                    }
                }
                // Status dot
                Box(
                    modifier = Modifier
                        .size(14.dp)
                        .clip(CircleShape)
                        .background(statusColor)
                )
            }

            Spacer(modifier = Modifier.height(10.dp))

            // IP + Hardware
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "${node.ip}:${node.port}",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary
                )
                if (node.hardware.isNotEmpty()) {
                    Text(
                        text = node.hardware,
                        style = MaterialTheme.typography.labelSmall,
                        color = TextSecondary
                    )
                }
            }

            // Services
            if (node.services.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                node.services.forEach { service ->
                    ServiceRow(service.name, service.port, service.status)
                }
            }
        }
    }
}

@Composable
private fun ServiceRow(name: String, port: Int, status: NodeStatus) {
    val dotColor = when (status) {
        NodeStatus.ONLINE -> NodeOnline
        NodeStatus.OFFLINE -> NodeOffline
        NodeStatus.WARNING -> NodeWarning
        NodeStatus.UNKNOWN -> NodeUnknown
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(dotColor)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = name,
            style = MaterialTheme.typography.bodySmall,
            color = TextPrimary,
            modifier = Modifier.weight(1f)
        )
        Text(
            text = ":$port",
            style = MaterialTheme.typography.labelSmall,
            color = TextSecondary
        )
    }
}

private fun nodeIcon(nodeId: String): ImageVector {
    return when (nodeId) {
        "node-a" -> Icons.Default.Memory
        "node-b" -> Icons.Default.Dns
        "node-c" -> Icons.Default.Computer
        "node-d" -> Icons.Default.Home
        "node-e" -> Icons.Default.Videocam
        else -> Icons.Default.Dns
    }
}
