package com.mustafacanyucel.firefly_shortcuts

import android.content.Context
  import androidx.work.*
  import kotlinx.coroutines.Dispatchers
  import kotlinx.coroutines.withContext
  import okhttp3.MediaType.Companion.toMediaType
  import okhttp3.OkHttpClient
  import okhttp3.Request
  import okhttp3.RequestBody.Companion.toRequestBody
  import org.json.JSONArray
  import org.json.JSONObject
  import java.time.LocalDateTime
  import java.time.format.DateTimeFormatter
  import java.util.concurrent.TimeUnit

  class ShortcutExecuteWorker(
      private val context: Context,
      params: WorkerParameters
  ) : CoroutineWorker(context, params) {

      companion object {
          const val KEY_SHORTCUT_ID = "shortcut_id"
      }

      override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
          val shortcutId = inputData.getInt(KEY_SHORTCUT_ID, -1)
          if (shortcutId == -1) return@withContext Result.failure()

          val prefs = context.getSharedPreferences(
              ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
          )
          val serverUrl = prefs.getString("server_url", "") ?: ""
          val token = prefs.getString("access_token", "") ?: ""
          // Transaction fields come only from app-private storage, never from
          // the triggering intent.
          val shortcut = findShortcut(prefs.getString("shortcuts", "[]") ?: "[]", shortcutId)

          if (serverUrl.isEmpty() || token.isEmpty() || shortcut == null) {
              setState(shortcutId, "error")
              scheduleReset(shortcutId)
              return@withContext Result.failure()
          }

          try {
              val body = buildBody(shortcut)

              val response = OkHttpClient().newCall(
                  Request.Builder()
                      .url("$serverUrl/api/v1/transactions")
                      .post(body.toRequestBody("application/json".toMediaType()))
                      .addHeader("Authorization", "Bearer $token")
                      .addHeader("Accept", "application/vnd.api+json")
                      .build()
              ).execute()

              val success = response.isSuccessful
              setState(shortcutId, if (success) "success" else "error")
              scheduleReset(shortcutId)
              if (success) Result.success() else Result.failure()
          } catch (e: Exception) {
              setState(shortcutId, "error")
              scheduleReset(shortcutId)
              Result.failure()
          }
      }

      private fun findShortcut(json: String, id: Int): JSONObject? {
          val array = try { JSONArray(json) } catch (_: Exception) { return null }
          return (0 until array.length())
              .map { array.getJSONObject(it) }
              .firstOrNull { it.optInt("id", -1) == id }
      }

      private fun buildBody(s: JSONObject): String {
          val item = JSONObject().apply {
              put("type", s.getString("type"))
              put("date", LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME))
              put("amount", s.getString("amount"))
              put("description", s.optString("description").ifEmpty { s.getString("name") })
              put("source_id", s.getString("fromAccountId"))
              put("source_name", s.getString("fromAccountName"))
              put("destination_id", s.getString("toAccountId"))
              put("destination_name", s.getString("toAccountName"))
              fun putIfPresent(key: String, jsonKey: String) {
                  val v = s.optString(key)
                  if (v.isNotEmpty() && v != "null") put(jsonKey, v)
              }
              putIfPresent("categoryId", "category_id")
              putIfPresent("budgetId", "budget_id")
              putIfPresent("billId", "bill_id")
              putIfPresent("piggybankId", "piggy_bank_id")
              s.optJSONArray("tags")?.takeIf { it.length() > 0 }?.let { put("tags", it) }
          }
          return JSONObject().put("transactions", JSONArray().put(item)).toString()
      }

      private fun setState(shortcutId: Int, state: String) {
          context.getSharedPreferences(ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
              .edit().putString("${ShortcutWidgetProvider.KEY_STATE_PREFIX}$shortcutId", state)
              .apply()
          ShortcutWidgetProvider.updateAllWidgets(context)
      }

      private fun scheduleReset(shortcutId: Int) {
          WorkManager.getInstance(context).enqueue(
              OneTimeWorkRequestBuilder<ShortcutStateResetWorker>()
                  .setInitialDelay(5, TimeUnit.SECONDS)
                  .setInputData(workDataOf(ShortcutStateResetWorker.KEY_SHORTCUT_ID to shortcutId))
                  .build()
          )
      }
  }