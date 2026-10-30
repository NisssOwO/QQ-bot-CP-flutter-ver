package com.shinycolors.officialbot

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class RuntimeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        update(context, manager, ids)
    }

    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, RuntimeWidgetProvider::class.java)
            update(context, manager, manager.getAppWidgetIds(component))
        }

        private fun update(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val prefs = context.getSharedPreferences(RuntimeService.PREFS, Context.MODE_PRIVATE)
            val status = prefs.getString("status", "stopped") ?: "stopped"
            val phase = prefs.getString("phase", "未启动") ?: "未启动"
            val message = prefs.getString("message", "") ?: ""
            val views = RemoteViews(context.packageName, R.layout.widget_runtime).apply {
                setTextViewText(R.id.widget_status, statusLabel(status))
                setTextViewText(R.id.widget_phase, "$phase：$message")
                val intent = Intent(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
            ids.forEach { manager.updateAppWidget(it, views) }
        }

        private fun statusLabel(value: String) = when (value) {
            "online" -> "运行中"
            "starting" -> "启动中"
            "reconnecting" -> "重连中"
            "failed" -> "异常"
            "stopping" -> "停止中"
            else -> "已停止"
        }
    }
}
