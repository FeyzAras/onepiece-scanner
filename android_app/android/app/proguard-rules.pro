# Das ML-Kit-Text-Plugin verweist auf Erkenner fuer Chinesisch, Japanisch, Koreanisch und
# Devanagari. Diese App nutzt nur die lateinische Schrift, deshalb sind die zugehoerigen
# Bibliotheken nicht eingebunden - R8 soll die fehlenden Verweise ignorieren statt abzubrechen.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit laedt Teile erst zur Laufzeit ueber Reflection. Wird R8 wieder eingeschaltet
# (siehe build.gradle.kts), muessen diese Klassen vollstaendig erhalten bleiben - sonst
# scheitert die Bilduebergabe mit einer NullPointerException.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
