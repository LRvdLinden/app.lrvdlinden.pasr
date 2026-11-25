package app.lrvdlinden.pasr

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Prefs

class FavoriteCardsWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateCardWidgets(context)
    }
}

class FrequentCardsWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        updateCardWidgets(context)
    }
}

internal fun updateCardWidgets(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    val available = CardStore.visible.filter { !it.isLocked && !it.isExpired }
    val groups = listOf(
        Triple(FavoriteCardsWidget::class.java, "Favoriete kaarten", available.filter { it.isFavorite }),
        Triple(FrequentCardsWidget::class.java, "Meest gebruikt", available.filter { it.useCount > 0 }.sortedByDescending { it.useCount }),
    )
    for ((provider, title, cards) in groups) {
        for (widgetId in manager.getAppWidgetIds(ComponentName(context, provider))) {
            val views = RemoteViews(context.packageName, R.layout.pasr_widget)
            views.setTextViewText(R.id.widget_title, title)
            val privateMode = Prefs.lockEnabled || Prefs.bool("screen.block")
            val rows = listOf(R.id.widget_first, R.id.widget_second, R.id.widget_third)
            for ((index, row) in rows.withIndex()) {
                val card = cards.getOrNull(index).takeUnless { privateMode }
                val visible = card != null || index == 0
                views.setViewVisibility(row, if (visible) View.VISIBLE else View.GONE)
                if (!visible) continue
                views.setTextViewText(row, card?.storeName ?: if (privateMode) "Open Pasr om je kaarten te bekijken" else "Open Pasr")
                val intent = Intent(context, MainActivity::class.java).setAction("app.lrvdlinden.pasr.WIDGET.$widgetId.$index")
                if (card != null) intent.putExtra("cardId", card.id)
                val pending = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                views.setOnClickPendingIntent(row, pending)
            }
            manager.updateAppWidget(widgetId, views)
        }
    }
}
