package com.aisherpa.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.aisherpa.app.BuildConfig
import com.aisherpa.app.ui.components.SherpaTopBar
import com.aisherpa.app.ui.theme.SherpaAccent
import com.aisherpa.app.ui.theme.SherpaBackground
import com.aisherpa.app.ui.theme.SherpaCard
import com.aisherpa.app.ui.theme.SherpaPrimary
import com.aisherpa.app.ui.theme.SherpaSurface
import com.aisherpa.app.ui.theme.TextPrimary
import com.aisherpa.app.ui.theme.TextSecondary

@Composable
fun SettingsScreen(
    onSave: (commandCenterUrl: String, kvmUrl: String, kvmToken: String) -> Unit
) {
    var commandCenterUrl by remember {
        mutableStateOf(BuildConfig.DEFAULT_COMMAND_CENTER_URL)
    }
    var kvmUrl by remember {
        mutableStateOf(BuildConfig.DEFAULT_KVM_OPERATOR_URL)
    }
    var kvmToken by remember { mutableStateOf("") }

    Scaffold(
        topBar = { SherpaTopBar(subtitle = "Settings") },
        containerColor = SherpaBackground
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            item {
                SettingsSection("Command Center (Node A)") {
                    SettingsField(
                        label = "Base URL",
                        value = commandCenterUrl,
                        onValueChange = { commandCenterUrl = it },
                        placeholder = "http://192.168.1.9:3099"
                    )
                }
            }

            item {
                SettingsSection("KVM Operator") {
                    SettingsField(
                        label = "Base URL",
                        value = kvmUrl,
                        onValueChange = { kvmUrl = it },
                        placeholder = "http://192.168.1.9:5000"
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    SettingsField(
                        label = "API Token",
                        value = kvmToken,
                        onValueChange = { kvmToken = it },
                        placeholder = "Bearer token for KVM Operator"
                    )
                }
            }

            item {
                SettingsSection("Network Topology") {
                    InfoRow("Node A (Brain)", "192.168.1.9")
                    InfoRow("Node B (Unraid)", "192.168.1.222")
                    InfoRow("Node C (Arc)", "192.168.1.6")
                    InfoRow("Node D (Home Asst)", "192.168.1.149")
                    InfoRow("Node E (Sentinel)", "192.168.1.116")
                    InfoRow("NanoKVM (kvm-d829)", "192.168.1.130")
                }
            }

            item {
                Button(
                    onClick = { onSave(commandCenterUrl, kvmUrl, kvmToken) },
                    modifier = Modifier.fillMaxWidth(),
                    colors = ButtonDefaults.buttonColors(containerColor = SherpaPrimary),
                    shape = RoundedCornerShape(12.dp)
                ) {
                    Text("Save Settings", color = TextPrimary)
                }
            }

            item {
                Text(
                    text = "AI Sherpa v${BuildConfig.VERSION_NAME} — Grand Unified AI Home Lab",
                    style = MaterialTheme.typography.labelSmall,
                    color = TextSecondary,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }
}

@Composable
private fun SettingsSection(title: String, content: @Composable () -> Unit) {
    Card(
        colors = CardDefaults.cardColors(containerColor = SherpaCard),
        shape = RoundedCornerShape(12.dp)
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                color = SherpaAccent
            )
            Spacer(modifier = Modifier.height(12.dp))
            content()
        }
    }
}

@Composable
private fun SettingsField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String
) {
    Column {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = TextSecondary
        )
        Spacer(modifier = Modifier.height(4.dp))
        TextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text(placeholder, color = TextSecondary.copy(alpha = 0.5f)) },
            singleLine = true,
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
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(text = label, style = MaterialTheme.typography.bodySmall, color = TextSecondary)
        Text(text = value, style = MaterialTheme.typography.labelLarge, color = TextPrimary)
    }
}
