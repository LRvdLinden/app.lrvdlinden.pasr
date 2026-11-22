# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class app.lrvdlinden.pasr.data.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class app.lrvdlinden.pasr.data.**$$serializer { *; }
-keepclassmembers @kotlinx.serialization.Serializable class app.lrvdlinden.pasr.data.** { *; }
