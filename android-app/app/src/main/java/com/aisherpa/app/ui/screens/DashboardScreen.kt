package com.aisherpa.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.aisherpa.app.data.model.NodeStatus
import com.aisherpa.app.ui.components.NodeStatusCard
import com.aisherpa.app.ui.components.SherpaTopBar
import com.aisherpa.app.ui.theme.NodeOffline
import com.aisherpa.app.ui.theme.NodeOnline
import com.aisherpa.app.ui.theme.NodeWarning
import com.aisherpa.app.ui.theme.SherpaAccent
import com.aisherpa.app.ui.theme.SherpaBackground
import com.aisherpa.app.ui.theme.SherpaPrimary
import com.aisherpa.app.ui.theme.TextPrimary
import com.aisherpa.app.ui.theme.TextSecondary
import com.aisherpa.app.viewmodel.DashboardViewModel

@Composable
fun DashboardScreen(viewModel: DashboardViewModel) {
    val nodes by viewModel.nodes.collectAsState()
    val isRefreshing by viewModel.isRefreshing.collectAsState()
    val lastRefresh by viewModel.lastRefresh.collectAsState()

    val onlineCount = nodes.count { it.status == NodeStatus.ONLINE }
    val warningCount = nodes.count { it.status == NodeStatus.WARNING }
    val offlineCount = nodes.count { it.status == NodeStatus.OFFLINE }

    Scaffold(
        topBar = { SherpaTopBar(subtitle = "Dashboard") },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { viewModel.refreshAll() },
                containerColor = SherpaPrimary
            ) {
                if (isRefreshing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = TextPrimary,
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(
                        Icons.Default.Refresh,
                        contentDescription = "Refresh",
                        tint = TextPrimary
                    )
                }
            }
        },
        containerColor = SherpaBackground
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Status summary banner
            item {
                StatusSummaryBanner(
                    online = onlineCount,
                    warning = warningCount,
                    offline = offlineCount,
                    total = nodes.size,
                    lastRefresh = lastRefresh,
                    isRefreshing = isRefreshing
                )
            }

            item {
                Text(
                    text = "Lab Nodes",
                    style = MaterialTheme.typography.headlineMedium,
                    color = TextPrimary,
                    modifier = Modifier.padding(vertical = 4.dp)
                )
            }

            items(nodes, key = { it.id }) { node ->
                NodeStatusCard(node = node)
            }

            item { Spacer(modifier = Modifier.height(80.dp)) }
        }
    }
}

@Composable
private fun StatusSummaryBanner(
    online: Int,
    warning: Int,
    offline: Int,
    total: Int,
    lastRefresh: String,
    isRefreshing: Boolean
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = when {
                    offline > 0 -> NodeOffline.copy(alpha = 0.15f)
                    warning > 0 -> NodeWarning.copy(alpha = 0.15f)
                    else -> NodeOnline.copy(alpha = 0.15f)
                },
                shape = RoundedCornerShape(16.dp)
            )
            .padding(16.dp)
    ) {
        Column {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Grand Unified AI Home Lab",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                AnimatedVisibility(visible = isRefreshing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        color = SherpaAccent,
                        strokeWidth = 2.dp
                    )
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                StatusChip(Icons.Default.CheckCircle, "$online Online", NodeOnline)
                StatusChip(Icons.Default.Warning, "$warning Warning", NodeWarning)
                StatusChip(Icons.Default.Error, "$offline Offline", NodeOffline)
            }

            if (lastRefresh.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Last checked: $lastRefresh",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    modifier = Modifier.align(Alignment.End)
                )
            }
        }
    }
}

@Composable
private fun StatusChip(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    color: androidx.compose.ui.graphics.Color
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(18.dp)
        )
        Spacer(modifier = Modifier.size(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = color
        )
    }
}
