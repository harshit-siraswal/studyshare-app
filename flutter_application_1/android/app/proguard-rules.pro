# ============================================
# Flutter Wrapper (Essential)
# ============================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.**

# ============================================
# Supabase & Postgrest (CRITICAL for data loading)
# ============================================
-keep class io.supabase.** { *; }
-keep class io.github.jan.supabase.** { *; }
-keep class com.supabase.** { *; }
-keep class androidx.lifecycle.** { *; }
-dontwarn io.supabase.**
-dontwarn io.github.jan.supabase.**

# Keep Supabase client and response models
-keep class * extends io.supabase.postgrest.** { *; }
-keep class * implements io.supabase.postgrest.** { *; }

# ============================================
# JSON Serialization (CRITICAL - Supabase uses this)
# ============================================
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Gson (used by Supabase/Postgrest)
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Keep model classes that are serialized/deserialized
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ============================================
# OkHttp & Networking (Supabase uses this)
# ============================================
-dontwarn okhttp3.**
-dontwarn okio.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# ============================================
# Firebase & Google Services
# ============================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ============================================
# Retrofit (if used by any dependencies)
# ============================================
-keep class retrofit2.** { *; }
-keep interface retrofit2.** { *; }
-dontwarn retrofit2.**
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# ============================================
# AndroidX & Support Libraries
# ============================================
-keep class androidx.** { *; }
-dontwarn androidx.**

# ============================================
# App-Specific Models (Keep your data models)
# ============================================
# Keep all classes in your app package
-keep class me.studyshare.android.** { *; }

# Keep model classes that might be serialized
-keepclassmembers class * {
    <fields>;
}

# ============================================
# Native Methods & Reflection
# ============================================
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ============================================
# WebView & Browser (for OAuth)
# ============================================
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void *(android.webkit.WebView, java.lang.String);
}

# ============================================
# General Rules
# ============================================
# Keep line numbers for debugging
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Don't warn about missing classes (some are optional)
-dontwarn javax.annotation.**
-dontwarn javax.inject.**
-dontwarn kotlin.**
-dontwarn kotlinx.**
