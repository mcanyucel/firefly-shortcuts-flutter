package com.mustafacanyucel.firefly_shortcuts

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

// Not exported: only reachable through the widget's PendingIntent, which is
// sent with this app's identity. Kept separate from ShortcutWidgetProvider
// because that one must stay exported to receive APPWIDGET_UPDATE.
class ShortcutExecuteReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_SHORTCUT_ID = "shortcut_id"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val shortcutId = intent.getIntExtra(EXTRA_SHORTCUT_ID, -1)
        if (shortcutId == -1) return

        val prefs = context.getSharedPreferences(
            ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
        )
        val currentState = prefs.getString("${ShortcutWidgetProvider.KEY_STATE_PREFIX}$shortcutId", "idle")
        if (currentState != "idle") return

        prefs.edit().putString("${ShortcutWidgetProvider.KEY_STATE_PREFIX}$shortcutId", "executing").apply()
        ShortcutWidgetProvider.updateAllWidgets(context)

        WorkManager.getInstance(context).enqueue(
            OneTimeWorkRequestBuilder<ShortcutExecuteWorker>()
                .setInputData(workDataOf(ShortcutExecuteWorker.KEY_SHORTCUT_ID to shortcutId))
                .build()
        )
    }
}
