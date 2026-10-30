package com.shinycolors.officialbot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class RuntimeActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == ACTION_STOP) {
            context.stopService(Intent(context, RuntimeService::class.java))
        }
    }

    companion object {
        const val ACTION_STOP = "com.shinycolors.officialbot.action.STOP_RUNTIME"
    }
}
