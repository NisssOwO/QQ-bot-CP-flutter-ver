package com.shinycolors.officialbot

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/** Builds the ongoing runtime notification shared by the service and the stage recorder. */
class RuntimeNotifier(private val context: Context) {
    fun channel(): String {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "QQ-bot-CP Runtime", NotificationManager.IMPORTANCE_LOW))
        return CHANNEL
    }

    fun build(text: String): Notification {
        val open = PendingIntent.getActivity(context, 1002, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getBroadcast(context, 1003, Intent(context, RuntimeActionReceiver::class.java).setAction(RuntimeActionReceiver.ACTION_STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val restart = PendingIntent.getBroadcast(context, 1004, Intent(context, RuntimeActionReceiver::class.java).setAction(RuntimeActionReceiver.ACTION_RESTART), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(context, channel())
            .setContentTitle("QQ-bot-CP")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "重启 Runtime", restart).build())
            .addAction(Notification.Action.Builder(null, "停止 Runtime", stop).build())
            .build()
    }

    fun show(text: String) = post(ID, build(text))

    fun update(text: String) = show(text)

    fun post(id: Int, notification: Notification) {
        try {
            context.getSystemService(NotificationManager::class.java).notify(id, notification)
        } catch (_: SecurityException) {
            // Notification permission may be denied; the in-app state still updates.
        }
    }

    companion object {
        const val CHANNEL = "runtime"
        const val ID = 1001
    }
}