package me.studyshare.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class ScheduleWidgetRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return ScheduleWidgetRemoteViewsFactory(applicationContext)
    }
}

private class ScheduleWidgetRemoteViewsFactory(
    private val context: Context
) : RemoteViewsService.RemoteViewsFactory {
    private val widgetData = HomeWidgetPlugin.getData(context)
    private val cards = mutableListOf<ScheduleWidgetCard>()

    override fun onCreate() {
        loadCards()
    }

    override fun onDataSetChanged() {
        loadCards()
    }

    override fun onDestroy() {
        cards.clear()
    }

    override fun getCount(): Int = cards.size

    override fun getViewAt(position: Int): RemoteViews? {
        val card = cards.getOrNull(position) ?: return null
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_item)

        views.setTextViewText(R.id.widget_card_status, card.status)
        views.setTextViewText(R.id.widget_card_title, card.title)
        views.setTextViewText(R.id.widget_card_meta, card.meta)
        views.setTextViewText(R.id.widget_card_detail, card.detail)
        views.setTextViewText(R.id.widget_card_progress_label, card.progressLabel)
        views.setViewVisibility(
            R.id.widget_card_status,
            if (card.status.isBlank()) View.GONE else View.VISIBLE,
        )
        views.setViewVisibility(
            R.id.widget_card_detail,
            if (card.detail.isBlank()) View.GONE else View.VISIBLE,
        )
        views.setViewVisibility(
            R.id.widget_card_progress,
            if (card.isLive) View.VISIBLE else View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_card_progress_label,
            if (card.isLive && card.progressLabel.isNotBlank()) View.VISIBLE else View.GONE,
        )
        views.setProgressBar(
            R.id.widget_card_progress,
            100,
            card.progress.coerceIn(0, 100),
            false,
        )
        views.setTextColor(
            R.id.widget_card_status,
            ContextCompat.getColor(
                context,
                if (card.isLive) R.color.widget_schedule_live_accent
                else R.color.widget_schedule_hint_text,
            ),
        )

        val fillInIntent = Intent().apply {
            data = Uri.parse(card.targetUri)
        }
        views.setOnClickFillInIntent(R.id.widget_card_container, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long {
        return cards.getOrNull(position)?.targetUri?.hashCode()?.toLong()
            ?: position.toLong()
    }

    override fun hasStableIds(): Boolean = true

    private fun loadCards() {
        cards.clear()
        val raw = widgetData.getString("schedule_cards_json", "[]") ?: "[]"
        val json = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }

        for (index in 0 until json.length()) {
            val item = json.optJSONObject(index) ?: continue
            cards.add(
                ScheduleWidgetCard(
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
        }
    }
}

private data class ScheduleWidgetCard(
    val status: String,
    val title: String,
    val meta: String,
    val detail: String,
    val progress: Int,
    val progressLabel: String,
    val isLive: Boolean,
    val targetUri: String,
)
