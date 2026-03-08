package me.studyshare.android

import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

internal object WidgetLayoutBinder {
    private val itemViewIds = intArrayOf(
        R.id.widget_item_1,
        R.id.widget_item_2,
        R.id.widget_item_3,
    )

    fun bind(
        views: RemoteViews,
        dataPrefix: String,
        title: String,
        subtitle: String,
        emptyMessage: String,
        widgetData: SharedPreferences,
    ) {
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_subtitle, subtitle)
        views.setTextViewText(R.id.widget_empty_message, emptyMessage)

        val items = mutableListOf<String>()
        for (index in itemViewIds.indices) {
            val value = widgetData
                .getString("${dataPrefix}_item_${index + 1}", null)
                ?.trim()
            if (!value.isNullOrEmpty()) {
                items.add(value)
            }
        }

        val hasItems = items.isNotEmpty()
        views.setViewVisibility(
            R.id.widget_list_container,
            if (hasItems) View.VISIBLE else View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_empty_message,
            if (hasItems) View.GONE else View.VISIBLE,
        )

        itemViewIds.forEachIndexed { index, viewId ->
            val itemText = items.getOrNull(index)
            views.setTextViewText(viewId, itemText ?: "")
            views.setViewVisibility(
                viewId,
                if (itemText == null) View.GONE else View.VISIBLE,
            )
        }
    }
}
