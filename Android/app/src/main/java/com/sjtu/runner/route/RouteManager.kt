package com.sjtu.runner.route

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class RouteManager(private val context: Context) {

    companion object {
        private const val PREF_NAME = "route_prefs"
        private const val KEY_ROUTES = "custom_routes"
        private const val DEFAULT_ROUTE_ID = "default"
        private const val DEFAULT_ROUTE_NAME = "思源湖路线"
        private const val ROUTES_DIR = "routes"
    }

    private val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    private val gson = Gson()
    private val routesDir = File(context.filesDir, ROUTES_DIR).apply {
        if (!exists()) mkdirs()
    }

    // 获取默认路线
    fun getDefaultRoute(): RouteInfo {
        return RouteInfo(
            id = DEFAULT_ROUTE_ID,
            name = DEFAULT_ROUTE_NAME,
            filePath = "",
            isDefault = true,
            pointCount = getDefaultRoutePointCount()
        )
    }

    // 获取所有自定义路线
    suspend fun getCustomRoutes(): List<RouteInfo> = withContext(Dispatchers.IO) {
        val json = prefs.getString(KEY_ROUTES, "[]")
        val type = object : TypeToken<List<RouteInfo>>() {}.type
        val routes: List<RouteInfo> = gson.fromJson(json, type)
        // 更新每个路线的点数量
        routes.map { route ->
            route.copy(pointCount = getRoutePointCount(route))
        }
    }

    // 获取所有路线（默认+自定义）
    suspend fun getAllRoutes(): List<RouteInfo> = withContext(Dispatchers.IO) {
        val customRoutes = getCustomRoutes()
        listOf(getDefaultRoute()) + customRoutes
    }

    // 保存自定义路线
    suspend fun saveCustomRoute(name: String, coordinates: List<Pair<Double, Double>>): RouteInfo? = withContext(Dispatchers.IO) {
        if (name.isBlank() || coordinates.isEmpty()) return@withContext null

        // 生成唯一文件名
        val fileName = "${name}_${System.currentTimeMillis()}.txt"
        val routeFile = File(routesDir, fileName)

        // 保存坐标到文件
        val success = routeFile.writeCoordinates(coordinates)
        if (!success) return@withContext null

        val routeId = routeFile.nameWithoutExtension
        val newRoute = RouteInfo(
            id = routeId,
            name = name,
            filePath = routeFile.absolutePath,
            isDefault = false,
            pointCount = coordinates.size
        )

        // 更新自定义路线列表
        val currentRoutes = getCustomRoutes().toMutableList()
        currentRoutes.add(newRoute)
        saveRouteList(currentRoutes)

        return@withContext newRoute
    }

    // 删除自定义路线
    suspend fun deleteRoute(routeId: String): Boolean = withContext(Dispatchers.IO) {
        val currentRoutes = getCustomRoutes().toMutableList()
        val routeToDelete = currentRoutes.find { it.id == routeId } ?: return@withContext false

        // 删除文件
        val file = File(routeToDelete.filePath)
        if (file.exists()) file.delete()

        // 更新列表
        currentRoutes.remove(routeToDelete)
        saveRouteList(currentRoutes)

        return@withContext true
    }

    // 获取路线的坐标点列表
    suspend fun getRouteCoordinates(route: RouteInfo): List<Pair<Double, Double>> = withContext(Dispatchers.IO) {
        if (route.isDefault) {
            return@withContext readDefaultRouteCoordinates()
        }
        val file = File(route.filePath)
        if (!file.exists()) return@withContext emptyList()
        file.readCoordinates()
    }

    // 获取路线点数（用于显示）
    private fun getRoutePointCount(route: RouteInfo): Int {
        if (route.isDefault) return getDefaultRoutePointCount()
        val file = File(route.filePath)
        if (!file.exists()) return 0
        return file.useLines { it.count() }
    }

    private fun getDefaultRoutePointCount(): Int {
        return try {
            context.resources.openRawResource(
                context.resources.getIdentifier("route_coordinates", "raw", context.packageName)
            ).bufferedReader().useLines { it.count() }
        } catch (e: Exception) {
            0
        }
    }

    private suspend fun readDefaultRouteCoordinates(): List<Pair<Double, Double>> = withContext(Dispatchers.IO) {
        val list = mutableListOf<Pair<Double, Double>>()
        try {
            context.resources.openRawResource(
                context.resources.getIdentifier("route_coordinates", "raw", context.packageName)
            ).bufferedReader().use { reader ->
                reader.lineSequence().forEach { line ->
                    val parts = line.trim().split(",")
                    if (parts.size == 2) {
                        list.add(parts[0].toDouble() to parts[1].toDouble())
                    }
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        list
    }

    private fun saveRouteList(routes: List<RouteInfo>) {
        val json = gson.toJson(routes)
        prefs.edit().putString(KEY_ROUTES, json).apply()
    }

    // 扩展函数：写入坐标到文件
    private fun File.writeCoordinates(coordinates: List<Pair<Double, Double>>): Boolean {
        return try {
            writeText(buildString {
                coordinates.forEach { (lng, lat) ->
                    appendLine("$lng,$lat")
                }
            })
            true
        } catch (e: Exception) {
            false
        }
    }

    // 扩展函数：从文件读取坐标
    private fun File.readCoordinates(): List<Pair<Double, Double>> {
        val list = mutableListOf<Pair<Double, Double>>()
        forEachLine { line ->
            val parts = line.trim().split(",")
            if (parts.size == 2) {
                list.add(parts[0].toDouble() to parts[1].toDouble())
            }
        }
        return list
    }
}