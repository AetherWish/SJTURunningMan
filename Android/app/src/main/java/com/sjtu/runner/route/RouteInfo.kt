package com.sjtu.runner.route

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class RouteInfo(
    val id: String,
    val name: String,
    val filePath: String,
    val isDefault: Boolean = false,
    val pointCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis()
) : Parcelable