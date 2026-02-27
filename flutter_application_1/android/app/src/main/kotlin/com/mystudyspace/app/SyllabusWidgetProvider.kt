package com.mystudyspace.app

import android.appwidget.AppWidgetManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import me.mystudyspace.android.R
import me.mystudyspace.android.MainActivity
import es.antonborri.home_widget.HomeWidgetProvider

class SyllabusWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.syllabus_widget_layout).apply {
                val syllabusTitle = widgetData.getString("syllabus_title", "Syllabus")
                val syllabusData = widgetData.getString("syllabus_data", "No recent syllabus items.")
                setTextViewText(R.id.widget_title, syllabusTitle)
                setTextViewText(R.id.widget_message, syllabusData)

                val intent = Intent(context, MainActivity::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, appWidgetId, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
