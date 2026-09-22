package com.mustafacanyucel.firefly_shortcuts

import android.content.Context
  import android.content.SharedPreferences
  import androidx.work.*
  import kotlinx.coroutines.Dispatchers
  import kotlinx.coroutines.withContext
  import okhttp3.MediaType.Companion.toMediaType
  import okhttp3.OkHttpClient
  import okhttp3.Request
  import okhttp3.RequestBody.Companion.toRequestBody
  import org.json.JSONArray
  import org.json.JSONObject
  import java.io.IOException
  import java.time.OffsetDateTime
  import java.time.format.DateTimeFormatter
  import java.time.temporal.ChronoUnit
  import java.util.concurrent.TimeUnit

  class ShortcutExecuteWorker(
      private val context: Context,
      params: WorkerParameters
  ) : CoroutineWorker(context, params) {

      companion object {
          const val KEY_SHORTCUT_ID = "shortcut_id"
          const val KEY_DATE = "date"

          private const val MAX_ATTEMPTS = 3
          // Firefly's 422 message when error_if_duplicate_hash matches.
          private const val DUPLICATE_MESSAGE = "Duplicate of transaction"

          private val client = OkHttpClient()
      }

      override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
          val shortcutId = inputData.getInt(KEY_SHORTCUT_ID, -1)
          if (shortcutId == -1) return@withContext Result.failure()

          val prefs = context.getSharedPreferences(
              ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE
          )

          val outcome = try {
              attempt(prefs, shortcutId)
          } catch (e: IOException) {
              // Includes timeouts after the request was sent. Retrying is
              // safe: the body is identical and Firefly rejects duplicates.
              Outcome.TRANSIENT
          } catch (e: Exception) {
              Outcome.FAILED
          }

          if (outcome == Outcome.TRANSIENT && runAttemptCount < MAX_ATTEMPTS - 1) {
              return@withContext Result.retry()
          }
          val success = outcome == Outcome.SUCCESS
          setState(shortcutId, if (success) "success" else "error")
          scheduleReset(shortcutId)
          if (success) Result.success() else Result.failure()
      }

      private enum class Outcome { SUCCESS, FAILED, TRANSIENT }

      private fun attempt(prefs: SharedPreferences, shortcutId: Int): Outcome {
          val serverUrl = prefs.getString("server_url", "") ?: ""
          val token = WidgetToken.read(prefs) ?: ""
          // Transaction fields come only from app-private storage, never from
          // the triggering intent.
          val shortcut = findShortcut(prefs.getString("shortcuts", "[]") ?: "[]", shortcutId)

          // Covers a missing or expired token, and a 401 seen earlier: the
          // request would fail, and only the app can get a new token.
          if (serverUrl.isEmpty() || shortcut == null || token.isEmpty() ||
              ShortcutWidgetProvider.needsReauth(prefs)) {
              return Outcome.FAILED
          }

          val date = inputData.getString(KEY_DATE) ?: OffsetDateTime.now()
              .truncatedTo(ChronoUnit.SECONDS)
              .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
          val request = Request.Builder()
              .url("$serverUrl/api/v1/transactions")
              .post(buildBody(shortcut, date).toRequestBody("application/json".toMediaType()))
              .addHeader("Authorization", "Bearer $token")
              .addHeader("Accept", "application/vnd.api+json")
              .build()

          return client.newCall(request).execute().use { response ->
              when {
                  response.isSuccessful -> Outcome.SUCCESS
                  response.code == 401 -> {
                      markNeedsReauth()
                      Outcome.FAILED
                  }
                  // An earlier attempt of this tap already created it.
                  response.code == 422 &&
                      response.body?.string()?.contains(DUPLICATE_MESSAGE) == true ->
                      Outcome.SUCCESS
                  response.code == 408 || response.code == 429 || response.code >= 500 ->
                      Outcome.TRANSIENT
                  else -> Outcome.FAILED
              }
          }
      }

      private fun findShortcut(json: String, id: Int): JSONObject? {
          val array = try { JSONArray(json) } catch (_: Exception) { return null }
          return (0 until array.length())
              .map { array.getJSONObject(it) }
              .firstOrNull { it.optInt("id", -1) == id }
      }

      private fun buildBody(s: JSONObject, date: String): String {
          val item = JSONObject().apply {
              put("type", s.getString("type"))
              put("date", date)
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
          return JSONObject()
              .put("error_if_duplicate_hash", true)
              .put("transactions", JSONArray().put(item))
              .toString()
      }

      // Cleared when the app pushes a new token.
      private fun markNeedsReauth() {
          context.getSharedPreferences(ShortcutWidgetProvider.PREFS_NAME, Context.MODE_PRIVATE)
              .edit().putBoolean(ShortcutWidgetProvider.KEY_NEEDS_REAUTH, true).apply()
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