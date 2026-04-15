package me.studyshare.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class ScheduleWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val TAG = "ScheduleWidgetProvider"
    }

    private data class ScheduleCard(
        val status: String,
        val title: String,
        val meta: String,
        val detail: String,
        val progress: Int,
        val progressLabel: String,
        val isLive: Boolean,
        val targetUri: String,
    )

    private fun launchPendingIntent(
        context: Context,
        uri: Uri? = null,
    ): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    private fun parseCards(widgetData: SharedPreferences): List<ScheduleCard> {
        val raw = widgetData.getString("schedule_cards_json", "[]") ?: "[]"
        val json = try {
            JSONArray(raw)
        } catch (error: Exception) {
            Log.e(TAG, "Failed to parse widget JSON", error)
            JSONArray()
        }

        val cards = mutableListOf<ScheduleCard>()
        for (index in 0 until json.length()) {
            val item = json.optJSONObject(index) ?: continue
            cards.add(
                ScheduleCard(
                    status = item.optString("status"),
                    title = item.optString("title"),
                    meta = item.optString("meta"),
                    detail = item.optString("detail"),
                    progress = item.optInt("progress", 0),
                    progressLabel = item.optString("progressLabel"),
                    isLive = item.optBoolean("isLive", false),
                    targetUri = item.optString(
                        "targetUri",
                        "studyshare://widget/schedule?view=attendance",
                    ),
                ),
            )
            if (cards.size == 3) break
        }

        return cards
    }

    private fun bindCard(
        views: RemoteViews,
        context: Context,
        containerId: Int,
        statusId: Int,
        titleId: Int,
        metaId: Int,
        detailId: Int,
        progressId: Int,
        progressLabelId: Int,
        card: ScheduleCard?,
    ) {
        if (card == null) {
            views.setViewVisibility(containerId, View.GONE)
            return
        }

        views.setViewVisibility(containerId, View.VISIBLE)
        views.setTextViewText(statusId, card.status)
        views.setTextViewText(titleId, card.title)
        views.setTextViewText(metaId, card.meta)
        views.setTextViewText(detailId, card.detail)
        views.setTextViewText(progressLabelId, card.progressLabel)
        views.setViewVisibility(statusId, if (card.status.isBlank()) View.GONE else View.VISIBLE)
        views.setViewVisibility(detailId, if (card.detail.isBlank()) View.GONE else View.VISIBLE)
        views.setViewVisibility(progressId, if (card.isLive) View.VISIBLE else View.GONE)
        views.setViewVisibility(
            progressLabelId,
            if (card.isLive && card.progressLabel.isNotBlank()) View.VISIBLE else View.GONE,
        )
        views.setProgressBar(progressId, 100, card.progress.coerceIn(0, 100), false)
        views.setTextColor(
            statusId,
            ContextCompat.getColor(
                context,
                if (card.isLive) R.color.widget_schedule_live_accent
                else R.color.widget_schedule_hint_text,
            ),
        )
        val validatedUri = validateTargetUri(card.targetUri)
        if (validatedUri != null) {
            views.setOnClickPendingIntent(
                containerId,
                launchPendingIntent(context, validatedUri),
            )
        }
    }

    private fun validateTargetUri(rawTargetUri: String): Uri? {
        val trimmed = rawTargetUri.trim()
        if (trimmed.isEmpty()) return null

        val parsed = try {
            Uri.parse(trimmed)
        } catch (_: Exception) {
            return null
        }

        val scheme = parsed.scheme?.lowercase() ?: return null
        return if (scheme == "studyshare" || scheme == "https" || scheme == "http") {
            parsed
        } else {
            null
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            val scheduleUri = Uri.parse("studyshare://widget/schedule?view=attendance")
            val cards = parseCards(widgetData)
            val hasCards = cards.isNotEmpty()
            val isLive = widgetData.getBoolean("schedule_is_live", false)
            val showHeroProgress =
                widgetData.getBoolean("schedule_hero_progress_visible", false)
            val heroProgress = widgetData.getInt("schedule_hero_progress", 0)

            val views = RemoteViews(context.packageName, R.layout.schedule_widget_layout).apply {
                setTextViewText(
                    R.id.widget_chip,
                    widgetData.getString("schedule_badge", "Live now"),
                )
                setTextViewText(
                    R.id.widget_location_label,
                    widgetData.getString(
                        "schedule_location_label",
                        "Current Class Location",
                    ),
                )
                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("schedule_room_label", "Open Schedule"),
                )
                setTextViewText(
                    R.id.widget_progress_label,
                    widgetData.getString("schedule_progress_label", ""),
                )
                setTextViewText(
                    R.id.widget_empty_message,
                    widgetData.getString(
                        "schedule_empty_message",
                        "No schedule data yet. Open StudyShare to connect attendance.",
                    ),
                )
                setTextViewText(
                    R.id.widget_swipe_hint,
                    widgetData.getString(
                        "schedule_footer_label",
                        "Tap to open schedule",
                    ),
                )
                setViewVisibility(
                    R.id.widget_live_dot,
                    if (isLive) View.VISIBLE else View.INVISIBLE,
                )
                setViewVisibility(
                    R.id.widget_progress_section,
                    if (showHeroProgress) View.VISIBLE else View.GONE,
                )
                setProgressBar(
                    R.id.widget_hero_progress,
                    100,
                    heroProgress.coerceIn(0, 100),
                    false,
                )
                setTextColor(
                    R.id.widget_chip,
                    ContextCompat.getColor(
                        context,
                        if (isLive) R.color.widget_schedule_live_accent
                        else R.color.widget_schedule_hint_text,
                    ),
                )
                setViewVisibility(
                    R.id.widget_cards_container,
                    if (hasCards) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_empty_message,
                    if (hasCards) View.GONE else View.VISIBLE,
                )
                setViewVisibility(
                    R.id.widget_swipe_hint,
                    if (hasCards) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_footer_row,
                    if (hasCards) View.VISIBLE else View.GONE,
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    launchPendingIntent(context, scheduleUri),
                )
                setOnClickPendingIntent(
                    R.id.widget_swipe_hint,
                    launchPendingIntent(context, scheduleUri),
                )

                bindCard(
                    views = this,
                    context = context,
                    containerId = R.id.widget_card_primary,
                    statusId = R.id.widget_card_primary_status,
                    titleId = R.id.widget_card_primary_title,
                    metaId = R.id.widget_card_primary_meta,
                    detailId = R.id.widget_card_primary_detail,
                    progressId = R.id.widget_card_primary_progress,
                    progressLabelId = R.id.widget_card_primary_progress_label,
                    card = cards.getOrNull(0),
                )
                bindCard(
                    views = this,
                    context = context,
                    containerId = R.id.widget_card_secondary,
                    statusId = R.id.widget_card_secondary_status,
                    titleId = R.id.widget_card_secondary_title,
                    metaId = R.id.widget_card_secondary_meta,
                    detailId = R.id.widget_card_secondary_detail,
                    progressId = R.id.widget_card_secondary_progress,
                    progressLabelId = R.id.widget_card_secondary_progress_label,
                    card = cards.getOrNull(1),
                )
                bindCard(
                    views = this,
                    context = context,
                    containerId = R.id.widget_card_tertiary,
                    statusId = R.id.widget_card_tertiary_status,
                    titleId = R.id.widget_card_tertiary_title,
                    metaId = R.id.widget_card_tertiary_meta,
                    detailId = R.id.widget_card_tertiary_detail,
                    progressId = R.id.widget_card_tertiary_progress,
                    progressLabelId = R.id.widget_card_tertiary_progress_label,
                    card = cards.getOrNull(2),
                )
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
