package app.lrvdlinden.pasrzakelijk.core

import android.content.Context
import android.location.Geocoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale

/** Adres → plek (lat/lng) via de geocoder van Android, voor "In de buurt" in Pasr. Niets wordt bewaard behalve wat je opslaat. */
object Geo {
    suspend fun locate(context: Context, address: String): Pair<Double, Double>? = withContext(Dispatchers.IO) {
        val query = address.trim()
        if (query.length < 4 || !Geocoder.isPresent()) return@withContext null
        runCatching {
            @Suppress("DEPRECATION")
            Geocoder(context, Locale("nl", "NL")).getFromLocationName(query, 1)?.firstOrNull()?.let { it.latitude to it.longitude }
        }.getOrNull()
    }
}
