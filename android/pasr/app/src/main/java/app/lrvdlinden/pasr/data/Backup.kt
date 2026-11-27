package app.lrvdlinden.pasr.data

import android.content.Context
import android.net.Uri
import android.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

object Backup {
    private const val ITERATIONS = 310_000
    private const val MAX_FILE = 64 * 1024 * 1024
    private val photoSlots = setOf("front", "back", "note1", "note2", "note3", "note4")
    private val uuid = Regex("[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")

    @Serializable
    private data class Archive(val cards: List<SavedCard>, val receipts: List<SavedReceipt>)

    @Serializable
    private data class SavedCard(val card: Card, val photos: Map<String, String>)

    @Serializable
    private data class SavedReceipt(val receipt: Receipt, val pages: List<String>)

    @Serializable
    private data class Envelope(val format: String, val version: Int, val salt: String, val data: String)

    data class Restored(val cards: Int, val receipts: Int)

    fun write(context: Context, uri: Uri, password: String) {
        val archive = Archive(
            CardStore.visible.filter { it.groupId == null }.map { card ->
                val photos = card.photos.filter { it in photoSlots }.mapNotNull { slot ->
                    CardStore.photo(card.id, slot)?.let { slot to encode(it) }
                }.toMap()
                SavedCard(card, photos)
            },
            ReceiptStore.receipts.value.map { receipt ->
                val pages = (0 until receipt.pages.coerceIn(0, Receipt.MAX_PAGES))
                    .mapNotNull { ReceiptStore.pageBytes(receipt.id, it)?.let(::encode) }
                SavedReceipt(receipt, pages)
            },
        )
        val salt = ByteArray(16).also(SecureRandom()::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key(password, salt)) }
        val data = cipher.iv + cipher.doFinal(PasrJson.encodeToString(archive).encodeToByteArray())
        val envelope = Envelope("pasr-android-backup", 1, encode(salt), encode(data))
        val bytes = PasrJson.encodeToString(envelope).encodeToByteArray()
        require(bytes.size <= MAX_FILE)
        requireNotNull(context.contentResolver.openOutputStream(uri, "wt")).use { it.write(bytes) }
    }

    fun restore(context: Context, uri: Uri, password: String): Restored {
        val bytes = requireNotNull(context.contentResolver.openInputStream(uri)).use { it.readBounded(MAX_FILE) }
        val envelope = PasrJson.decodeFromString<Envelope>(bytes.decodeToString())
        require(envelope.format == "pasr-android-backup" && envelope.version == 1)
        val salt = decode(envelope.salt)
        val data = decode(envelope.data)
        require(salt.size == 16 && data.size >= 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(password, salt), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        }
        val plain = cipher.doFinal(data, 12, data.size - 12)
        val archive = PasrJson.decodeFromString<Archive>(plain.decodeToString())
        // Validate and decode all record payloads before writing anything into Pasr.
        val cards = archive.cards.map { saved ->
            require(saved.card.groupId == null && uuid.matches(saved.card.id) && saved.photos.keys.all { it in photoSlots })
            saved.card to saved.photos.mapValues { decode(it.value) }
        }
        val receipts = archive.receipts.map { saved ->
            require(uuid.matches(saved.receipt.id) && saved.pages.size <= Receipt.MAX_PAGES)
            saved.receipt to saved.pages.map(::decode)
        }

        val existingCodes = CardStore.visible.filter { it.number.isNotBlank() }
            .map { it.formatRaw to it.number }.toMutableSet()
        val matchedCards = mutableMapOf<String, String>()
        var cardCount = 0
        for ((card, photos) in cards) {
            val existing = CardStore.get(card.id) ?: CardStore.visible.firstOrNull {
                card.number.isNotBlank() && it.formatRaw == card.formatRaw && it.number == card.number
            }
            if (existing != null) {
                matchedCards[card.id] = existing.id
                continue
            }
            if (card.number.isNotBlank() && !existingCodes.add(card.formatRaw to card.number)) continue
            CardStore.upsert(card.copy(photos = emptyList(), deletedAt = null))
            photos.forEach { (slot, jpeg) -> CardStore.setPhoto(card.id, slot, jpeg) }
            matchedCards[card.id] = card.id
            cardCount++
        }
        var receiptCount = 0
        for ((receipt, pages) in receipts) {
            if (ReceiptStore.get(receipt.id) != null) continue
            val source = receipt.cardID
            val target = source?.let { matchedCards[it] ?: CardStore.get(it)?.id }
            val use = receipt.useID?.takeIf { id -> target?.let(CardStore::get)?.history?.any { it.id == id } == true }
            val restored = receipt.copy(cardID = target, useID = use)
            ReceiptStore.save(restored, pages)
            receiptCount++
        }
        return Restored(cardCount, receiptCount)
    }

    private fun key(password: String, salt: ByteArray): SecretKeySpec {
        val spec = PBEKeySpec(password.toCharArray(), salt, ITERATIONS, 256)
        return try {
            val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
            SecretKeySpec(bytes, "AES").also { bytes.fill(0) }
        } finally {
            spec.clearPassword()
        }
    }

    private fun encode(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun decode(value: String) = Base64.decode(value, Base64.NO_WRAP)
}
