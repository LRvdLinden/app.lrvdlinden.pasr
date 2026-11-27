package app.lrvdlinden.pasr.data

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-256-GCM met een sleutel in de Android Keystore: kaarten, foto's en de sessie staan versleuteld op het toestel. */
object Crypto {
    private const val ALIAS = "pasr.store.v1"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    fun encrypt(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        return c.iv + c.doFinal(plain)
    }

    fun decrypt(data: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        return c.doFinal(data, 12, data.size - 12)
    }

    fun encryptString(s: String): String = Base64.encodeToString(encrypt(s.toByteArray()), Base64.NO_WRAP)
    fun decryptString(s: String): String? = runCatching { String(decrypt(Base64.decode(s, Base64.NO_WRAP))) }.getOrNull()
}

val PasrJson = Json { ignoreUnknownKeys = true; encodeDefaults = false; explicitNulls = false; coerceInputValues = true }

/** Instellingen en kleine status (geen geheimen; de sessie gaat versleuteld). */
object Prefs {
    lateinit var p: SharedPreferences
    fun init(context: Context) { p = context.getSharedPreferences("pasr", Context.MODE_PRIVATE) }

    var onboarded: Boolean
        get() = p.getBoolean("onboarded", false)
        set(v) = p.edit().putBoolean("onboarded", v).apply()
    var lockEnabled: Boolean
        get() = p.getBoolean("lock", false)
        set(v) = p.edit().putBoolean("lock", v).apply()
    var remindersEnabled: Boolean
        get() = p.getBoolean("reminders", true)
        set(v) = p.edit().putBoolean("reminders", v).apply()
    var order: CardOrder
        get() = CardOrder.of(p.getString("order", null))
        set(v) = p.edit().putString("order", v.raw).apply()
    var appearance: String
        get() = p.getString("appearance", "auto") ?: "auto"
        set(v) = p.edit().putString("appearance", v).apply()
    var brightness: Boolean
        get() = p.getBoolean("brightness", true)
        set(v) = p.edit().putBoolean("brightness", v).apply()

    /** Willekeurige id van deze installatie (voor de apparaatregistratie; geen persoonsgegeven). */
    val deviceId: String
        get() = p.getString("device", null) ?: newId().replace("-", "").lowercase().also { p.edit().putString("device", it).apply() }

    fun string(key: String): String? = p.getString(key, null)
    fun setString(key: String, value: String?) = p.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun long(key: String): Long = p.getLong(key, 0L)
    fun setLong(key: String, value: Long) = p.edit().putLong(key, value).apply()
    fun bool(key: String): Boolean = p.getBoolean(key, false)
    fun setBool(key: String, value: Boolean) = p.edit().putBoolean(key, value).apply()
}

/** Alle kaarten, versleuteld in één bestand. Foto's als losse versleutelde bestanden. */
object CardStore {
    private lateinit var widgetContext: Context
    private lateinit var file: File
    private lateinit var photoDir: File
    private val _cards = MutableStateFlow<List<Card>>(emptyList())
    val cards: StateFlow<List<Card>> = _cards.asStateFlow()

    fun init(context: Context) {
        widgetContext = context.applicationContext
        file = File(context.filesDir, "cards.enc")
        photoDir = File(context.filesDir, "photos").apply { mkdirs() }
        _cards.value = load()
        purgeOld()
    }

    private fun load(): List<Card> = runCatching {
        if (!file.exists()) return emptyList()
        PasrJson.decodeFromString<List<Card>>(String(Crypto.decrypt(file.readBytes())))
    }.getOrElse { emptyList() }

    @Synchronized
    private fun persist(list: List<Card>) {
        _cards.value = list
        val tmp = File(file.parentFile, "cards.enc.tmp")
        tmp.writeBytes(Crypto.encrypt(PasrJson.encodeToString(list).toByteArray()))
        tmp.renameTo(file)
        app.lrvdlinden.pasr.updateCardWidgets(widgetContext)
        app.lrvdlinden.pasr.QuickAccess.updateShortcuts(widgetContext)
    }

    val visible: List<Card> get() = _cards.value.filter { it.deletedAt == null }
    val recentlyDeleted: List<Card> get() = _cards.value.filter { it.deletedAt != null }

    fun get(id: String): Card? = _cards.value.firstOrNull { it.id.equals(id, ignoreCase = true) }

    @Synchronized
    fun upsert(card: Card, touch: Boolean = true) {
        val c = if (touch) card.copy(updatedAt = nowMs()) else card
        val list = _cards.value.toMutableList()
        val i = list.indexOfFirst { it.id.equals(c.id, ignoreCase = true) }
        if (i >= 0) list[i] = c else list.add(c)
        persist(list)
    }

    @Synchronized
    fun replaceAll(list: List<Card>) = persist(list)

    @Synchronized
    fun discardGroups(allowed: Set<String>) {
        val removed = _cards.value.filter { it.groupId != null && it.groupId !in allowed }
        if (removed.isEmpty()) return
        val ids = removed.map { it.id }.toSet()
        removed.forEach { card -> card.photos.forEach { photoFile(card.id, it).delete() } }
        persist(_cards.value.filterNot { it.id in ids })
    }

    /** Naar Recent verwijderd (30 dagen). */
    fun delete(id: String) { get(id)?.let { upsert(it.copy(deletedAt = nowMs()), touch = false) } }
    fun restore(id: String) { get(id)?.let { upsert(it.copy(deletedAt = null)) } }

    @Synchronized
    fun purge(id: String) {
        get(id)?.photos?.forEach { photoFile(id, it).delete() }
        persist(_cards.value.filterNot { it.id.equals(id, ignoreCase = true) })
    }

    private fun purgeOld() {
        val cutoff = nowMs() - 30L * 86_400_000
        _cards.value.filter { (it.deletedAt ?: Long.MAX_VALUE) < cutoff }.forEach { purge(it.id) }
    }

    // ---- foto's ----
    private fun photoFile(id: String, slot: String) = File(photoDir, "${id.lowercase()}-$slot.enc")
    fun photo(id: String, slot: String): ByteArray? = runCatching { Crypto.decrypt(photoFile(id, slot).readBytes()) }.getOrNull()
    fun setPhoto(id: String, slot: String, jpeg: ByteArray?) {
        val f = photoFile(id, slot)
        if (jpeg == null) f.delete() else f.writeBytes(Crypto.encrypt(jpeg))
        get(id)?.let { c ->
            val slots = (c.photos - slot) + (if (jpeg != null) listOf(slot) else emptyList())
            upsert(c.copy(photos = slots.distinct()))
        }
    }

    /** Alles op dit toestel wissen (Instellingen › Alle kaarten wissen). */
    fun wipe() {
        photoDir.listFiles()?.forEach { it.delete() }
        persist(emptyList())
    }
}
