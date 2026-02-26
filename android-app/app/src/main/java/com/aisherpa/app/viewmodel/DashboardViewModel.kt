package com.aisherpa.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aisherpa.app.data.api.ApiClient
import com.aisherpa.app.data.model.LabNodes
import com.aisherpa.app.data.model.Node
import com.aisherpa.app.data.model.NodeService
import com.aisherpa.app.data.model.NodeStatus
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.URL

class DashboardViewModel : ViewModel() {

    private val _nodes = MutableStateFlow(LabNodes.ALL)
    val nodes: StateFlow<List<Node>> = _nodes.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _lastRefresh = MutableStateFlow("")
    val lastRefresh: StateFlow<String> = _lastRefresh.asStateFlow()

    init {
        refreshAll()
    }

    fun refreshAll() {
        viewModelScope.launch {
            _isRefreshing.value = true
            val updated = _nodes.value.map { node ->
                checkNode(node)
            }
            _nodes.value = updated
            _lastRefresh.value = java.text.SimpleDateFormat(
                "HH:mm:ss", java.util.Locale.getDefault()
            ).format(java.util.Date())
            _isRefreshing.value = false
        }
    }

    private suspend fun checkNode(node: Node): Node {
        val updatedServices = node.services.map { service ->
            checkService(node.ip, service)
        }
        val overallStatus = when {
            updatedServices.isEmpty() -> NodeStatus.UNKNOWN
            updatedServices.all { it.status == NodeStatus.ONLINE } -> NodeStatus.ONLINE
            updatedServices.all { it.status == NodeStatus.OFFLINE } -> NodeStatus.OFFLINE
            else -> NodeStatus.WARNING
        }
        return node.copy(status = overallStatus, services = updatedServices)
    }

    private suspend fun checkService(ip: String, service: NodeService): NodeService {
        return try {
            val url = URL("http://$ip:${service.port}/")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 3000
            conn.readTimeout = 3000
            conn.requestMethod = "GET"
            val code = conn.responseCode
            conn.disconnect()
            service.copy(
                status = if (code in 200..499) NodeStatus.ONLINE else NodeStatus.WARNING,
                url = "http://$ip:${service.port}"
            )
        } catch (_: Exception) {
            service.copy(status = NodeStatus.OFFLINE, url = "http://$ip:${service.port}")
        }
    }

    fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(30_000) // refresh every 30s
                refreshAll()
            }
        }
    }
}
