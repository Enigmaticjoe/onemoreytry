package com.aisherpa.app.data.model

data class Node(
    val id: String,
    val name: String,
    val role: String,
    val ip: String,
    val port: Int,
    val status: NodeStatus = NodeStatus.UNKNOWN,
    val services: List<NodeService> = emptyList(),
    val hardware: String = ""
)

enum class NodeStatus {
    ONLINE, OFFLINE, WARNING, UNKNOWN;

    val displayName: String
        get() = when (this) {
            ONLINE -> "Online"
            OFFLINE -> "Offline"
            WARNING -> "Warning"
            UNKNOWN -> "Checking..."
        }
}

data class NodeService(
    val name: String,
    val port: Int,
    val status: NodeStatus = NodeStatus.UNKNOWN,
    val url: String = ""
)

// Pre-configured nodes matching the home lab topology
object LabNodes {
    val ALL = listOf(
        Node(
            id = "node-a",
            name = "Node A — Brain",
            role = "Command Center / vLLM",
            ip = "192.168.1.9",
            port = 3099,
            hardware = "AMD RX 7900 XT",
            services = listOf(
                NodeService("Command Center", 3099),
                NodeService("vLLM", 8000),
                NodeService("KVM Operator", 5000),
            )
        ),
        Node(
            id = "node-b",
            name = "Node B — Unraid",
            role = "LiteLLM / Infra Gateway",
            ip = "192.168.1.222",
            port = 4000,
            hardware = "Unraid Server",
            services = listOf(
                NodeService("LiteLLM", 4000),
                NodeService("Uptime Kuma", 3010),
                NodeService("Dozzle", 8888),
                NodeService("Homepage", 8010),
            )
        ),
        Node(
            id = "node-c",
            name = "Node C — Arc",
            role = "Ollama / Intel Arc",
            ip = "192.168.1.6",
            port = 11434,
            hardware = "Intel Arc A770",
            services = listOf(
                NodeService("Ollama", 11434),
                NodeService("Open WebUI", 3000),
            )
        ),
        Node(
            id = "node-d",
            name = "Node D — Home Asst",
            role = "Home Assistant",
            ip = "192.168.1.149",
            port = 8123,
            hardware = "Dedicated HA",
            services = listOf(
                NodeService("Home Assistant", 8123),
            )
        ),
        Node(
            id = "node-e",
            name = "Node E — Sentinel",
            role = "Vision / NVR Relay",
            ip = "192.168.1.116",
            port = 3005,
            hardware = "Surveillance Node",
            services = listOf(
                NodeService("Sentinel", 3005),
            )
        ),
    )
}
