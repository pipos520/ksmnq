# Card Market ProGuard Rules

# Keep data classes (JSON serialization)
-keep class com.pipahua.cardmarket.CardInfo { *; }
-keep class com.pipahua.cardmarket.ApiResult { *; }
-keep class com.pipahua.cardmarket.MarketItem { *; }
-keep class com.pipahua.cardmarket.MarketResult { *; }
-keep class com.pipahua.cardmarket.Receipt { *; }
-keep class com.pipahua.cardmarket.PackStatus { *; }
-keep class com.pipahua.cardmarket.SyncResult { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**

# Kotlin coroutines
-keepclassmembers class kotlinx.coroutines.** { *; }
