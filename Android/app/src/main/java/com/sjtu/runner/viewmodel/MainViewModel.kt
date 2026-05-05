package com.sjtu.runner.viewmodel

import android.app.Application
import android.content.Intent
import android.webkit.CookieManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.sjtu.runner.data.DataGenerator
import com.sjtu.runner.login.LoginActivity
import com.sjtu.runner.network.ApiService
import com.sjtu.runner.route.RouteInfo
import com.sjtu.runner.route.RouteManager
import com.sjtu.runner.utils.GpsUtil
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlin.random.Random

class MainViewModel(application: Application) : AndroidViewModel(application) {

    private val api = ApiService(application)
    private val routeManager = RouteManager(application)

    var onReloginRequired: (() -> Unit)? = null

    private val _log = MutableStateFlow("")
    val log: StateFlow<String> = _log

    private val _running = MutableStateFlow(false)
    val running: StateFlow<Boolean> = _running

    // 路线相关状态
    private val _routes = MutableStateFlow<List<RouteInfo>>(emptyList())
    val routes: StateFlow<List<RouteInfo>> = _routes

    private val _selectedRoute = MutableStateFlow<RouteInfo?>(null)
    val selectedRoute: StateFlow<RouteInfo?> = _selectedRoute

    private var job: Job? = null

    init {
        loadRoutes()
    }

    fun loadRoutes() {
        viewModelScope.launch {
            val allRoutes = routeManager.getAllRoutes()
            _routes.value = allRoutes
            // 如果没有选中路线，默认选中默认路线
            if (_selectedRoute.value == null && allRoutes.isNotEmpty()) {
                _selectedRoute.value = allRoutes.firstOrNull { it.isDefault } ?: allRoutes.first()
            }
        }
    }

    fun selectRoute(route: RouteInfo) {
        _selectedRoute.value = route
        logMsg("已选择路线: ${route.name}")
    }

    fun deleteRoute(route: RouteInfo) {
        if (route.isDefault) {
            logMsg("默认路线不能删除")
            return
        }
        viewModelScope.launch {
            val success = routeManager.deleteRoute(route.id)
            if (success) {
                logMsg("已删除路线: ${route.name}")
                loadRoutes() // 刷新列表
                // 如果删除的是当前选中的路线，切换到默认路线
                if (_selectedRoute.value?.id == route.id) {
                    _selectedRoute.value = _routes.value.firstOrNull { it.isDefault }
                }
            } else {
                logMsg("删除路线失败")
            }
        }
    }

    fun refreshRoutes() {
        loadRoutes()
    }

    private suspend fun getCurrentRouteCoordinates(): List<Pair<Double, Double>> {
        val route = _selectedRoute.value ?: return emptyList()
        return if (route.isDefault) {
            GpsUtil.readCoordinates(getApplication())
        } else {
            val file = File(route.filePath)
            if (file.exists()) {
                GpsUtil.readCoordinatesFromFile(file)
            } else {
                logMsg("路线文件不存在，使用默认路线")
                GpsUtil.readCoordinates(getApplication())
            }
        }
    }

    fun startUpload(
        days: Int,
        distanceKm: Int,
        hour: Int,
        minute: Int,
        dateStr: String?
    ) {
        job = viewModelScope.launch(Dispatchers.IO) {
            _running.value = true
            _log.value = ""

            try {
                // 检查是否选中路线
                val selected = _selectedRoute.value
                if (selected == null) {
                    logMsg("未选择任何路线，请先选择路线")
                    return@launch
                }
                logMsg("使用路线: ${selected.name}")

                logMsg("步骤1: 获取坐标路线...")
                val coordinates = getCurrentRouteCoordinates()
                if (coordinates.isEmpty()) {
                    logMsg("路线坐标为空，请选择其他路线")
                    return@launch
                }
                logMsg("路线点数量: ${coordinates.size}")

                logMsg("步骤2: 获取 UID...")
                val uid = api.getUid()
                if (uid == null) {
                    logMsg("UID 获取失败，可能cookie已过期，尝试重新登录...")
                    triggerRelogin()
                    return@launch
                }
                logMsg("UID 获取成功: $uid")

                val targetDistanceM = distanceKm * 1000

                val startDate = if (dateStr.isNullOrBlank()) {
                    LocalDate.now().minusDays(1)
                } else {
                    LocalDate.parse(dateStr, DateTimeFormatter.ISO_LOCAL_DATE)
                }

                for (i in 0 until days) {
                    if (!_running.value) break

                    val date = startDate.minusDays(i.toLong())

                    val randomOffsetSec = Random.nextLong(-600, 601)

                    val startTimeInstant = date.atTime(hour, minute)
                        .atZone(java.time.ZoneId.systemDefault())
                        .toInstant()
                        .plusSeconds(randomOffsetSec)

                    val startTimeMs = startTimeInstant.toEpochMilli()
                    val displayTime = startTimeInstant.atZone(java.time.ZoneId.systemDefault())
                        .format(DateTimeFormatter.ofPattern("HH:mm:ss"))

                    logMsg("生成第 ${i + 1}/$days 条数据 ($date $displayTime)...")
                    val (payload, actualDist) = DataGenerator.generate(
                        coordinates,
                        uid,
                        targetDistanceM,
                        startTimeMs,
                        intervalSeconds = 3,
                        log = { msg -> logMsg(msg) }
                    )
                    logMsg("实际距离: ${String.format("%.2f", actualDist)} m")

                    logMsg("上传第 ${i + 1}/$days 条...")
                    val result = api.upload(uid, payload)

                    if (result.success) {
                        logMsg("第 ${i + 1} 条上传成功")
                    } else {
                        if (result.needRelogin) {
                            logMsg("上传失败: ${result.message}，尝试重新登录...")
                            triggerRelogin()
                            break
                        } else {
                            logMsg("失败: ${result.message}")
                        }
                    }
                }
                logMsg("全部任务完成")
            } catch (e: CancellationException) {
                logMsg("任务已手动停止")
            } catch (e: Exception) {
                logMsg("错误: ${e.message}")
            } finally {
                _running.value = false
            }
        }
    }

    fun stopUpload() {
        job?.cancel()
        _running.value = false
    }

    private fun logMsg(msg: String) {
        viewModelScope.launch(Dispatchers.Main) {
            _log.value = _log.value + "\n${java.time.LocalTime.now().withNano(0)} $msg"
        }
    }

    private fun triggerRelogin() {
        viewModelScope.launch(Dispatchers.Main) {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            onReloginRequired?.invoke()
        }
    }
}