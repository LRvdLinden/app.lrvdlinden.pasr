package app.lrvdlinden.pasr

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import app.lrvdlinden.pasr.data.Card
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Prefs

/**
 * Snel bij een kaart op Android, de tegenhanger van Apple Wallet (dubbelklik) en Siri-suggesties op de iPhone:
 * - een tegel in Snelle instellingen ("Pasr-kaart") die je favoriete of meest gebruikte kaart opent, ook vanaf het
 *   vergrendelscherm (na ontgrendelen);
 * - app-snelkoppelingen (lang drukken op het Pasr-icoon, of "Open … in Pasr" via de assistent) naar je drie meest
 *   gebruikte kaarten.
 * Met het app-slot of "Screenshots blokkeren" aan tonen tegel en snelkoppelingen geen winkelnamen.
 */
object QuickAccess {
    private val privateMode get() = Prefs.lockEnabled || Prefs.bool("screen.block")

    /** Kaarten voor snelle toegang: favorieten eerst, daarna meest gebruikt. */
    fun cards(): List<Card> {
        val usable = CardStore.visible.filter { !it.isLocked && !it.isExpired }
        val favorites = usable.filter { it.isFavorite }
        val used = usable.filter { it.useCount > 0 && !it.isFavorite }.sortedByDescending { Card.score(it) }
        return (favorites + used).distinctBy { it.id }
    }

    fun openIntent(context: Context, card: Card?): Intent =
        Intent(context, MainActivity::class.java)
            .setAction("app.lrvdlinden.pasr.OPEN_CARD." + (card?.id ?: "home"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .apply { card?.let { putExtra("cardId", it.id) } }

    /** Dynamische snelkoppelingen bijwerken (na elke wijziging aan de kaarten). */
    fun updateShortcuts(context: Context) {
        runCatching {
            if (privateMode) { ShortcutManagerCompat.removeAllDynamicShortcuts(context); return }
            val max = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context).coerceAtMost(4) - 2
            val list = cards().take(max.coerceIn(0, 3)).mapIndexed { i, card ->
                ShortcutInfoCompat.Builder(context, "card-" + card.id)
                    .setShortLabel(card.storeName.take(24))
                    .setLongLabel(("Toon " + card.storeName).take(40))
                    .setIcon(IconCompat.createWithResource(context, R.mipmap.ic_launcher))
                    .setIntent(openIntent(context, card))
                    .setRank(i)
                    .build()
            }
            ShortcutManagerCompat.setDynamicShortcuts(context, list)
        }
    }
}

/** Tegel in Snelle instellingen: één tik opent je favoriete (of meest gebruikte) kaart. */
class CardTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        val card = QuickAccess.cards().firstOrNull()
        tile.label = "Pasr-kaart"
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = when {
                Prefs.lockEnabled || Prefs.bool("screen.block") -> "Open Pasr"
                card != null -> card.storeName
                else -> "Open Pasr"
            }
        }
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val intent = QuickAccess.openIntent(this, QuickAccess.cards().firstOrNull())
        val open = {
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 7, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            } else {
                @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
                startActivityAndCollapse(intent)
            }
        }
        if (isLocked) unlockAndRun { open() } else open()
    }
}
