package me.studyshare.android

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class SyllabusWidgetProvider : HomeWidgetProvider() {
    private fun launchPendingIntent(
        context: Context,
        uri: Uri? = null,
    ): PendingIntent {
        return HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.syllabus_widget_layout).apply {
                val scheduleUri = Uri.parse("studyshare://widget/schedule?view=attendance")
                val scheduleBadge = widgetData.getString(
                    "schedule_badge",
                    "LIVE NOW",
                )
                val scheduleLocationLabel = widgetData.getString(
                    "schedule_location_label",
                    "Current Class Location",
                )
                val scheduleRoomLabel = widgetData.getString(
                    "schedule_room_label",
                    "Schedule",
                )
                val scheduleFooterLabel = widgetData.getString(
                    "schedule_footer_label",
                    "Swipe for next class",
                )
                val scheduleEmpty = widgetData.getString(
                    "schedule_empty_message",
                    "No schedule data yet. Open StudyShare to connect attendance.",
                )
                val cardCount = widgetData.getInt("schedule_indicator_count", 0)
                val isLive = widgetData.getBoolean("schedule_is_live", false)

                setTextViewText(R.id.widget_chip, scheduleBadge ?: "LIVE NOW")
                setTextViewText(
                    R.id.widget_location_label,
                    scheduleLocationLabel ?: "Current Class Location",
                )
                setTextViewText(
                    R.id.widget_title,
                    scheduleRoomLabel ?: "Schedule",
                )
                setTextViewText(
                    R.id.widget_empty_message,
                    scheduleEmpty
                        ?: "No schedule data yet. Open StudyShare to connect attendance.",
                )
                setTextViewText(
                    R.id.widget_swipe_hint,
                    scheduleFooterLabel ?: "Swipe for next class",
                )
                setViewVisibility(
                    R.id.widget_live_dot,
                    if (isLive) android.view.View.VISIBLE else android.view.View.INVISIBLE,
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
                    R.id.widget_footer_row,
                    if (cardCount > 0) android.view.View.VISIBLE else android.view.View.GONE,
                )
                setViewVisibility(
                    R.id.widget_indicator_secondary,
                    if (cardCount > 1) android.view.View.VISIBLE else android.view.View.GONE,
                )
                setViewVisibility(
                    R.id.widget_indicator_tertiary,
                    if (cardCount > 2) android.view.View.VISIBLE else android.view.View.GONE,
                )

                val serviceIntent = Intent(context, ScheduleWidgetRemoteViewsService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
                setRemoteAdapter(R.id.widget_stack, serviceIntent)
                setEmptyView(R.id.widget_stack, R.id.widget_empty_message)
                setPendingIntentTemplate(
                    R.id.widget_stack,
                    launchPendingIntent(context),
                )
                setOnClickPendingIntent(
                    R.id.widget_container,
                    launchPendingIntent(context, scheduleUri)
                )
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(
                intArrayOf(appWidgetId),
                R.id.widget_stack,
            )
        }
    }
}
