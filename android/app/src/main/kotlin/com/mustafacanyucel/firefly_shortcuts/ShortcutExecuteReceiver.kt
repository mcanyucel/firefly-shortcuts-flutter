package com.mustafacanyucel.firefly_shortcuts

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit

// Not exported: only reachable through the widget's PendingIntent, which is
// sent with this app's identity. Kept separate from ShortcutWidgetProvider
// because that one must stay exported to receive APPWIDGET_UPDATE.
class ShortcutExecuteReceiver : BroadcastReceiver() {

    companion object {
        const val EXTRA_SHORTCUT_ID = "shortcut_id"

        // Well above the worker's worst case of three attempts with backoff.
        // Past this, "executing" is assumed stuck (process killed, work
        // cancelled) and a tap starts over instead of being ignored forever.
        private val STALE_AFTER_MS = TimeUnit.MINUTES.toMillis(5)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val shortcutId = intent.getIntExtra(EXTRA_SHORTCUT_ID, -1)
        if (shortcutId == -1) return

        val prefs = context.getSharedPreferences(
            ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
        )
        val stateKey = "${ShortcutWidgetProvider.KEY_STATE_PREFIX}$shortcutId"
        val startedKey = "${ShortcutWidgetProvider.KEY_STARTED_PREFIX}$shortcutId"
        val now = System.currentTimeMillis()
        val stale = now - prefs.getLong(startedKey, 0L) > STALE_AFTER_MS
        when (prefs.getString(stateKey, "idle")) {
            "idle" -> {}
            "executing" -> if (!stale) return
            else -> return
        }

        prefs.edit()
            .putString(stateKey, "executing")
            .putLong(startedKey, now)
            .apply()
        ShortcutWidgetProvider.updateAllWidgets(context)

        // Fixed per tap, so every retry of this tap sends an identical body
        // and Firefly's duplicate check can recognise a request that already
        // went through.
        val date = OffsetDateTime.now()
            .truncatedTo(ChronoUnit.SECONDS)
            .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

        WorkManager.getInstance(context).enqueueUniqueWork(
            "execute_shortcut_$shortcutId",
            // Only reached when idle or stale, so anything still queued
            // under this name is stuck.
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<ShortcutExecuteWorker>()
                .setInputData(workDataOf(
                    ShortcutExecuteWorker.KEY_SHORTCUT_ID to shortcutId,
                    ShortcutExecuteWorker.KEY_DATE to date,
                ))
                .setBackoffCriteria(BackoffPolicy.LINEAR, 10, TimeUnit.SECONDS)
                .build()
        )
    }
}
