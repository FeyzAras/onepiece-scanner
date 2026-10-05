# Das ML-Kit-Text-Plugin verweist auf Erkenner fuer Chinesisch, Japanisch, Koreanisch und
# Devanagari. Diese App nutzt nur die lateinische Schrift, deshalb sind die zugehoerigen
# Bibliotheken nicht eingebunden - R8 soll die fehlenden Verweise ignorieren statt abzubrechen.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Die lateinische Variante bleibt vollstaendig erhalten.
-keep class com.google.mlkit.vision.text.latin.** { *; }
