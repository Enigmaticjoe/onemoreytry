package com.aisherpa.app.data.model

data class KvmTarget(
    val name: String,
    val ip: String,
    val powerState: PowerState = PowerState.UNKNOWN,
    val snapshotBase64: String? = null
)

enum class PowerState {
    ON, OFF, UNKNOWN;

    val displayName: String
        get() = when (this) {
            ON -> "Powered On"
            OFF -> "Powered Off"
            UNKNOWN -> "Unknown"
        }
}

data class KvmHealthResponse(
    val ok: Boolean,
    val version: String = "",
    val targets: List<String> = emptyList(),
    val require_approval: Boolean = true,
    val allow_dangerous: Boolean = false
)

data class KvmSnapshotResponse(
    val ok: Boolean,
    val jpeg_b64: String = ""
)

data class KvmTargetsResponse(
    val targets: Map<String, KvmTargetInfo> = emptyMap()
)

data class KvmTargetInfo(
    val ip: String
)

data class KvmTaskRequest(
    val instruction: String,
    val max_steps: Int = 10
)

data class KvmTaskResponse(
    val status: String,
    val history: List<Map<String, Any>> = emptyList(),
    val error: String? = null
)

data class KvmPowerRequest(
    val action: String
)
