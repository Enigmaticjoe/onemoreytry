package com.aisherpa.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Power
import androidx.compose.material.icons.filled.PowerOff
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RestartAlt
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.aisherpa.app.ui.components.KvmSnapshotViewer
import com.aisherpa.app.ui.components.SherpaTopBar
import com.aisherpa.app.ui.theme.NodeOffline
import com.aisherpa.app.ui.theme.NodeOnline
import com.aisherpa.app.ui.theme.NodeWarning
import com.aisherpa.app.ui.theme.SherpaAccent
import com.aisherpa.app.ui.theme.SherpaBackground
import com.aisherpa.app.ui.theme.SherpaCard
import com.aisherpa.app.ui.theme.SherpaPrimary
import com.aisherpa.app.ui.theme.SherpaSurface
import com.aisherpa.app.ui.theme.TextPrimary
import com.aisherpa.app.ui.theme.TextSecondary
import com.aisherpa.app.viewmodel.KvmViewModel

@Composable
fun KvmScreen(viewModel: KvmViewModel) {
    val targets by viewModel.targets.collectAsState()
    val selectedTarget by viewModel.selectedTarget.collectAsState()
    val snapshot by viewModel.snapshot.collectAsState()
    val health by viewModel.health.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val statusMessage by viewModel.statusMessage.collectAsState()
    val taskLog by viewModel.taskLog.collectAsState()

    var taskInstruction by remember { mutableStateOf("") }

    LaunchedEffect(Unit) {
        viewModel.loadHealth()
    }

    Scaffold(
        topBar = { SherpaTopBar(subtitle = "KVM Control") },
        containerColor = SherpaBackground
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // Connection status bar
            item {
                ConnectionStatusBar(health, statusMessage, isLoading)
            }

            // Target selector
            item {
                Text(
                    text = "KVM Targets",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                Spacer(modifier = Modifier.height(8.dp))
                if (targets.isEmpty()) {
                    Text(
                        text = "No targets found. Check KVM Operator connection.",
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary
                    )
                } else {
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(targets) { target ->
                            TargetChip(
                                name = target.name,
                                isSelected = target.name == selectedTarget,
                                onClick = { viewModel.selectTarget(target.name) }
                            )
                        }
                    }
                }
            }

            // Live snapshot viewer
            item {
                SectionHeader("Live View")
                Spacer(modifier = Modifier.height(8.dp))
                KvmSnapshotViewer(
                    snapshot = snapshot,
                    targetName = selectedTarget ?: ""
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center
                ) {
                    Button(
                        onClick = { viewModel.captureSnapshot() },
                        enabled = selectedTarget != null && !isLoading,
                        colors = ButtonDefaults.buttonColors(containerColor = SherpaPrimary)
                    ) {
                        Icon(Icons.Default.CameraAlt, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Capture")
                    }
                    Spacer(modifier = Modifier.width(12.dp))
                    OutlinedButton(
                        onClick = { viewModel.captureSnapshot() },
                        enabled = selectedTarget != null && !isLoading
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("Refresh")
                    }
                }
            }

            // Power controls
            item {
                SectionHeader("Power Control")
                Spacer(modifier = Modifier.height(8.dp))
                PowerControlPanel(
                    onPower = { action -> viewModel.powerAction(action) },
                    enabled = selectedTarget != null && !isLoading
                )
            }

            // AI Task runner
            item {
                SectionHeader("AI Vision Task")
                Spacer(modifier = Modifier.height(8.dp))
                Card(
                    colors = CardDefaults.cardColors(containerColor = SherpaCard),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            text = "Describe what the AI should do on the remote screen:",
                            style = MaterialTheme.typography.bodySmall,
                            color = TextSecondary
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        TextField(
                            value = taskInstruction,
                            onValueChange = { taskInstruction = it },
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text("e.g. Open terminal and run htop", color = TextSecondary) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                            keyboardActions = KeyboardActions(onGo = {
                                if (taskInstruction.isNotBlank()) {
                                    viewModel.runTask(taskInstruction)
                                }
                            }),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = SherpaSurface,
                                unfocusedContainerColor = SherpaSurface,
                                focusedTextColor = TextPrimary,
                                unfocusedTextColor = TextPrimary,
                                cursorColor = SherpaAccent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent
                            ),
                            shape = RoundedCornerShape(8.dp)
                        )
                        Spacer(modifier = Modifier.height(10.dp))
                        Row {
                            Button(
                                onClick = {
                                    if (taskInstruction.isNotBlank()) {
                                        viewModel.runTask(taskInstruction)
                                    }
                                },
                                enabled = taskInstruction.isNotBlank() && selectedTarget != null && !isLoading,
                                colors = ButtonDefaults.buttonColors(containerColor = SherpaAccent)
                            ) {
                                Icon(Icons.Default.SmartToy, contentDescription = null, modifier = Modifier.size(18.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text("Run AI Task", color = Color.Black)
                            }
                            if (isLoading) {
                                Spacer(modifier = Modifier.width(12.dp))
                                CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    color = SherpaAccent,
                                    strokeWidth = 2.dp
                                )
                            }
                        }
                    }
                }
            }

            // Task log
            if (taskLog.isNotEmpty()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        SectionHeader("Activity Log")
                        IconButton(onClick = { viewModel.clearLog() }) {
                            Icon(
                                Icons.Default.DeleteSweep,
                                contentDescription = "Clear log",
                                tint = TextSecondary
                            )
                        }
                    }
                    Spacer(modifier = Modifier.height(4.dp))
                    Card(
                        colors = CardDefaults.cardColors(containerColor = SherpaCard),
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Column(modifier = Modifier.padding(12.dp)) {
                            taskLog.takeLast(20).forEach { entry ->
                                Text(
                                    text = entry,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = when {
                                        "ERROR" in entry -> NodeOffline
                                        "RESULT" in entry -> NodeOnline
                                        "NOTE" in entry -> NodeWarning
                                        else -> TextSecondary
                                    },
                                    modifier = Modifier.padding(vertical = 2.dp)
                                )
                            }
                        }
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(80.dp)) }
        }
    }
}

@Composable
private fun ConnectionStatusBar(
    health: com.aisherpa.app.data.model.KvmHealthResponse?,
    statusMessage: String,
    isLoading: Boolean
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = if (health != null) NodeOnline.copy(alpha = 0.1f) else NodeOffline.copy(alpha = 0.1f),
                shape = RoundedCornerShape(12.dp)
            )
            .padding(12.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(RoundedCornerShape(5.dp))
                    .background(if (health != null) NodeOnline else NodeOffline)
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (health != null) "Connected" else "Disconnected",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                if (statusMessage.isNotEmpty()) {
                    Text(
                        text = statusMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = TextSecondary
                    )
                }
            }
            if (health != null) {
                Column(horizontalAlignment = Alignment.End) {
                    Text(
                        text = "Approval: ${if (health.require_approval) "ON" else "OFF"}",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (health.require_approval) NodeWarning else NodeOnline
                    )
                    Text(
                        text = "Dangerous: ${if (health.allow_dangerous) "ON" else "OFF"}",
                        style = MaterialTheme.typography.labelSmall,
                        color = if (health.allow_dangerous) NodeOffline else NodeOnline
                    )
                }
            }
        }
    }
}

@Composable
private fun TargetChip(name: String, isSelected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(20.dp))
            .background(if (isSelected) SherpaPrimary else SherpaCard)
            .border(
                width = 1.dp,
                color = if (isSelected) SherpaAccent else TextSecondary.copy(alpha = 0.3f),
                shape = RoundedCornerShape(20.dp)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Default.Keyboard,
                contentDescription = null,
                tint = if (isSelected) TextPrimary else TextSecondary,
                modifier = Modifier.size(16.dp)
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = name,
                style = MaterialTheme.typography.bodySmall,
                color = if (isSelected) TextPrimary else TextSecondary
            )
        }
    }
}

@Composable
private fun PowerControlPanel(onPower: (String) -> Unit, enabled: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly
    ) {
        PowerButton(Icons.Default.Power, "Power On", NodeOnline, enabled) { onPower("on") }
        PowerButton(Icons.Default.PowerOff, "Power Off", NodeOffline, enabled) { onPower("off") }
        PowerButton(Icons.Default.RestartAlt, "Reset", NodeWarning, enabled) { onPower("reset") }
    }
}

@Composable
private fun PowerButton(
    icon: ImageVector,
    label: String,
    color: Color,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        IconButton(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier
                .size(52.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(
                    if (enabled) color.copy(alpha = 0.15f) else Color.Gray.copy(alpha = 0.1f)
                )
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (enabled) color else Color.Gray,
                modifier = Modifier.size(28.dp)
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (enabled) TextSecondary else Color.Gray
        )
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = TextPrimary
    )
}
