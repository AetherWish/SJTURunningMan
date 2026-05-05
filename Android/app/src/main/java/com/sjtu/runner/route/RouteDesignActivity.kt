package com.sjtu.runner.route

import android.os.Bundle
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.lifecycleScope
import com.google.gson.Gson
import com.sjtu.runner.viewmodel.MainViewModel
import kotlinx.coroutines.launch

class RouteDesignActivity : ComponentActivity() {

    companion object {
        const val EXTRA_ROUTE_SAVED = "route_saved"
        const val EXTRA_ROUTE_NAME = "route_name"
        const val EXTRA_ROUTE_POINTS = "route_points"
    }

    private lateinit var routeManager: RouteManager
    private lateinit var webView: WebView
    private var isSaving = false

    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        routeManager = RouteManager(this)

        setContent {
            MaterialTheme {
                RouteDesignScreen(
                    onBackPressed = { finish() }
                )
            }
        }
    }

    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    private fun RouteDesignScreen(onBackPressed: () -> Unit) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text("设计路线", color = MaterialTheme.colorScheme.onPrimaryContainer) },
                    navigationIcon = {
                        IconButton(onClick = onBackPressed) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer,
                        titleContentColor = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                )
            }
        ) { paddingValues ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
            ) {
                AndroidView(
                    factory = { context ->
                        WebView(context).apply {
                            layoutParams = ViewGroup.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT
                            )
                            settings.javaScriptEnabled = true
                            settings.domStorageEnabled = true
                            settings.loadWithOverviewMode = true
                            settings.useWideViewPort = true

                            webViewClient = WebViewClient()

                            addJavascriptInterface(AndroidBridge(), "AndroidInterface")

                            // 加载 assets 中的 HTML
                            loadUrl("file:///android_asset/route_design.html")
                        }.also { webView = it }
                    },
                    modifier = Modifier.fillMaxSize()
                )
            }
        }
    }

    inner class AndroidBridge {
        @JavascriptInterface
        fun onSaveRoute(routeName: String, pointsJson: String) {
            if (isSaving) return
            isSaving = true

            runOnUiThread {
                lifecycleScope.launch {
                    try {
                        val points = parsePointsJson(pointsJson)
                        if (points.isEmpty()) {
                            Toast.makeText(this@RouteDesignActivity, "坐标点无效", Toast.LENGTH_SHORT).show()
                            return@launch
                        }

                        val route = routeManager.saveCustomRoute(routeName, points)
                        if (route != null) {
                            Toast.makeText(
                                this@RouteDesignActivity,
                                "路线「${route.name}」保存成功！共${points.size}个点",
                                Toast.LENGTH_LONG
                            ).show()

                            val intent = intent.apply {
                                putExtra(EXTRA_ROUTE_SAVED, true)
                                putExtra(EXTRA_ROUTE_NAME, route.name)
                            }
                            setResult(RESULT_OK, intent)
                            finish()
                        } else {
                            Toast.makeText(this@RouteDesignActivity, "保存失败", Toast.LENGTH_SHORT).show()
                        }
                    } catch (e: Exception) {
                        Toast.makeText(this@RouteDesignActivity, "保存出错: ${e.message}", Toast.LENGTH_SHORT).show()
                    } finally {
                        isSaving = false
                    }
                }
            }
        }
    }

    private fun parsePointsJson(json: String): List<Pair<Double, Double>> {
        val gson = Gson()
        val type = object : com.google.gson.reflect.TypeToken<List<Map<String, Double>>>() {}.type
        val pointsList: List<Map<String, Double>> = gson.fromJson(json, type)
        return pointsList.mapNotNull { point ->
            val lng = point["lng"]
            val lat = point["lat"]
            if (lng != null && lat != null) lng to lat else null
        }
    }
}