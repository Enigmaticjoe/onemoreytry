package com.aisherpa.app.viewmodel

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aisherpa.app.BuildConfig
import com.aisherpa.app.data.api.ApiClient
import com.aisherpa.app.data.model.KvmHealthResponse
import com.aisherpa.app.data.model.KvmPowerRequest
import com.aisherpa.app.data.model.KvmTarget
import com.aisherpa.app.data.model.KvmTaskRequest
import com.aisherpa.app.data.model.PowerState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class KvmViewModel : ViewModel() {

    private val _targets = MutableStateFlow<List<KvmTarget>>(emptyList())
    val targets: StateFlow<List<KvmTarget>> = _targets.asStateFlow()

    private val _selectedTarget = MutableStateFlow<String?>(null)
    val selectedTarget: StateFlow<String?> = _selectedTarget.asStateFlow()

    private val _snapshot = MutableStateFlow<ImageBitmap?>(null)
    val snapshot: StateFlow<ImageBitmap?> = _snapshot.asStateFlow()

    private val _health = MutableStateFlow<KvmHealthResponse?>(null)
    val health: StateFlow<KvmHealthResponse?> = _health.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _statusMessage = MutableStateFlow("")
    val statusMessage: StateFlow<String> = _statusMessage.asStateFlow()

    private val _taskLog = MutableStateFlow<List<String>>(emptyList())
    val taskLog: StateFlow<List<String>> = _taskLog.asStateFlow()

    private var kvmBaseUrl = BuildConfig.DEFAULT_KVM_OPERATOR_URL
    private var kvmToken = ""

    fun updateConfig(baseUrl: String, token: String) {
        kvmBaseUrl = baseUrl
        kvmToken = token
    }

    private fun authHeader(): String = "Bearer $kvmToken"

    fun loadHealth() {
        viewModelScope.launch {
            try {
                val api = ApiClient.createKvmService(kvmBaseUrl)
                val h = api.health()
                _health.value = h
                _targets.value = h.targets.map { name ->
                    KvmTarget(name = name, ip = "")
                }
                if (h.targets.isNotEmpty() && _selectedTarget.value == null) {
                    _selectedTarget.value = h.targets.first()
                }
                _statusMessage.value = "KVM Operator v${h.version} — ${h.targets.size} target(s)"
            } catch (e: Exception) {
                _statusMessage.value = "Cannot reach KVM Operator: ${e.message}"
                _health.value = null
            }
        }
    }

    fun loadTargets() {
        viewModelScope.launch {
            try {
                val api = ApiClient.createKvmService(kvmBaseUrl)
                val resp = api.getTargets(authHeader())
                _targets.value = resp.targets.map { (name, info) ->
                    KvmTarget(name = name, ip = info.ip)
                }
            } catch (e: Exception) {
                _statusMessage.value = "Failed to load targets: ${e.message}"
            }
        }
    }

    fun selectTarget(targetName: String) {
        _selectedTarget.value = targetName
        _snapshot.value = null
        captureSnapshot()
    }

    fun captureSnapshot() {
        val target = _selectedTarget.value ?: return
        _isLoading.value = true

        viewModelScope.launch {
            try {
                val api = ApiClient.createKvmService(kvmBaseUrl)
                val resp = api.getSnapshot(target, authHeader())
                if (resp.ok && resp.jpeg_b64.isNotEmpty()) {
                    val bytes = Base64.decode(resp.jpeg_b64, Base64.DEFAULT)
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    _snapshot.value = bmp?.asImageBitmap()
                    _statusMessage.value = "Snapshot captured from $target"
                }
            } catch (e: Exception) {
                _statusMessage.value = "Snapshot failed: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun powerAction(action: String) {
        val target = _selectedTarget.value ?: return
        _isLoading.value = true

        viewModelScope.launch {
            try {
                val api = ApiClient.createKvmService(kvmBaseUrl)
                api.powerAction(target, KvmPowerRequest(action), authHeader())
                _statusMessage.value = "Power $action sent to $target"
                addLog("POWER $action -> $target")
            } catch (e: Exception) {
                _statusMessage.value = "Power action failed: ${e.message}"
                addLog("ERROR: Power $action failed — ${e.message}")
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun runTask(instruction: String, maxSteps: Int = 10) {
        val target = _selectedTarget.value ?: return
        _isLoading.value = true
        addLog("TASK: \"$instruction\" on $target (max $maxSteps steps)")

        viewModelScope.launch {
            try {
                val api = ApiClient.createKvmService(kvmBaseUrl)
                val resp = api.runTask(target, KvmTaskRequest(instruction, maxSteps), authHeader())
                _statusMessage.value = "Task ${resp.status}: ${resp.history.size} step(s)"
                addLog("RESULT: ${resp.status} — ${resp.history.size} step(s)")
                if (resp.error != null) {
                    addLog("NOTE: ${resp.error}")
                }
            } catch (e: Exception) {
                _statusMessage.value = "Task failed: ${e.message}"
                addLog("ERROR: ${e.message}")
            } finally {
                _isLoading.value = false
            }
        }
    }

    private fun addLog(entry: String) {
        val ts = java.text.SimpleDateFormat(
            "HH:mm:ss", java.util.Locale.getDefault()
        ).format(java.util.Date())
        _taskLog.value = _taskLog.value + "[$ts] $entry"
    }

    fun clearLog() {
        _taskLog.value = emptyList()
    }
}
