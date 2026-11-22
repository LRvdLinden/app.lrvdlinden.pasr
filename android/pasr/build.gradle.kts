plugins {
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
    // Push via Firebase Cloud Messaging; alleen toegepast als app/google-services.json er is (de workflow schrijft hem)
    id("com.google.gms.google-services") version "4.4.2" apply false
}
