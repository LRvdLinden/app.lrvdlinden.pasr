plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
    // Alleen voor de previews (./gradlew -Ppreviews recordPaparazziDebug); de APK-build gebruikt hem niet.
    id("app.cash.paparazzi") version "1.3.5" apply false
}
