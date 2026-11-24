package app.lrvdlinden.pasr.notify

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import androidx.core.content.ContextCompat
import app.lrvdlinden.pasr.data.CardStore
import app.lrvdlinden.pasr.data.Prefs
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.tasks.CancellationTokenSource
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.min

/** Winkelmeldingen zijn opt-in. Coördinaten en kaart-ID's blijven op het toestel. */
object NearbyStoresAndroid {
    const val PREF = "nearby.enabled"
    private const val PLACES = "pasr.nearby.places"
    private const val MAX_REGIONS = 90
    private const val GEOFENCE_RADIUS_METERS = 120f
    private const val ACCURACY_LIMIT = 50f
    private const val MAX_ERROR_MARGIN = 25f
    private const val CONFIRM_METERS = 5f
    private const val COOLDOWN_MS = 4 * 3600_000L
    private const val GLOBAL_COOLDOWN_MS = 120_000L
    private const val LAST_SHOWN = "pasr.nearby.lastshown"
    private const val LAST_ANY = "pasr.nearby.lastany"

    fun enabled(): Boolean = Prefs.bool(PREF)
    fun available(context: Context): Boolean =
        GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    fun hasLocation(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED &&
        (Build.VERSION.SDK_INT < 29 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
                PackageManager.PERMISSION_GRANTED)

    fun ready(context: Context): Boolean = hasLocation(context) && Reminders.canNotify(context) && available(context)

    fun monitoredCount(context: Context): Int =
        context.getSharedPreferences("nearby.android",Context.MODE_PRIVATE).getString(PLACES,"[]")
            ?.let { runCatching { JSONArray(it).length() }.getOrDefault(0) } ?: 0

    private fun pending(context: Context): PendingIntent {
        val intent = Intent(context, NearbyGeofenceReceiver::class.java).setAction("app.lrvdlinden.pasr.NEARBY_GEOFENCE")
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(context, 12743, intent, flags)
    }

    fun setEnabled(context: Context, enabled: Boolean) {
        Prefs.setBool(PREF, enabled && ready(context))
        sync(context)
    }

    /** Herregistreer bij openen en na kaartwijzigingen. Geen permanent draaiende achtergrondservice. */
    @Suppress("MissingPermission")
    fun sync(context: Context) {
        val client = LocationServices.getGeofencingClient(context)
        val pi = pending(context)
        if (!enabled() || !ready(context)) {
            if (!ready(context)) Prefs.setBool(PREF, false)
            context.getSharedPreferences("nearby.android",Context.MODE_PRIVATE).edit().remove(PLACES).apply()
            client.removeGeofences(pi)
            return
        }
        // Eigen opgeslagen winkelspelden, met dezelfde kaart-ID als op het kaartenscherm.
        val locations = CardStore.visible
            .filter { it.places.isNotEmpty() }
            .flatMap { c -> c.places.map { p ->
                JSONObject().put("key", c.id + "|" + p.id)
                    .put("card",c.id).put("store",c.storeName)
                    .put("lat",p.latitude).put("lon",p.longitude)
            } }
            .distinctBy { it.getString("key") }
            .take(MAX_REGIONS)
        val prefs = context.getSharedPreferences("nearby.android",Context.MODE_PRIVATE)
        prefs.edit().putString(PLACES,JSONArray(locations).toString()).apply()
        client.removeGeofences(pi).addOnCompleteListener {
            if (locations.isEmpty() || !enabled() || !ready(context)) return@addOnCompleteListener
            try {
                val fences=locations.map { p ->
                    Geofence.Builder().setRequestId(p.getString("key"))
                        .setCircularRegion(p.getDouble("lat"),p.getDouble("lon"),GEOFENCE_RADIUS_METERS)
                        .setExpirationDuration(Geofence.NEVER_EXPIRE)
                        .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER).build()
                }
                val req=GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                    .addGeofences(fences).build()
                client.addGeofences(req,pi)
            } catch (_: SecurityException) { Prefs.setBool(PREF,false) }
        }
    }

    internal fun handle(context: Context, event: GeofencingEvent, result: BroadcastReceiver.PendingResult) {
        if (!enabled() || !ready(context) || event.hasError() ||
            event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) {
            result.finish();return
        }
        val ids=event.triggeringGeofences?.map { it.requestId }?.toSet().orEmpty()
        if (ids.isEmpty()) { result.finish();return }
        // Bestaande geofencepositie kan honderden meters onnauwkeurig zijn; meet nauwkeurig bij entry.
        try {
            val request=CurrentLocationRequest.Builder().setPriority(Priority.PRIORITY_HIGH_ACCURACY)
                .setDurationMillis(8000L).setMaxUpdateAgeMillis(4000L).build()
            LocationServices.getFusedLocationProviderClient(context)
                .getCurrentLocation(request,CancellationTokenSource().token)
                .addOnSuccessListener { location ->
                    try { if (location != null) notifyIfAtStore(context,ids,location) }
                    finally { result.finish() }
                }
                .addOnFailureListener { result.finish() }
                .addOnCanceledListener { result.finish() }
        } catch (_: Exception) { result.finish() }
    }

    private fun notifyIfAtStore(context: Context, ids: Set<String>, position: Location) {
        if (!position.hasAccuracy() || position.accuracy < 0 || position.accuracy > ACCURACY_LIMIT ||
            (position.hasSpeed() && position.speed > 2.5f) ||
            System.currentTimeMillis() - position.time > 30_000L) return
        val now=System.currentTimeMillis()
        val prefs=context.getSharedPreferences("nearby.android",Context.MODE_PRIVATE)
        if (now-prefs.getLong(LAST_ANY,0L) < GLOBAL_COOLDOWN_MS) return
        val places=JSONArray(prefs.getString(PLACES,"[]") ?: "[]")
        var best: JSONObject?=null
        var closest=Float.MAX_VALUE
        for (i in 0 until places.length()) {
            val p=places.optJSONObject(i) ?: continue
            if (p.optString("key") !in ids) continue
            val dist=FloatArray(1)
            Location.distanceBetween(position.latitude,position.longitude,
                p.getDouble("lat"),p.getDouble("lon"),dist)
            if (dist[0] <= CONFIRM_METERS+min(position.accuracy,MAX_ERROR_MARGIN) &&
                dist[0] < closest) { best=p;closest=dist[0] }
        }
        val match=best ?: return
        val store=match.optString("store")
        val lastKey=LAST_SHOWN + store.lowercase().filter { it.isLetterOrDigit() }
        if (now-prefs.getLong(lastKey,0L) < COOLDOWN_MS) return
        Reminders.notify(context,"nearby-store",Reminders.CHANNEL_NEARBY,
            "Je bent bij $store","Tik om je kaart te tonen.",match.optString("card"))
        prefs.edit().putLong(lastKey,now).putLong(LAST_ANY,now).apply()
    }
}

/** Geofence-signalen zijn alleen een aanleiding tot GPS-verificatie, geen directe melding. */
class NearbyGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result=goAsync()
        try {
            val event=GeofencingEvent.fromIntent(intent)
            if (event == null) result.finish()
            else NearbyStoresAndroid.handle(context.applicationContext,event,result)
        } catch (_: Exception) { result.finish() }
    }
}
