# ── GoDeli ProGuard / R8 rules ───────────────────────────────────────────
# Modo completo con reglas mínimas necesarias para mayor optimización

# Flutter — solo lo esencial
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# Firebase (necesario para inicialización por reflexión)
-keep class com.google.firebase.FirebaseApp { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.installations.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Supabase — HTTP client + serialización
-keep class io.supabase.gotrue.** { *; }
-keep class io.supabase.postgrest.** { *; }
-keep class io.supabase.realtime.** { *; }
-dontwarn io.supabase.**
-dontwarn com.supabase.**

# Google Maps
-keep class com.google.android.libraries.maps.** { *; }
-dontwarn com.google.android.libraries.**

# Google Sign-In
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.auth.**

# Audio players (ExoPlayer — necesario para reproducción de audio)
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# WebView (usado para Webpay)
-keep class android.webkit.** { *; }
-dontwarn android.webkit.**

# Image picker
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# App-specific — necesario para Supabase data classes
-keep class com.godeli.go_deli.** { *; }

# Android essentials
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver

# Evitar warnings de clases que no existen en el classpath
-dontwarn javax.annotation.**
-dontwarn kotlin.Unit
-dontwarn retrofit2.**
