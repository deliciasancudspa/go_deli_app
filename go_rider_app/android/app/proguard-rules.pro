# ── GoRider ProGuard / R8 rules ───────────────────────────────────────────
# Generated for Google Play production builds

# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Supabase (Gotrue + PostgREST + Realtime)
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
-keep class com.supabase.** { *; }

# Google Maps
-keep class com.google.android.libraries.** { *; }
-dontwarn com.google.android.libraries.**

# Audio players (ExoPlayer)
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# Kotlin serialization (usado por Supabase)
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.godeli.go_rider.**$$serializer { *; }
-keepclassmembers class com.godeli.go_rider.** {
    *** Companion;
}
-keepclasseswithmembers class com.godeli.go_rider.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep data classes used by Supabase serialization
-keep class com.godeli.go_rider.** { *; }

# General Android
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes SourceFile,LineNumberTable
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
